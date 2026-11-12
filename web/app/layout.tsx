import "./globals.css";
import Link from "next/link";
import { sbServer } from "@/lib/supabase-server";

export const metadata = {
  title: "Dogears",
  description: "Highlights from your Kobo, by book, by day, and by category.",
};

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  const sb = sbServer();
  const { data: { user } } = await sb.auth.getUser();

  return (
    <html lang="en">
      <body className="min-h-screen">
        <header className="border-b border-[color:var(--rule)]">
          <nav className="max-w-3xl mx-auto px-4 py-4 flex flex-wrap items-center gap-x-4 gap-y-2 text-sm">
            <Link href="/library" className="font-semibold tracking-wide mr-auto">
              Dogears
            </Link>
            {user ? (
              <div className="flex flex-wrap gap-x-4 gap-y-2 text-[color:var(--muted)]">
                <Link href="/today" className="hover:text-black">Today</Link>
                <Link href="/timeline" className="hover:text-black">All</Link>
                <Link href="/books" className="hover:text-black">Books</Link>
                <Link href="/categories" className="hover:text-black">Categories</Link>
                <Link href="/" className="hover:text-black">Daily</Link>
                <Link href="/account" className="hover:text-black">Account</Link>
              </div>
            ) : (
              <Link href="/login" className="text-[color:var(--accent)]">Log in</Link>
            )}
          </nav>
        </header>
        <main className="max-w-3xl mx-auto px-6 py-10">{children}</main>
      </body>
    </html>
  );
}
