import "./globals.css";
import Link from "next/link";
import { sbServer } from "@/lib/supabase";

export const metadata = {
  title: "Dogear",
  description: "Your personal book memory — all the passages you've highlighted on your Kobo.",
};

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  const sb = sbServer();
  const { data: { user } } = await sb.auth.getUser();

  return (
    <html lang="en">
      <body className="min-h-screen">
        <header className="border-b border-[color:var(--rule)]">
          <nav className="max-w-3xl mx-auto px-6 py-4 flex items-center justify-between text-sm">
            <Link href="/" className="font-semibold tracking-wide">
              Dogear
            </Link>
            {user ? (
              <div className="flex gap-5 text-[color:var(--muted)]">
                <Link href="/" className="hover:text-black">Daily</Link>
                <Link href="/books" className="hover:text-black">Books</Link>
                <Link href="/timeline" className="hover:text-black">Timeline</Link>
                <Link href="/themes" className="hover:text-black">Themes</Link>
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
