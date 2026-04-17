"use client";
import { useState } from "react";
import { sbBrowser } from "@/lib/supabase-browser";

export default function LoginPage() {
  const [email, setEmail] = useState("");
  const [sent, setSent] = useState(false);

  async function sendLink(e: React.FormEvent) {
    e.preventDefault();
    const sb = sbBrowser();
    await sb.auth.signInWithOtp({
      email,
      options: { emailRedirectTo: `${location.origin}/auth/callback` },
    });
    setSent(true);
  }

  return (
    <section className="max-w-sm">
      <h1 className="text-2xl font-semibold mb-4">Log in</h1>
      {sent ? (
        <p>Check your email for a magic link.</p>
      ) : (
        <form onSubmit={sendLink} className="space-y-3">
          <input
            type="email"
            required
            placeholder="you@example.com"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="w-full border border-[color:var(--rule)] px-3 py-2"
          />
          <button className="border border-[color:var(--ink)] px-4 py-2 hover:bg-[color:var(--ink)] hover:text-white transition">
            Send magic link
          </button>
        </form>
      )}
    </section>
  );
}
