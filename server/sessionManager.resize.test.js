// Runnable self-check for resize coalescing.
//   node --test server/sessionManager.resize.test.js
// A rotation emits several sizes within a few milliseconds. The cooldown that
// stops two clients fighting over the PTY must hold the last one, not drop it —
// dropping leaves the PTY on an intermediate width forever, and the shell then
// wraps every prompt at the wrong column.
import assert from "assert";
import SessionManager from "./sessionManager.js";

const sm = new SessionManager();

// A stand-in for a session: resize() only touches the size bookkeeping, the
// client set and the PTY's resize method.
function session(name, clientCount = 1) {
  const applied = [];
  const clients = Array.from({ length: clientCount }, (_, i) => ({ id: i }));
  const s = {
    name,
    clients: new Set(clients),
    clientSizes: new WeakMap(),
    lastCols: 80,
    lastRows: 24,
    lastResizeAt: 0,
    pendingResize: null,
    killing: false,
    pty: { resize: (cols, rows) => applied.push([cols, rows]) },
  };
  sm.sessions.set(name, s);
  return { s, applied, clients };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// --- a burst applies its last size, not its first -----------------------------
let { s, applied, clients } = session("rotate");
sm.resize("rotate", 100, 30, clients[0]); // lands immediately
sm.resize("rotate", 120, 40, clients[0]); // inside the cooldown
sm.resize("rotate", 132, 44, clients[0]); // the size the client settled on
assert.deepEqual(applied, [[100, 30]], "only the first should have landed yet");
await sleep(200);
assert.deepEqual(
  applied,
  [
    [100, 30],
    [132, 44],
  ],
  "the last size of the burst must reach the PTY",
);
assert.equal(s.lastCols, 132, "and be recorded as the current size");
assert.equal(s.pendingResize, null, "the timer must not be left behind");

// --- a burst that ends back where it started does nothing ---------------------
// The deferred work recomputes rather than replaying a captured size, so
// 100 -> 120 -> 100 must not leave the PTY on 120.
({ s, applied, clients } = session("bounce"));
sm.resize("bounce", 100, 30, clients[0]);
sm.resize("bounce", 120, 40, clients[0]);
sm.resize("bounce", 100, 30, clients[0]);
await sleep(200);
assert.deepEqual(
  applied,
  [[100, 30]],
  "a burst returning to its start is a no-op",
);

// --- a client that leaves mid-burst is not counted ----------------------------
// The narrower client's size is what the PTY is on; once it detaches the
// deferred resize must widen to the client that remains, not replay the
// departed one.
({ s, applied, clients } = session("leaver", 2));
sm.resize("leaver", 200, 50, clients[0]);
await sleep(150);
sm.resize("leaver", 100, 30, clients[1]); // narrower client joins the calculation
await sleep(150);
assert.deepEqual(
  applied.at(-1),
  [100, 30],
  "the minimum wins while both are here",
);
sm.resize("leaver", 95, 29, clients[1]); // lands, and opens the cooldown
sm.resize("leaver", 90, 28, clients[1]); // deferred inside it...
s.clients.delete(clients[1]); // ...and the client leaves first
await sleep(200);
assert.deepEqual(
  applied.at(-1),
  [200, 50],
  "a departed client must not size the PTY",
);

// --- a session that goes away must not be resized -----------------------------
// The timer outlives the session by up to the cooldown, and a killed session,
// an exited shell and a failed reattach all drop it from the map the same way.
({ s, applied, clients } = session("doomed"));
sm.resize("doomed", 100, 30, clients[0]);
sm.resize("doomed", 120, 40, clients[0]);
sm.sessions.delete("doomed");
await sleep(200);
assert.deepEqual(applied, [[100, 30]], "a gone session must not be resized");

// --- a renamed session keeps its pending resize -------------------------------
// rename() updates session.name before moving the map entry, so the identity
// check must still recognise it.
({ s, applied, clients } = session("before"));
sm.resize("before", 100, 30, clients[0]);
sm.resize("before", 132, 44, clients[0]);
sm.sessions.delete("before");
s.name = "after";
sm.sessions.set("after", s);
await sleep(200);
assert.deepEqual(
  applied.at(-1),
  [132, 44],
  "a rename must not lose the resize",
);

// --- tiny sizes are still rejected -------------------------------------------
({ s, applied, clients } = session("tiny"));
sm.resize("tiny", 4, 2, clients[0]);
await sleep(150);
assert.deepEqual(applied, [], "a size that breaks rendering is ignored");

console.log("ok - resize coalescing");
