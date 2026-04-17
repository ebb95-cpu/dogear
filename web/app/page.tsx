import Link from "next/link";
import { sbServer } from "@/lib/supabase";
import HighlightCard from "@/components/HighlightCard";
import type { Highlight } from "@/lib/types";
import { format } from "date-fns";

export const revalidate = 0;

export default async function HomePage() {
  const sb = sbServer();
  const { data: { user } } = await sb.auth.getUser();

  if (!user) {
    return (
      <section className="max-w-prose">
        <h1 className="text-3xl font-semibold mb-4">Your personal book memory.</h1>
        <p className="text-[color:var(--muted)] mb-6">
          Every passage you highlight on your Kobo, surfaced back to you a few at a time —
          so the books you&apos;ve read keep teaching you.
        </p>
        <Link
          href="/login"
          className="inline-block border border-[color:var(--ink)] px-5 py-2 text-sm hover:bg-[color:var(--ink)] hover:text-white transition"
        >
          Log in to continue
        </Link>
      </section>
    );
  }

  // Fetch today's daily review: 5 highlights via the RPC
  const { data: highlights } = await sb.rpc("get_daily_review", {
    p_user_id: user.id,
    p_count: 5,
  });
  const list = (highlights ?? []) as Highlight[];

  // Mark them as reviewed (so they don't repeat for 30 days)
  if (list.length > 0) {
    await sb.from("daily_reviews").insert(
      list.map((h) => ({ user_id: user.id, highlight_id: h.id }))
    );
  }

  return (
    <section>
      <header className="mb-8">
        <p className="text-xs uppercase tracking-widest text-[color:var(--muted)]">
          {format(new Date(), "EEEE, MMMM d")}
        </p>
        <h1 className="text-3xl font-semibold mt-2">Today&apos;s review</h1>
        <p className="text-sm text-[color:var(--muted)] mt-1">
          {list.length} highlights from your library. Nothing repeats for 30 days.
        </p>
      </header>

      {list.length === 0 ? (
        <p className="text-[color:var(--muted)]">
          No highlights yet. Sync from your Kobo and they&apos;ll start showing up here.
        </p>
      ) : (
        <div>
          {list.map((h) => (
            <HighlightCard key={h.id} h={h} />
          ))}
        </div>
      )}
    </section>
  );
}
