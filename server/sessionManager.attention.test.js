// Runnable self-check for the attention transition logic.
//   node server/sessionManager.attention.test.js
// Exercises the branch that matters (false->true transition tracking, the
// ephemeral list-exclusion, and clear) without spawning a real PTY.
import assert from "assert";
import SessionManager from "./sessionManager.js";

const sm = new SessionManager();
const events = [];
sm.onAttentionChange = (session, meta) =>
  events.push({ name: session.name, ...meta });

// Inject fake sessions (bypass create() so we don't spawn shells).
sm.sessions.set("main", {
  name: "main",
  ephemeral: false,
  needsAttention: false,
});
sm.sessions.set("pane", {
  name: "pane",
  ephemeral: true,
  needsAttention: false,
});

// First bell: false->true transition, changed=true.
sm.markAttention("main", { source: "bell" });
assert.equal(events.length, 1);
assert.deepEqual(
  {
    name: events[0].name,
    source: events[0].source,
    changed: events[0].changed,
  },
  { name: "main", source: "bell", changed: true },
);
assert.equal(sm.sessions.get("main").needsAttention, true);

// Second bell while already flagged: still fires, but changed=false (so the
// list won't re-broadcast, only explicit notifies force a banner).
sm.markAttention("main", { source: "bell" });
assert.equal(events.length, 2);
assert.equal(events[1].changed, false);

// Ephemeral split-pane sessions still raise the event (so an agent in a pane
// can alert) but are excluded from list(), so they never render a badge.
sm.markAttention("pane", { source: "bell" });
assert.equal(events.length, 3, "ephemeral session must still raise attention");
assert.equal(sm.sessions.get("pane").needsAttention, true);
assert.ok(
  !sm.list().includes("pane"),
  "ephemeral session must not appear in list()",
);
assert.ok(sm.list().includes("main"), "named session must appear in list()");

// Clear transitions true->false once; a second clear is a no-op.
sm.clearAttention("main");
assert.equal(events.length, 4);
assert.equal(events[3].source, "clear");
assert.equal(sm.sessions.get("main").needsAttention, false);
sm.clearAttention("main");
assert.equal(events.length, 4, "clearing an already-clear session is a no-op");

console.log("ok - attention transitions");
