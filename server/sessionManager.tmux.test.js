// Runnable self-check for tmux persistence.
//   node server/sessionManager.tmux.test.js
// Spawns real tmux sessions on a throwaway socket and exercises the four places
// persistence can silently break: shutdown, explicit kill, rename, and a client
// that exits while its tmux session keeps running. Skips if tmux is missing.
import assert from "assert";
import { execFileSync } from "child_process";
import SessionManager from "./sessionManager.js";

process.env.TERMAWAY_TMUX = "1";
const PORT = 59000 + (process.pid % 1000); // unique socket per run

const sm = new SessionManager({ port: PORT });
if (!sm.tmux) {
  console.log("skip - no tmux binary found");
  process.exit(0);
}

// Probe, not a mutation: once the last session is gone the tmux server exits
// and list-sessions fails, which is simply "no sessions".
const tmuxSessions = () => {
  const r = sm._tmuxResult("list-sessions", "-F", "#{session_name}");
  return r.ok ? r.stdout.trim().split("\n").filter(Boolean) : [];
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// The tmux server starts asynchronously with its first client, so a session is
// not listed the instant create() returns.
async function expectSessions(expected, message) {
  for (let i = 0; i < 50; i++) {
    if (JSON.stringify(tmuxSessions()) === JSON.stringify(expected)) return;
    await sleep(100);
  }
  assert.deepEqual(tmuxSessions(), expected, message);
}

// Record what a session would send to attached clients.
function spy(session) {
  const sent = [];
  session.clients.add({
    readyState: 1,
    send: (json) => sent.push(JSON.parse(json)),
  });
  return sent;
}

try {
  // --- create -------------------------------------------------------------
  // The dot matters: tmux accepts it in a name but reads it as a window
  // separator in a target, so an unencoded "app.web" is unkillable.
  sm.create("app.web");
  assert.ok(sm.info("app.web").isTmux, "session should be tmux-backed");
  await expectSessions(["app%2Eweb"], "dot must be encoded");

  // --- no window where the session does not exist yet ---------------------
  // The tmux session is created synchronously, so a kill that lands in the
  // same tick still finds it. If creation were left to the PTY, tmux would
  // finish afterwards and orphan a session that comes back on next start.
  sm.create("racy");
  sm.kill("racy");
  await expectSessions(
    ["app%2Eweb"],
    "an immediate kill must not orphan a session",
  );

  sm.create("racy2");
  sm.rename("racy2", "renamed-fast");
  await expectSessions(
    ["app%2Eweb", "renamed-fast"],
    "an immediate rename must reach tmux",
  );
  sm.kill("renamed-fast");
  await expectSessions(["app%2Eweb"]);

  // Ephemeral split panes are hidden from the list and auto-killed, so
  // persisting one would leave a tmux session nobody can reach.
  sm.create("pane", true);
  assert.equal(
    sm.get("pane").tmuxName,
    null,
    "ephemeral must be a plain shell",
  );
  await expectSessions(
    ["app%2Eweb"],
    "ephemeral must not create a tmux session",
  );
  sm.kill("pane");

  // --- rename -------------------------------------------------------------
  sm.rename("app.web", "api");
  await expectSessions(
    ["api"],
    "rename must follow through to tmux, or the old name returns on restart",
  );

  // --- client death reattaches -------------------------------------------
  // `tmux detach` and a killed client both look like a PTY exit, but the
  // session is still running and must not be reported as gone.
  await sleep(1100); // clear the respawn-loop guard
  const before = sm.get("api").pty.pid;
  sm.get("api").pty.kill();
  await sleep(600);
  assert.ok(sm.exists("api"), "session must survive its client dying");
  assert.notEqual(
    sm.get("api").pty.pid,
    before,
    "a new client must be spawned",
  );
  await expectSessions(["api"], "reattach must not disturb the tmux session");

  // --- shutdown leaves tmux alone ----------------------------------------
  // This is the one that makes persistence real: "Stop Server" walks every
  // session through kill(), which must not end the tmux session.
  const sent = spy(sm.get("api"));
  sm.shuttingDown = true;
  sm.kill("api");
  await expectSessions(["api"], "shutdown must leave the tmux session running");
  // ...and must stay quiet about it. iOS discards the composer draft on both
  // "killed" and "exited", so announcing either would lose work for a session
  // that is still running.
  await sleep(600); // let the PTY's exit land
  assert.deepEqual(
    sent.map((m) => m.type).filter((t) => t === "killed" || t === "exited"),
    [],
    "shutdown must not tell clients the session was killed or exited",
  );

  // --- a new run adopts it ------------------------------------------------
  const restarted = new SessionManager({ port: PORT });
  assert.equal(restarted.adoptTmuxSessions(), 1);
  assert.ok(restarted.exists("api"), "surviving session must be adopted");

  // --- explicit kill really kills ----------------------------------------
  restarted.kill("api");
  await expectSessions([], "explicit kill must end the tmux session");

  console.log("ok - tmux persistence");
} finally {
  try {
    execFileSync(sm.tmux.bin, ["-L", sm.tmux.socket, "kill-server"], {
      stdio: "ignore",
    });
  } catch {
    // already gone
  }
}
