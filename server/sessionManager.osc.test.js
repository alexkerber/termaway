// Runnable self-check for OSC notification parsing.
//   node --test server/sessionManager.osc.test.js
// The interesting case isn't the happy path — it's a sequence split across two
// PTY reads, which is why this can't be a substring match.
import assert from "assert";
import SessionManager from "./sessionManager.js";

const BEL = "\x07";
const ST = "\x1b\\";

const sm = new SessionManager();
const raised = [];
sm.onAttentionChange = (session, meta) => raised.push({ ...meta });

// A stand-in for a session: _scanAttention only needs the carry field,
// and markAttention only needs the map entry.
function session(name) {
  const s = {
    name,
    ephemeral: false,
    needsAttention: false,
    oscCarry: "",
    lastOscNotifyAt: 0,
  };
  sm.sessions.set(name, s);
  return s;
}

/** Feed chunks the way a PTY would, and report what attention was raised. */
function feed(s, ...chunks) {
  raised.length = 0;
  for (const chunk of chunks) {
    const { notification, bell } = sm._scanAttention(s, chunk);
    if (notification) {
      sm.markAttention(s.name, {
        source: "notify",
        title: notification.title || s.name,
        body: notification.body,
      });
    } else if (bell) {
      sm.markAttention(s.name, { source: "bell" });
    }
  }
  return raised;
}

// --- OSC 9: a message with no title of its own ------------------------------
let s = session("a");
let out = feed(s, `\x1b]9;Build finished${BEL}`);
assert.deepEqual(
  out.map((e) => [e.source, e.title, e.body]),
  [["notify", "a", "Build finished"]],
  "OSC 9 should raise a notify carrying the message, titled with the session",
);

// --- OSC 777: title and body ------------------------------------------------
s = session("b");
out = feed(s, `\x1b]777;notify;Codex;Needs your approval${BEL}`);
assert.deepEqual(
  out.map((e) => [e.source, e.title, e.body]),
  [["notify", "Codex", "Needs your approval"]],
);

// A body containing semicolons stays intact.
s = session("c");
out = feed(s, `\x1b]777;notify;Deploy;staging;then production${BEL}`);
assert.equal(out[0].body, "staging;then production");

// --- OSC 9 is multiplexed: sub-commands are not notifications ---------------
// iTerm2 sends progress as 9;4;state;percent, ConEmu uses 9;<digit>; for other
// things. Treating those as messages meant an alert on every progress tick.
s = session("p");
assert.deepEqual(feed(s, `\x1b]9;4;1;50${BEL}`), [], "iTerm2 progress must be ignored");
assert.deepEqual(feed(s, `\x1b]9;1;something${BEL}`), [], "ConEmu 9;1 must be ignored");
assert.deepEqual(feed(s, `\x1b]9;12${BEL}`), [], "a two-digit sub-command too");
assert.deepEqual(feed(s, `\x1b]9;10;x${BEL}`), [], "and its multi-part form");
assert.deepEqual(feed(s, `\x1b]9;${BEL}`), [], "an empty message is not a notification");
// A real message that merely starts with a digit still works.
out = feed(s, `\x1b]9;3 tests failed${BEL}`);
assert.equal(out[0].body, "3 tests failed");

// --- ST terminator, not just BEL --------------------------------------------
s = session("d");
out = feed(s, `\x1b]9;Done${ST}`);
assert.equal(out.length, 1, "ESC \\\\ terminates a sequence too");
assert.equal(out[0].body, "Done");

// --- split across reads: the whole reason this is stateful ------------------
s = session("e");
out = feed(s, "\x1b]777;notify;Cla", `ude;Finished${BEL}`);
assert.deepEqual(
  out.map((e) => [e.title, e.body]),
  [["Claude", "Finished"]],
  "a sequence split mid-payload must still be recognised",
);

