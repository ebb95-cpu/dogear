import Link from "next/link";
import { sbServer } from "@/lib/supabase-server";
import LogoutButton from "./LogoutButton";

export const revalidate = 0;

export default async function AccountPage() {
  const sb = sbServer();
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return <p>Please <Link href="/login">log in</Link>.</p>;

  const { count: hc } = await sb.from("highlights")
    .select("*", { count: "exact", head: true }).eq("user_id", user.id);
  const { count: bc } = await sb.from("books")
    .select("*", { count: "exact", head: true }).eq("user_id", user.id);

  return (
    <section>
      <h1 className="text-3xl font-semibold mb-6">Account</h1>
      <p className="text-sm text-[color:var(--muted)]">Signed in as {user.email}</p>
      <p className="mt-4 text-sm">{bc ?? 0} books · {hc ?? 0} highlights</p>

      <h2 className="text-sm uppercase tracking-widest text-[color:var(--muted)] mt-10 mb-3">
        Your Kobo sync token
      </h2>
      <p className="text-sm max-w-prose mb-3">
        Paste this into the Kobo sync script (one time). Your sync script uses it to upload
        highlights to your account. Keep it private.
      </p>
      <code className="block bg-white border border-[color:var(--rule)] px-3 py-2 text-xs break-all select-all">
        {user.id}
      </code>

      <div className="mt-10"><LogoutButton /></div>
    </section>
  );
}
