/** Per-account Kobo ingest token. The device stores this, never a service-role key. */

const TOKEN_RE = /^dogear_[A-Za-z0-9_-]{32,}$/;

export function isIngestToken(value: string): boolean {
  return value.length >= 40 && value.length <= 200 && TOKEN_RE.test(value);
}

export function generateIngestToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  const body = btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
  return `dogear_${body}`;
}

export async function ingestTokenHash(token: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
