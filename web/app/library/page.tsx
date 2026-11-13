import Link from "next/link";
import { sbServer } from "@/lib/supabase-server";
import { formatLastSync } from "@/lib/last-sync";

export const revalidate = 0;

const views = [
  { href: "/timeline", title: "All", detail: "Every highlight, newest first." },
  { href: "/books", title: "Books", detail: "The same passages grouped by book." },
  { href: "/today", title: "Today", detail: "What you highlighted today." },
  { href: "/categories", title: "Categories", detail: "Group passages by a topic or idea." },
];

export default async function LibraryPage() {
  const sb = sbServer();
  const { data: { user } } = await sb.auth.getUser();

  let syncLine: string | null = null;
  if (user) {
    const { data, error } = await sb
      .from("device_credentials")
      .select("last_ingest_at, last_ingest_count")
      .not("last_ingest_at", "is", null)
      .order("last_ingest_at", { ascending: false })
      .limit(1);
    if (!error) {
      const row = data?.[0];
      syncLine = row?.last_ingest_at
        ? formatLastSync(row.last_ingest_at, row.last_ingest_count)
        : "No Kobo sync yet.";
    }
  }

  return (
    <section>
      <h1 className="text-3xl font-semibold mb-2">Dogears</h1>
      {syncLine && (
        <p className="border-2 border-[color:var(--ink)] px-4 py-3 mb-6 text-base">{syncLine}</p>
      )}
      <p className="text-sm text-[color:var(--muted)] mb-8 max-w-prose">
        Highlights from the Kobo. This page needs Wi-Fi on the reader. The stock reader does not keep a separate offline copy.
      </p>
      {user ? (
        <ul className="space-y-3">
          {views.map((view) => (
            <li key={view.href}>
              <Link href={view.href} className="block border border-[color:var(--rule)] px-4 py-4">
                <span className="text-lg">{view.title}</span>
                <span className="block text-sm text-[color:var(--muted)] mt-1">{view.detail}</span>
              </Link>
            </li>
          ))}
        </ul>
      ) : (
        <p>
          <Link href="/login" className="underline">Log in</Link> to open the library.
        </p>
      )}
    </section>
  );
}
