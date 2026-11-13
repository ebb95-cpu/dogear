/** One-time code that signs the Kobo browser into an account that is already signed in on a phone. */

// Unambiguous on an e-ink keyboard: no 0/O and no 1/I. L stays, because 1 is
// not in the set. 32 characters, so a random byte modulo 32 has no bias.
export const LOGIN_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const CODE_RE = new RegExp(`^[${LOGIN_CODE_ALPHABET}]{8}$`);

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export function generateLoginCode(): string {
  const bytes = new Uint8Array(8);
  crypto.getRandomValues(bytes);
  let out = "";
  for (const b of bytes) out += LOGIN_CODE_ALPHABET[b % LOGIN_CODE_ALPHABET.length];
  return out;
}

/** Uppercase, drop spaces and dashes. The hash is of this form, never the raw keystrokes. */
export function normalizeLoginCode(raw: string): string {
  return raw.toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 8);
}

export function isLoginCode(value: string): boolean {
  return CODE_RE.test(value);
}

export function formatLoginCode(code: string): string {
  return `${code.slice(0, 4)} ${code.slice(4)}`;
}

export async function loginCodeHash(code: string): Promise<string> {
  return sha256Hex(code);
}

export function clientIp(req: Request): string {
  const forwarded = req.headers.get("x-forwarded-for");
  if (forwarded) {
    const first = forwarded.split(",")[0]?.trim();
    if (first) return first.slice(0, 80);
  }
  const real = req.headers.get("x-real-ip")?.trim();
  if (real) return real.slice(0, 80);
  return "unknown";
}
