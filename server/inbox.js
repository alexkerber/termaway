// Images a phone drops into a session, saved where an agent on this machine can
// read them by absolute path. A fixed folder, not the session's cwd: node-pty
// only knows the shell's PID, so the foreground process's cwd isn't a portable
// lookup.
import { mkdirSync, writeFileSync } from "fs";
import { randomBytes } from "crypto";
import path from "path";
import os from "os";

export const INBOX_DIR = path.join(os.homedir(), ".termaway", "inbox");

const PNG_MAGIC = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

// The bytes decide the type, never the client: a wrong extension would make an
// agent misread the file, and anything else isn't an image we promised to take.
export function imageExtension(buf) {
  if (buf.length >= 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return "jpg";
  if (buf.length >= 8 && buf.subarray(0, 8).equals(PNG_MAGIC)) return "png";
  return null;
}

// Returns the saved file's absolute path, or null when the data is not a JPEG
// or PNG. The server names the file, so nothing from the client reaches the path.
// shortcut: the inbox is never pruned; add an age-based sweep if it grows.
export function saveImage(base64, dir = INBOX_DIR) {
  if (typeof base64 !== "string") return null;
  const buf = Buffer.from(base64, "base64");
  const ext = imageExtension(buf);
  if (!ext) return null;
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const file = path.join(dir, `${stamp}-${randomBytes(3).toString("hex")}.${ext}`);
  writeFileSync(file, buf, { mode: 0o600, flag: "wx" });
  return file;
}
