import assert from "node:assert/strict";
import test from "node:test";
import { createHash } from "node:crypto";
import {
  generateIngestToken,
  ingestTokenHash,
  isIngestToken,
} from "../../web/lib/device-token.ts";

const VECTOR = "dogear_abcdefghijklmnopqrstuvwxyz0123456789ABCD";
const VECTOR_HASH = "e157e599a3cfe8efc251f6d9d8f3326c208c7833524115bc29f1eb4079787794";

test("known token hashes to the same SHA-256 the database uses", async () => {
  const js = await ingestTokenHash(VECTOR);
  const node = createHash("sha256").update(VECTOR).digest("hex");
  assert.equal(js, VECTOR_HASH);
  assert.equal(node, VECTOR_HASH);
});

test("generated tokens match the ingest rules", () => {
  const token = generateIngestToken();
  assert.equal(isIngestToken(token), true);
  assert.equal(isIngestToken(VECTOR), true);
  assert.equal(isIngestToken("eyJhbGciOiJub25lIn0.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.sig"), false);
  assert.equal(isIngestToken("dogear_short"), false);
});
