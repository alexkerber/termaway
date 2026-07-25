// Runnable self-check for the server's trust boundaries.
//   node --test server/index.security.test.js
//
// Starts the real server as a child process on a throwaway port — no mocking of
// Express or the socket, because the things worth testing here are exactly the
// ones a mock would paper over. Everything runs against a password-protected
// instance, since that is the configuration where a leak actually matters.
import assert from "assert";
import { spawn } from "child_process";
import { once } from "events";
import path from "path";
import { fileURLToPath } from "url";
import { WebSocket } from "ws";

const SERVER = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "index.js",
);
const PORT = 51000 + (process.pid % 2000); // unique per run; never 3000
const PASSWORD = "correct-horse";
const BASE = `http://127.0.0.1:${PORT}`;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** A websocket client that records every message it is sent. */
async function connect({ authenticate }) {
  const ws = new WebSocket(`ws://127.0.0.1:${PORT}`);
  const received = [];
  ws.on("message", (raw) => received.push(JSON.parse(raw)));
  await once(ws, "open");
  if (authenticate) {
    ws.send(JSON.stringify({ type: "auth", password: PASSWORD }));
    for (
      let i = 0;
      i < 50 && !received.some((m) => m.type === "auth-success");
      i++
    ) {
      await sleep(50);
    }
    assert.ok(
      received.some((m) => m.type === "auth-success"),
      "auth should succeed with the right password",
    );
  }
  return { ws, received };
}

/** First non-loopback IPv4 of this machine, or null when there isn't one. */
async function externalIPv4() {
  const os = await import("os");
  for (const addrs of Object.values(os.networkInterfaces())) {
    for (const a of addrs ?? []) {
      if (a.family === "IPv4" && !a.internal) return a.address;
    }
  }
  return null;
}

const server = spawn(
  "node",
  [SERVER, "--port", String(PORT), "--password", PASSWORD],
  {
    stdio: ["ignore", "pipe", "pipe"],
  },
);

try {
  // Wait for the listener rather than sleeping a guessed amount. The timeout is
  // unref'd so it can't keep the process alive once the server is up.
  await Promise.race([
    (async () => {
      for await (const chunk of server.stdout) {
        if (String(chunk).includes("running at")) return;
      }
    })(),
    new Promise((_, reject) => {
      setTimeout(() => reject(new Error("server did not start")), 15000).unref();
    }),
  ]);

  // --- attention must not reach unauthenticated clients ---------------------
  // The leak this guards: /api/notify fans out a title and body that can carry
  // anything the user's agent decided to say. An unauthenticated socket is a
  // stranger who guessed the port.
  const anonymous = await connect({ authenticate: false });
  const authed = await connect({ authenticate: true });

  const notify = await fetch(`${BASE}/api/notify`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ title: "SECRET TITLE", body: "SECRET BODY" }),
  });
  assert.equal(notify.status, 200, "loopback JSON notify should be accepted");
  await sleep(500);

  const leaked = JSON.stringify(anonymous.received);
  assert.ok(
    !leaked.includes("SECRET"),
    "unauthenticated client must not receive attention",
  );
  assert.ok(
    JSON.stringify(authed.received).includes("SECRET"),
    "authenticated client should receive attention",
  );

  // --- /api/notify is loopback-only, JSON-only, and not browser-reachable ---
  const withOrigin = await fetch(`${BASE}/api/notify`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      origin: "http://evil.example",
    },
    body: "{}",
  });
  assert.equal(
    withOrigin.status,
    403,
    "a request carrying an Origin is a browser: reject it",
  );

  const wrongType = await fetch(`${BASE}/api/notify`, {
    method: "POST",
    headers: { "content-type": "text/plain" },
    body: "{}",
  });
  assert.equal(
    wrongType.status,
    415,
    "non-JSON must be rejected before it is parsed",
  );

  const external = await externalIPv4();
  if (external) {
    const offBox = await fetch(`http://${external}:${PORT}/api/notify`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: "{}",
    });
    assert.equal(offBox.status, 403, "notify must only answer on loopback");
  }

  // --- session names are a trust boundary ----------------------------------
  // "%" matters beyond hygiene: tmux names percent-encode dots, and that
  // mapping is only unambiguous while "%" can't appear in a session name.
  const rejected = ["", "   ", "a/b", "a:b", "a%2Eb", "a\u0007b", "x".repeat(65)];
  for (const name of rejected) {
    authed.received.length = 0;
    authed.ws.send(JSON.stringify({ type: "create", name }));
    await sleep(200);
    assert.ok(
      authed.received.some((m) => m.type === "error"),
      `session name ${JSON.stringify(name)} should be rejected`,
    );
    assert.ok(
      !authed.received.some((m) => m.type === "created"),
      `session name ${JSON.stringify(name)} must not create a session`,
    );
  }

  anonymous.ws.close();
  authed.ws.close();
  console.log("ok - server trust boundaries");
} finally {
  server.kill("SIGTERM");
  await sleep(300);
  server.kill("SIGKILL");
}
