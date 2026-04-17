export type Highlight = {
  id: string;
  text: string;
  annotation: string | null;
  web_note: string | null;
  chapter: string | null;
  is_favorite: boolean;
  highlighted_at: string | null;
  synced_at: string;
  book_id: string;
  book_title: string | null;
  book_author: string | null;
  book_cover_url: string | null;
  book_summary: string | null;
};

export type Book = {
  id: string;
  title: string | null;
  author: string | null;
  cover_url: string | null;
  summary: string | null;
  summary_is_ai_draft: boolean;
  highlight_count?: number;
};

export type Tag = {
  id: string;
  name: string;
  color: string | null;
  is_theme: boolean;
  sort_order: number;
};
