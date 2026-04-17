import Link from "next/link";
import { format } from "date-fns";
import type { Highlight } from "@/lib/types";

export default function HighlightCard({ h, showBook = true }: { h: Highlight; showBook?: boolean }) {
  return (
    <article className="border-b border-[color:var(--rule)] py-8">
      <blockquote className="text-lg leading-relaxed">
        {h.text}
      </blockquote>
      {h.annotation && (
        <p className="mt-3 text-sm italic text-[color:var(--muted)]">
          — note on Kobo: {h.annotation}
        </p>
      )}
      {h.web_note && (
        <p className="mt-3 text-sm text-[color:var(--accent)]">
          {h.web_note}
        </p>
      )}
      <footer className="mt-4 flex items-center justify-between text-xs text-[color:var(--muted)]">
        <div>
          {showBook && (
            <Link href={`/books/${h.book_id}`} className="hover:text-black">
              <span className="italic">{h.book_title ?? "Untitled"}</span>
              {h.book_author ? <span> · {h.book_author}</span> : null}
            </Link>
          )}
        </div>
        <div>
          {h.highlighted_at ? format(new Date(h.highlighted_at), "MMM d, yyyy") : ""}
        </div>
      </footer>
    </article>
  );
}
