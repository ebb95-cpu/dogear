"use client";
import { useState } from "react";
import { sbBrowser } from "@/lib/supabase-browser";

export default function BookSummary({
  bookId, initialSummary, isAiDraft,
}: { bookId: string; initialSummary: string | null; isAiDraft: boolean }) {
  const [summary, setSummary] = useState(initialSummary ?? "");
  const [draft, setDraft] = useState(isAiDraft);
  const [editing, setEditing] = useState(false);
  const [loading, setLoading] = useState(false);

  async function generate() {
    setLoading(true);
    const res = await fetch("/api/book-summary", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ bookId }),
    });
    const j = await res.json();
    if (j.summary) { setSummary(j.summary); setDraft(true); }
    setLoading(false);
  }

  async function save() {
    const sb = sbBrowser();
    await sb.from("books").update({
      summary,
      summary_is_ai_draft: false,
    }).eq("id", bookId);
    setDraft(false);
    setEditing(false);
  }

  return (
    <div className="mt-6 p-5 bg-white border border-[color:var(--rule)]">
      <div className="flex items-center justify-between mb-2">
        <h3 className="text-sm uppercase tracking-widest text-[color:var(--muted)]">
          What this book was about
        </h3>
        <div className="flex gap-3 text-xs">
          {!editing ? (
            <>
              <button onClick={() => setEditing(true)} className="hover:underline">edit</button>
              <button onClick={generate} disabled={loading} className="hover:underline">
                {loading ? "drafting…" : summary ? "redraft with AI" : "draft with AI"}
              </button>
            </>
          ) : (
            <>
              <button onClick={save} className="hover:underline">save</button>
              <button onClick={() => setEditing(false)} className="hover:underline">cancel</button>
            </>
          )}
        </div>
      </div>
      {draft && summary && (
        <p className="text-xs text-[color:var(--accent)] mb-2">AI draft — edit to make it yours.</p>
      )}
      {editing ? (
        <textarea
          value={summary}
          onChange={(e) => setSummary(e.target.value)}
          className="w-full border border-[color:var(--rule)] p-3 min-h-[140px] text-sm leading-relaxed"
        />
      ) : summary ? (
        <p className="text-sm leading-relaxed whitespace-pre-wrap">{summary}</p>
      ) : (
        <p className="text-sm text-[color:var(--muted)] italic">
          No summary yet. Click &quot;draft with AI&quot; to generate one from your highlights.
        </p>
      )}
    </div>
  );
}
