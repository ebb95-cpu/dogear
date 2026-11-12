import Link from "next/link";
import { sbServer } from "@/lib/supabase-server";
import HighlightCard from "@/components/HighlightCard";
import CategoryPicker from "@/components/CategoryPicker";
import { loadCategoryIndex } from "@/lib/library";
import type { Highlight } from "@/lib/types";

export const revalidate = 0;

export default async function CategoryPage({ params }: { params: { id: string } }) {
  const sb = sbServer();
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return <p>Please <Link href="/login">log in</Link>.</p>;

  const { data: tag } = await sb
    .from("tags")
    .select("id, name")
    .eq("id", params.id)
    .eq("user_id", user.id)
    .single();
  if (!tag) return <p>Category not found.</p>;

  const { data: links } = await sb
    .from("highlight_tags")
    .select("highlight_id")
    .eq("tag_id", tag.id);
  const ids = ((links ?? []) as { highlight_id: string }[]).map((row) => row.highlight_id);
  const { data } = ids.length
    ? await sb.from("v_highlights").select("*").eq("user_id", user.id).in("id", ids).order("highlighted_at", { ascending: false })
    : { data: [] };
  const list = (data ?? []) as Highlight[];
  const { categories, selected } = await loadCategoryIndex(sb, user.id, list.map((item) => item.id));

  return (
    <section>
      <Link href="/categories" className="text-sm text-[color:var(--muted)]">← categories</Link>
      <h1 className="text-3xl font-semibold mt-4 mb-6">{tag.name}</h1>
      {list.length === 0 ? (
        <p className="text-[color:var(--muted)]">No highlights in this category yet.</p>
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
