"use client";

import { useState } from "react";
import Link from "next/link";
import { sbBrowser } from "@/lib/supabase-browser";
import type { Category } from "@/lib/library";

export default function CategoryPicker({
  highlightId,
  categories,
  selected,
}: {
  highlightId: string;
  categories: Category[];
  selected: string[];
}) {
  const [on, setOn] = useState<string[]>(selected);

  async function toggle(id: string) {
    const sb = sbBrowser();
    const has = on.includes(id);
    const { error } = has
      ? await sb.from("highlight_tags").delete().eq("highlight_id", highlightId).eq("tag_id", id)
      : await sb.from("highlight_tags").insert({ highlight_id: highlightId, tag_id: id });
    if (error) return;
    setOn(has ? on.filter((item) => item !== id) : [...on, id]);
  }

  if (categories.length === 0) {
    return (
      <p className="mt-3 text-xs text-[color:var(--muted)]">
        <Link href="/categories" className="underline">Add a category</Link> to group this highlight.
      </p>
    );
  }

  return (
    <div className="mt-3 flex flex-wrap gap-2">
      {categories.map((category) => {
        const active = on.includes(category.id);
        return (
          <button
            key={category.id}
            type="button"
            onClick={() => toggle(category.id)}
            className={
              active
                ? "border border-[color:var(--ink)] bg-[color:var(--ink)] px-2 py-1 text-xs text-white"
                : "border border-[color:var(--rule)] px-2 py-1 text-xs text-[color:var(--muted)]"
            }
          >
            {category.name}
          </button>
        );
      })}
    </div>
  );
}
