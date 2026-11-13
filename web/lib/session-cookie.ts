/** How long the browser keeps the Supabase session cookie.

400 days is the longest a current browser will store. It is also before the
2038 cutoff, so the Kobo's older WebKit does not drop the cookie. Middleware
refreshes the session and rewrites the cookie, so opening the library extends it.
*/
export const SESSION_MAX_AGE = 60 * 60 * 24 * 400;

/** Rewrite a Set-Cookie header so a Kobo browser keeps the session. */
export function clampSessionCookie(header: string, now = Date.now(), secure = false): string {
  const eq = header.indexOf("=");
  const name = eq === -1 ? header : header.slice(0, eq);
  if (!name.startsWith("sb-")) return header;
  if (/Max-Age=0(?:;|$)/i.test(header)) return header;
  const expires = new Date(now + SESSION_MAX_AGE * 1000).toUTCString();
  let next = header;
  if (/Max-Age=/i.test(next)) {
    next = next.replace(/Max-Age=\d+/gi, `Max-Age=${SESSION_MAX_AGE}`);
  } else {
    next += `; Max-Age=${SESSION_MAX_AGE}`;
  }
  if (/Expires=/i.test(next)) {
    next = next.replace(/Expires=[^;]*/gi, `Expires=${expires}`);
  } else {
    next += `; Expires=${expires}`;
  }
  if (secure && !/;\s*Secure(?:;|$)/i.test(next)) {
    next += "; Secure";
  }
  return next;
}
