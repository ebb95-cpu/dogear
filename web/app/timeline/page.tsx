import Link from "next/link";
import { sbServer } from "@/lib/supabase";
import HighlightCard from "@/components/HighlightCard";
import type { Highlight } from "@/lib/types";

export const revalidate = 0;

export default async function TimelinePage() {
  const sb = sbServer();
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return <p>Please <Link href="/login">log in</Link>.</p>;

  const { data } = await sb.from("v_highlights")
    .select("*").eq("user_id", user.id)
    .order("highlighted_at", { ascending: false })
    .limit(200);

  const list = (data ?? []) as Highlight[];

  return (
    <section>
      <h1 className="text-3xl font-semibold mb-6">Timeline</h1>
      <p className="text-sm text-[color:var(--muted)] mb-8">
        Most recent {list.length} highlights.
      </p>
      {list.map((h) => (<HighlightCard key={h.id} h={h} />))}
    </section>
  );
}
