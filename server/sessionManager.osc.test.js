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

// A stand-in for a session: _scanOscNotification only needs the carry field,
// and markAttention only needs the map entry.
function session(name) {
  const s = { name, ephemeral: false, needsAttention: false, oscCarry: "" };
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
s = session("j");
feed(s, "\x1b]9;" + "x".repeat(5000));
assert.equal(s.oscCarry, "", "an oversized unterminated sequence is dropped");

// A partial sequence within the cap is kept, waiting for the rest.
s = session("k");
feed(s, "\x1b]9;still going");
assert.ok(s.oscCarry.startsWith("\x1b]9;"), "a short partial is carried");

console.log("ok - OSC notifications");
