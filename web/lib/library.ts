export type Category = { id: string; name: string };

type FromClient = {
  from: (table: string) => {
    select: (columns: string) => any;
  };
};

export function sanitizeSearch(raw: string | undefined): string {
  if (!raw) return "";
  return raw.replace(/[%_\\,]/g, " ").replace(/\s+/g, " ").trim().slice(0, 80);
}

export async function loadCategoryIndex(
  sb: FromClient,
  userId: string,
  highlightIds: string[],
): Promise<{ categories: Category[]; selected: Record<string, string[]> }> {
  const { data: tags } = await sb
    .from("tags")
    .select("id, name")
    .eq("user_id", userId)
    .order("name", { ascending: true });
  const categories = ((tags ?? []) as Category[]).filter((tag) => tag.name);
  const selected: Record<string, string[]> = {};
  if (highlightIds.length === 0) return { categories, selected };
  const { data: links } = await sb
    .from("highlight_tags")
    .select("highlight_id, tag_id")
    .in("highlight_id", highlightIds);
  for (const row of (links ?? []) as { highlight_id: string; tag_id: string }[]) {
    selected[row.highlight_id] = [...(selected[row.highlight_id] ?? []), row.tag_id];
  }
  return { categories, selected };
}
