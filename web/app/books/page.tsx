import Link from "next/link";
import { sbServer } from "@/lib/supabase-server";

export const revalidate = 0;

export default async function BooksPage() {
  const sb = sbServer();
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return <p>Please <Link href="/login">log in</Link>.</p>;

  // Group highlight counts by book
  const { data } = await sb
    .from("books")
    .select("id,title,author,summary,highlights(count)")
    .eq("user_id", user.id)
    .order("updated_at", { ascending: false });

  type Row = { id: string; title: string|null; author: string|null; summary: string|null; highlights: { count: number }[] };
  const rows = (data ?? []) as Row[];

  return (
    <section>
      <h1 className="text-3xl font-semibold mb-6">Your books</h1>
      {rows.length === 0 ? (
        <p className="text-[color:var(--muted)]">No books synced yet.</p>
      ) : (
        <ul className="divide-y divide-[color:var(--rule)]">
          {rows.map((b) => (
            <li key={b.id} className="py-5">
              <Link href={`/books/${b.id}`} className="block">
                <h2 className="text-lg italic">{b.title ?? "Untitled"}</h2>
                {b.author && <p className="text-sm text-[color:var(--muted)]">{b.author}</p>}
                <p className="text-xs text-[color:var(--muted)] mt-1">
                  {b.highlights?.[0]?.count ?? 0} highlights
                </p>
                {b.summary && (
                  <p className="text-sm mt-2 text-[color:var(--muted)] line-clamp-2">{b.summary}</p>
                )}
              </Link>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
