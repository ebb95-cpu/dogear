import Link from "next/link";
import { sbServer } from "@/lib/supabase-server";
import TodayList from "@/components/TodayList";
import { loadCategoryIndex } from "@/lib/library";
import type { Highlight } from "@/lib/types";

export const revalidate = 0;

export default async function TodayPage() {
  const sb = sbServer();
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return <p>Please <Link href="/login">log in</Link>.</p>;

  const since = new Date(Date.now() - 3 * 24 * 60 * 60 * 1000).toISOString();
  const { data } = await sb
    .from("v_highlights")
    .select("*")
    .eq("user_id", user.id)
    .gte("highlighted_at", since)
    .order("highlighted_at", { ascending: false });
  const list = (data ?? []) as Highlight[];
  const { categories, selected } = await loadCategoryIndex(sb, user.id, list.map((item) => item.id));

  return (
    <section>
      <h1 className="text-3xl font-semibold mb-2">Today</h1>
      <p className="text-sm text-[color:var(--muted)] mb-8">
        Highlights whose date is today on this phone or reader.
      </p>
      <TodayList highlights={list} categories={categories} selected={selected} />
    </section>
  );
}
