import { NextResponse } from "next/server";
import { sbRoute } from "@/lib/supabase";

/**
 * POST /api/book-summary  { bookId }
 * Uses Anthropic (Claude) if ANTHROPIC_API_KEY set, else OpenAI.
 * Generates a one-paragraph "what this book was about" summary from
 * the user's own highlights + the book title/author.
 */
export async function POST(req: Request) {
  const sb = sbRoute();
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return NextResponse.json({ error: "not authed" }, { status: 401 });

  const { bookId } = await req.json();

  const { data: book } = await sb.from("books")
    .select("title,author").eq("id", bookId).eq("user_id", user.id).single();
  if (!book) return NextResponse.json({ error: "not found" }, { status: 404 });

  const { data: hs } = await sb.from("highlights")
    .select("text").eq("book_id", bookId).eq("user_id", user.id).limit(60);

  const excerpts = (hs ?? []).map((h: { text: string }) => `- ${h.text}`).join("\n");
  const prompt = `You are summarizing a book for the reader who highlighted these passages.
Book: "${book.title}" by ${book.author ?? "unknown"}.
Their highlights:
${excerpts}

Write ONE paragraph (4-6 sentences) titled "What this book was about".
Write it as if reminding the reader six months from now why they cared about this book.
Plain prose, no bullet points, no headings.`;

  const anth = process.env.ANTHROPIC_API_KEY;
  const oai = process.env.OPENAI_API_KEY;
  let summary = "";

  try {
    if (anth) {
      const r = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
          "x-api-key": anth,
          "anthropic-version": "2023-06-01",
          "content-type": "application/json",
        },
        body: JSON.stringify({
          model: "claude-sonnet-4-6",
          max_tokens: 400,
          messages: [{ role: "user", content: prompt }],
        }),
      });
      const j = await r.json();
      summary = j?.content?.[0]?.text?.trim() ?? "";
    } else if (oai) {
      const r = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: { authorization: `Bearer ${oai}`, "content-type": "application/json" },
        body: JSON.stringify({
          model: "gpt-4o-mini",
          messages: [{ role: "user", content: prompt }],
        }),
      });
      const j = await r.json();
      summary = j?.choices?.[0]?.message?.content?.trim() ?? "";
    } else {
      return NextResponse.json({ error: "no AI key configured" }, { status: 400 });
    }
  } catch (e) {
    return NextResponse.json({ error: "AI call failed" }, { status: 500 });
  }

  await sb.from("books").update({
    summary, summary_is_ai_draft: true,
  }).eq("id", bookId).eq("user_id", user.id);

  return NextResponse.json({ summary });
}
