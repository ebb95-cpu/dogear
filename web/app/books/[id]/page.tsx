import Link from "next/link";
import { sbServer } from "@/lib/supabase-server";
import HighlightCard from "@/components/HighlightCard";
import CategoryPicker from "@/components/CategoryPicker";
import { loadCategoryIndex } from "@/lib/library";
import type { Highlight } from "@/lib/types";
import BookSummary from "./BookSummary";

export const revalidate = 0;

export default async function BookPage({ params }: { params: { id: string } }) {
  const sb = sbServer();
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return <p>Please <Link href="/login">log in</Link>.</p>;

  const { data: book } = await sb
    .from("books")
    .select("*")
    .eq("id", params.id)
    .eq("user_id", user.id)
    .single();

  if (!book) return <p>Book not found.</p>;

  const { data: highlights } = await sb
    .from("v_highlights")
    .select("*")
    .eq("book_id", book.id)
    .eq("user_id", user.id)
    .order("highlighted_at", { ascending: true });

  const list = (highlights ?? []) as Highlight[];
  const { categories, selected } = await loadCategoryIndex(
    sb,
    user.id,
    list.map((item) => item.id),
  );

  return (
    <section>
      <Link href="/books" className="text-sm text-[color:var(--muted)]">← all books</Link>
      <h1 className="text-3xl italic mt-4">{book.title ?? "Untitled"}</h1>
      {book.author && <p className="text-[color:var(--muted)] mt-1">{book.author}</p>}

      <BookSummary
        bookId={book.id}
        initialSummary={book.summary}
        isAiDraft={book.summary_is_ai_draft}
      />

      <hr className="my-8 border-[color:var(--rule)]" />

      <h2 className="text-sm uppercase tracking-widest text-[color:var(--muted)] mb-2">
        Highlights ({list.length})
      </h2>
      {list.map((h) => (
        <HighlightCard
          key={h.id}
          h={h}
          showBook={false}
          extra={
            <CategoryPicker
              highlightId={h.id}
              categories={categories}
              selected={selected[h.id] ?? []}
            />
          }
        />
      ))}
    </section>
  );
}
