import Link from "next/link";
import { sbServer } from "@/lib/supabase-server";
import LogoutButton from "./LogoutButton";
import DeviceTokenManager from "./DeviceTokenManager";

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

      <form method="post" action="/auth/device-code" className="mt-10 max-w-prose">
        <h2 className="text-sm uppercase tracking-widest text-[color:var(--muted)] mb-3">
          Sign in another device
        </h2>
        <p className="text-sm mb-3">
          The Kobo browser cannot open an email magic link. Create a code here, then on the
          Kobo open Log in and tap Have a code? The code works once and expires in 10 minutes.
        </p>
        <button
          type="submit"
          className="border-2 border-[color:var(--ink)] bg-[color:var(--ink)] text-white px-4 py-4 text-lg"
        >
          Sign in another device
        </button>
      </form>

      <DeviceTokenManager supabaseUrl={process.env.NEXT_PUBLIC_SUPABASE_URL ?? ""} />

      <div className="mt-10"><LogoutButton /></div>
    </section>
  );
}
