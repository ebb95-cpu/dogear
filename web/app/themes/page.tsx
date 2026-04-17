import Link from "next/link";
import { sbServer } from "@/lib/supabase-server";
import ThemeManager from "./ThemeManager";
import type { Tag } from "@/lib/types";

export const revalidate = 0;

export default async function ThemesPage() {
  const sb = sbServer();
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return <p>Please <Link href="/login">log in</Link>.</p>;

  const { data } = await sb.from("tags")
    .select("*").eq("user_id", user.id)
    .order("is_theme", { ascending: false })
    .order("sort_order", { ascending: true });

  const tags = (data ?? []) as Tag[];

  return (
    <section>
      <h1 className="text-3xl font-semibold mb-3">Themes</h1>
      <p className="text-[color:var(--muted)] mb-6 text-sm max-w-prose">
        Define 5–15 life areas you&apos;re learning about — leadership, discipline, faith, training,
        money, etc. Every highlight can be tagged with 0–3 themes. Keeps your library
        organized without decision fatigue.
      </p>
      <ThemeManager initial={tags} />
    </section>
  );
}
