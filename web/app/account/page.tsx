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

      <DeviceTokenManager supabaseUrl={process.env.NEXT_PUBLIC_SUPABASE_URL ?? ""} />

      <div className="mt-10"><LogoutButton /></div>
    </section>
  );
}
