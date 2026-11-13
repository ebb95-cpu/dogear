import { formatDistanceStrict } from "date-fns";

/** "Last synced 2 hours ago, 12 highlights" from the device credential row. */
export function formatLastSync(at: string | Date, count: number | null, now = new Date()): string {
  const ago = formatDistanceStrict(new Date(at), now, { addSuffix: true });
  const n = count ?? 0;
  const highlights = n === 1 ? "1 highlight" : `${n} highlights`;
  return `Last synced ${ago}, ${highlights}`;
}