// Split at the worst possible place — between ESC and ].
s = session("f");
out = feed(s, "output\x1b", `]9;Split at the bracket${BEL}`);
assert.equal(out.length, 1);
assert.equal(out[0].body, "Split at the bracket");

// --- the terminating BEL must not also fire a blank bell --------------------
s = session("g");
out = feed(s, `\x1b]9;Only once${BEL}`);
assert.equal(out.length, 1, "an OSC's own BEL must not raise a second alert");

// --- a bare bell still works ------------------------------------------------
s = session("h");
out = feed(s, `some output${BEL}`);
assert.deepEqual(
  out.map((e) => e.source),
  ["bell"],
);

// --- ordinary output is not mistaken for a notification ---------------------
s = session("i");
out = feed(s, "\x1b]0;window title\x07", "\x1b[31mred\x1b[0m", "plain text");
assert.deepEqual(out, [], "OSC 0 (window title) and SGR must be ignored");
assert.equal(s.oscCarry, "", "nothing should be left carried");

// --- an OSC that never terminates must not grow memory ----------------------
// It collapses to the two bytes that say "still inside a sequence" rather than
// to nothing: forgetting that is what let the terminator ring as a bell.
s = session("j");
feed(s, "\x1b]9;" + "x".repeat(5000));
assert.equal(s.oscCarry, "\x1b]", "an oversized sequence collapses but is remembered");

// A partial sequence within the cap is kept, waiting for the rest.
s = session("k");
feed(s, "\x1b]9;still going");
assert.ok(s.oscCarry.startsWith("\x1b]9;"), "a short partial is carried");

// --- a huge sequence must not invent a bell ---------------------------------
// OSC 52 clipboard sync and iTerm2's imgcat both base64 their whole payload, so
// they routinely exceed the carry cap. Dropping the carry there used to forget
// we were inside a sequence, and its terminator then rang as a real bell.
s = session("l");
out = feed(
  s,
  "\x1b]52;c;" + "A".repeat(3000),
  "B".repeat(3000),
  "C".repeat(2000) + BEL,
);
assert.deepEqual(out, [], "an oversized sequence must not ring the bell");
assert.deepEqual(
  feed(s, `still here${BEL}`).map((e) => e.source),
  ["bell"],
  "and a real bell after it must still ring",
);

// --- an abandoned sequence must not eat the bells after it ------------------
// xterm aborts an OSC on ESC followed by anything but a backslash. It happens
// on Ctrl-C mid-title-write, or cat of a binary. Carrying the dead opener meant
// every later bell — an agent's permission prompt — was silently swallowed.
s = session("m");
out = feed(s, "\x1b]0;title\x1b[31m", `hello${BEL}`);
assert.deepEqual(
  out.map((e) => e.source),
  ["bell"],
  "a bell after an aborted sequence must still ring",
);

// --- an opener abandoned by a later sequence must not eat a bell ------------
// A terminal drops the first sequence the moment the second one starts. Keeping
// the dead opener meant the next real BEL was consumed as its terminator.
s = session("n");
out = feed(s, "\x1b]0;old", `\x1b]9;Done${BEL}`, `real${BEL}`);
assert.deepEqual(
  out.map((e) => e.source),
  ["notify", "bell"],
  "the notification lands and the later bell still rings",
);

// --- CAN and SUB abort a sequence -------------------------------------------
// A terminal stops parsing at 0x18 or 0x1a and treats the rest as output.
s = session("o");
out = feed(s, `\x1b]9;fake\x18text${BEL}`);
assert.deepEqual(
  out.map((e) => e.source),
  ["bell"],
  "an aborted sequence is not a notification, and its BEL is a plain bell",
);
for (const abort of ["\x18", "\x1a"]) {
  s = session(`o${abort.charCodeAt(0)}`);
  out = feed(s, `\x1b]0;title${abort}`, `real${BEL}`);
  assert.deepEqual(
    out.map((e) => e.source),
    ["bell"],
    "a bell after an aborted sequence must still ring",
  );
}

console.log("ok - OSC notifications");
