// Runnable self-check for the photo inbox.
//   node --test server/inbox.test.js
import assert from "assert";
import { mkdtempSync, readFileSync, statSync, readdirSync, rmSync } from "fs";
import path from "path";
import os from "os";
import { saveImage } from "./inbox.js";

const dir = path.join(mkdtempSync(path.join(os.tmpdir(), "termaway-inbox-")), "inbox");
const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
const png = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 9]);

try {
  const a = saveImage(jpeg.toString("base64"), dir);
  assert.ok(a.startsWith(dir + path.sep) && a.endsWith(".jpg"), "JPEG lands in the inbox as .jpg");
  assert.deepEqual(readFileSync(a), jpeg, "bytes are stored unchanged");
  assert.equal(statSync(a).mode & 0o777, 0o600, "only the owner can read a dropped photo");
  assert.equal(statSync(dir).mode & 0o777, 0o700, "inbox is private");

  assert.ok(saveImage(png.toString("base64"), dir).endsWith(".png"), "PNG is kept as .png");
  assert.notEqual(saveImage(jpeg.toString("base64"), dir), a, "two drops never share a name");

  // Anything that isn't a JPEG or PNG is refused and writes nothing.
  for (const bad of [Buffer.from("#!/bin/sh\nrm -rf ~\n"), Buffer.from("GIF89a"), Buffer.alloc(0)]) {
    assert.equal(saveImage(bad.toString("base64"), dir), null);
  }
  assert.equal(saveImage(42, dir), null, "non-string data is refused");
  assert.equal(readdirSync(dir).length, 3, "refused drops leave no files");
  console.log("ok - inbox stores JPEG/PNG privately and refuses everything else");
} finally {
  rmSync(path.dirname(dir), { recursive: true, force: true });
}
