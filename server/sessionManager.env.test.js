// Runnable self-check for the agent hook environment.
//   node --test server/sessionManager.env.test.js
// An agent hook inside a session reads TERMAWAY_SESSION and TERMAWAY_URL to
// know which session to flag and where /api/notify is. Without them the hook
// can only raise a plain banner. The tmux case lives in the tmux test, since the
// shell there is a child of the tmux server, not of the PTY this spawns.
import assert from "assert";
import SessionManager from "./sessionManager.js";

process.env.SHELL = "/bin/sh"; // a login zsh with a real config is slow and noisy
delete process.env.TERMAWAY_TMUX;

const sm = new SessionManager({ port: 4321, agentUrl: "https://127.0.0.1:4321" });
const name = "env check.1"; // a space and a dot, both allowed in session names
sm.create(name);

let out = "";
sm.sessions.get(name).clients.add({
  readyState: 1,
  send: (json) => {
    const msg = JSON.parse(json);
    if (msg.type === "output") out += msg.data;
  },
});
sm.sessions.get(name).pty.write('printf "<%s|%s>\\n" "$TERMAWAY_SESSION" "$TERMAWAY_URL"\n');

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
for (let i = 0; i < 50 && !out.includes(`<${name}|https://127.0.0.1:4321>`); i++) await sleep(100);
sm.kill(name);
assert.ok(out.includes(`<${name}|https://127.0.0.1:4321>`), `hook env missing from the shell, got: ${JSON.stringify(out.slice(-200))}`);
console.log("ok - session shell sees TERMAWAY_SESSION and TERMAWAY_URL");
