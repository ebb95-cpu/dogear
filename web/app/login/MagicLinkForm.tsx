"use client";

import { useState } from "react";
import { sbBrowser } from "@/lib/supabase-browser";

export default function MagicLinkForm() {
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

  if (sent) {
    return <p>Check your email for a magic link.</p>;
  }

  return (
    <form onSubmit={sendLink} className="space-y-3">
      <input
        type="email"
        required
        placeholder="you@example.com"
        value={email}
        onChange={(e) => setEmail(e.target.value)}
        className="w-full border-2 border-[color:var(--ink)] px-4 py-4 text-lg"
      />
      <button className="w-full border-2 border-[color:var(--ink)] bg-[color:var(--ink)] text-white px-4 py-4 text-lg">
        Send magic link
      </button>
    </form>
  );
}
