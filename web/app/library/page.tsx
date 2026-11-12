import Link from "next/link";
import { sbServer } from "@/lib/supabase-server";

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

  return (
    <section>
      <h1 className="text-3xl font-semibold mb-2">Dogears</h1>
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
