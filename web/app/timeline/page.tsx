import Link from "next/link";
import { sbServer } from "@/lib/supabase-server";
import HighlightCard from "@/components/HighlightCard";
import CategoryPicker from "@/components/CategoryPicker";
import { loadCategoryIndex, sanitizeSearch } from "@/lib/library";
import type { Highlight } from "@/lib/types";

export const revalidate = 0;

export default async function TimelinePage({
  searchParams,
}: {
  searchParams?: { q?: string };
}) {
  const sb = sbServer();
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return <p>Please <Link href="/login">log in</Link>.</p>;

  const q = sanitizeSearch(searchParams?.q);
  let query = sb
    .from("v_highlights")
    .select("*")
    .eq("user_id", user.id)
    .order("highlighted_at", { ascending: false })
    .limit(200);
  if (q) {
    query = query.or(`text.ilike.%${q}%,annotation.ilike.%${q}%,book_title.ilike.%${q}%`);
  }
  const { data } = await query;
  const list = (data ?? []) as Highlight[];
  const { categories, selected } = await loadCategoryIndex(sb, user.id, list.map((item) => item.id));

  return (
    <section>
      <h1 className="text-3xl font-semibold mb-4">All highlights</h1>
      <form action="/timeline" className="mb-8">
        <input
          name="q"
          defaultValue={q}
          placeholder="Search text, notes, or book"
          aria-label="Search highlights"
          className="w-full border border-[color:var(--rule)] px-3 py-2 text-sm"
        />
      </form>
      {list.length === 0 ? (
        <p className="text-[color:var(--muted)]">No highlights match.</p>
      ) : (
        list.map((highlight) => (
          <HighlightCard
            key={highlight.id}
            h={highlight}
            extra={
              <CategoryPicker
                highlightId={highlight.id}
                categories={categories}
                selected={selected[highlight.id] ?? []}
              />
            }
          />
        ))
      )}
    </section>
  );
}
