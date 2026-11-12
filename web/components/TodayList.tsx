"use client";

import HighlightCard from "@/components/HighlightCard";
import CategoryPicker from "@/components/CategoryPicker";
import type { Highlight } from "@/lib/types";
import type { Category } from "@/lib/library";

export default function TodayList({
  highlights,
  categories,
  selected,
}: {
  highlights: Highlight[];
  categories: Category[];
  selected: Record<string, string[]>;
}) {
  const start = new Date();
  start.setHours(0, 0, 0, 0);
  const today = highlights.filter((highlight) => {
    if (!highlight.highlighted_at) return false;
    return new Date(highlight.highlighted_at) >= start;
  });

  if (today.length === 0) {
    return (
      <p className="text-[color:var(--muted)]">
        Nothing highlighted today yet. Passages sync the next time the Kobo is on Wi-Fi.
      </p>
    );
  }

  return (
    <div>
      {today.map((highlight) => (
        <HighlightCard key={highlight.id} h={highlight} extra={
          <CategoryPicker
            highlightId={highlight.id}
            categories={categories}
            selected={selected[highlight.id] ?? []}
          />
        } />
      ))}
    </div>
  );
}
