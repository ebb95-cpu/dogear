import Link from "next/link";
import { sbServer } from "@/lib/supabase-server";
import ThemeManager from "../themes/ThemeManager";
import type { Tag } from "@/lib/types";

export const revalidate = 0;

export default async function CategoriesPage() {
  const sb = sbServer();
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return <p>Please <Link href="/login">log in</Link>.</p>;

  const { data } = await sb
    .from("tags")
    .select("*")
    .eq("user_id", user.id)
    .order("name", { ascending: true });
  const tags = (data ?? []) as Tag[];

  return (
    <section>
      <h1 className="text-3xl font-semibold mb-3">Categories</h1>
      <p className="text-[color:var(--muted)] mb-6 text-sm max-w-prose">
        A category is a topic or idea, such as discipline or money. Open one to see its highlights, or tap the chips on a highlight to file it.
      </p>
      <ThemeManager initial={tags} />
      <ul className="mt-8 divide-y divide-[color:var(--rule)]">
        {tags.map((tag) => (
          <li key={tag.id} className="py-4">
            <Link href={`/categories/${tag.id}`} className="text-lg">{tag.name}</Link>
          </li>
        ))}
      </ul>
    </section>
  );
}
