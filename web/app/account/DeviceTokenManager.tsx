"use client";

import { useEffect, useState } from "react";
import { sbBrowser } from "@/lib/supabase-browser";
import { generateIngestToken, ingestTokenHash, isIngestToken } from "@/lib/device-token";

type Credential = {
  id: string;
  token_prefix: string;
  label: string | null;
  created_at: string;
  revoked_at: string | null;
  last_used_at: string | null;
};

export default function DeviceTokenManager({ supabaseUrl }: { supabaseUrl: string }) {
  const [rows, setRows] = useState<Credential[]>([]);
  const [fresh, setFresh] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [needsMigration, setNeedsMigration] = useState(false);
  const [busy, setBusy] = useState(false);

  async function load() {
    const sb = sbBrowser();
    const { data, error: loadError } = await sb
      .from("device_credentials")
      .select("id, token_prefix, label, created_at, revoked_at, last_used_at")
      .order("created_at", { ascending: false });
    if (loadError) {
      const msg = loadError.message ?? "";
      if (/device_credentials|schema cache|does not exist/i.test(msg)) {
        setNeedsMigration(true);
      }
      setError(msg);
      return;
    }
    setNeedsMigration(false);
    setError(null);
    setRows((data ?? []) as Credential[]);
  }

  useEffect(() => {
    load();
  }, []);

  async function createToken() {
    setBusy(true);
    setFresh(null);
    setError(null);
    try {
      const sb = sbBrowser();
      const { data: { user } } = await sb.auth.getUser();
      if (!user) {
        setError("Log in again, then create a token.");
        return;
      }
      const token = generateIngestToken();
      if (!isIngestToken(token)) {
        setError("Could not generate a token.");
        return;
      }
      const token_hash = await ingestTokenHash(token);
      const { error: insertError } = await sb.from("device_credentials").insert({
        user_id: user.id,
        token_hash,
        token_prefix: token.slice(0, 12),
        label: "Kobo",
      });
      if (insertError) {
        const msg = insertError.message ?? "";
        if (/device_credentials|schema cache|does not exist/i.test(msg)) setNeedsMigration(true);
        setError(msg);
        return;
      }
      setFresh(token);
      await load();
    } finally {
      setBusy(false);
    }
  }

  async function revoke(id: string) {
    const sb = sbBrowser();
    const { error: updateError } = await sb
      .from("device_credentials")
      .update({ revoked_at: new Date().toISOString() })
      .eq("id", id);
    if (updateError) {
      setError(updateError.message);
      return;
    }
    if (fresh) setFresh(null);
    await load();
  }

  const config = fresh
    ? [
        `SUPABASE_URL="${supabaseUrl || "https://YOUR-PROJECT.supabase.co"}"`,
        `SUPABASE_ANON_KEY="paste-the-anon-public-key"`,
        `DOGEAR_INGEST_TOKEN="${fresh}"`,
      ].join("\n")
    : "";

  return (
    <div>
      <h2 className="text-sm uppercase tracking-widest text-[color:var(--muted)] mt-10 mb-3">
        Kobo ingest token
      </h2>
      <p className="text-sm max-w-prose mb-3">
        Create a token on this page and put it in the Kobo <span className="italic">config.env</span>.
        It can only add highlights to this account. Revoke it here if the Kobo is lost or sold.
        Use the anon / public key from Supabase, not the service role key.
      </p>
      {needsMigration && (
        <p className="text-sm mb-3">
          The database does not have device tokens yet. Run{" "}
          <span className="italic">supabase/migrations/20261111_device_ingest.sql</span> in the
          Supabase SQL editor. That file does not delete highlights.
        </p>
      )}
      {error && !needsMigration && (
        <p className="text-sm text-[color:var(--accent)] mb-3 break-words">{error}</p>
      )}
      <button
        type="button"
        onClick={createToken}
        disabled={busy}
        className="border border-[color:var(--ink)] px-4 py-2 text-sm hover:bg-[color:var(--ink)] hover:text-white transition disabled:opacity-50"
      >
        {busy ? "Creating…" : "Create Kobo token"}
      </button>
      {fresh && (
        <div className="mt-4">
          <p className="text-sm mb-2">
            Copy this into <span className="italic">config.env</span> now. It is not shown again.
            Replace the anon key placeholder with the public anon key. Leave the service role key out.
          </p>
          <textarea
            readOnly
            value={config}
            rows={5}
            className="w-full border border-[color:var(--rule)] bg-white px-3 py-2 text-xs break-all"
            aria-label="Kobo config.env contents"
          />
        </div>
      )}
      {rows.length > 0 && (
        <ul className="mt-6 divide-y divide-[color:var(--rule)] text-sm">
          {rows.map((row) => (
            <li key={row.id} className="py-3 flex items-center justify-between gap-3">
              <div className="min-w-0">
                <p className="break-all">{row.label ?? "Kobo"} · {row.token_prefix}…</p>
                <p className="text-xs text-[color:var(--muted)]">
                  {row.revoked_at
                    ? "Revoked"
                    : row.last_used_at
                      ? `Last sync ${new Date(row.last_used_at).toLocaleString()}`
                      : "Not used yet"}
                </p>
              </div>
              {!row.revoked_at && (
                <button
                  type="button"
                  onClick={() => revoke(row.id)}
                  className="text-sm text-[color:var(--accent)] hover:underline shrink-0"
                >
                  Revoke
                </button>
              )}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
