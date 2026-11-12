"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { sbBrowser } from "@/lib/supabase-browser";
import type { Tag } from "@/lib/types";

export default function ThemeManager({ initial }: { initial: Tag[] }) {
  const router = useRouter();
  const [tags, setTags] = useState<Tag[]>(initial);
  const [name, setName] = useState("");

  async function add() {
    if (!name.trim()) return;
    const sb = sbBrowser();
    const { data: { user } } = await sb.auth.getUser();
    if (!user) return;
    const { data } = await sb.from("tags").insert({
      user_id: user.id, name: name.trim(), is_theme: true,
      sort_order: tags.length,
    }).select().single();
    if (data) setTags([...tags, data as Tag]);
    setName("");
    router.refresh();
  }

  async function remove(id: string) {
    const sb = sbBrowser();
    await sb.from("tags").delete().eq("id", id);
    setTags(tags.filter((t) => t.id !== id));
    router.refresh();
  }

  const themes = tags.filter((t) => t.is_theme);

  return (
    <div>
      <div className="flex gap-2 mb-6">
        <input
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="e.g. discipline or a half-formed idea"
          className="flex-1 border border-[color:var(--rule)] px-3 py-2 text-sm"
        />
        <button onClick={add} className="border border-[color:var(--ink)] px-4 py-2 text-sm">
          Add category
        </button>
      </div>

      <ul className="flex flex-wrap gap-2">
        {themes.map((t) => (
          <li key={t.id} className="flex items-center gap-2 border border-[color:var(--rule)] px-3 py-1 text-sm">
            <span>{t.name}</span>
            <button onClick={() => remove(t.id)} className="text-[color:var(--muted)] hover:text-black">×</button>
          </li>
        ))}
      </ul>
    </div>
  );
}
