"use client";
import { sbBrowser } from "@/lib/supabase-browser";
import { useRouter } from "next/navigation";

export default function LogoutButton() {
  const router = useRouter();
  return (
    <button
      onClick={async () => {
        await sbBrowser().auth.signOut();
        router.push("/");
      }}
      className="text-sm text-[color:var(--accent)] hover:underline"
    >
      Log out
    </button>
  );
}
