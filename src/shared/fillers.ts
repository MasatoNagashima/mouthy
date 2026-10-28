/** 語数から除くフィラー。環境変数 FILLER_WORDS（カンマ区切り）で差し替えられる。 */
export const DEFAULT_FILLERS = [
  "um",
  "uh",
  "uhh",
  "erm",
  "er",
  "hmm",
  "hm",
  "ah",
  "eh",
  "mm",
  "mhm",
  "えーと",
  "えーっと",
  "えっと",
  "あのー",
  "あの",
  "そのー",
  "その",
  "うーん",
  "えー",
] as const;

export function parseFillerList(raw: string | undefined | null): string[] {
  if (!raw?.trim()) return [...DEFAULT_FILLERS];
  const items = raw
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
  return items.length > 0 ? items : [...DEFAULT_FILLERS];
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export function isFillerToken(token: string, fillers: readonly string[]): boolean {
  const lower = token.toLowerCase();
  const collapsed = lower.replace(/(.)\1+$/u, "$1");
  return fillers.some((filler) => {
    const target = filler.toLowerCase();
    return target === lower || target === collapsed;
  });
}

export function countFillerHits(text: string, fillers: readonly string[] = DEFAULT_FILLERS): number {
  let count = 0;
  const ordered = [...fillers].sort((a, b) => b.length - a.length);
  for (const filler of ordered) {
    const pattern = /[A-Za-z]/.test(filler)
      ? new RegExp(`\\b${escapeRegExp(filler)}\\b`, "gi")
      : new RegExp(escapeRegExp(filler), "g");
    count += text.match(pattern)?.length ?? 0;
  }
  return count;
}

export function removeFillers(text: string, fillers: readonly string[] = DEFAULT_FILLERS): string {
  let cleaned = text;
  const ordered = [...fillers].sort((a, b) => b.length - a.length);
  for (const filler of ordered) {
    const pattern = /[A-Za-z]/.test(filler)
      ? new RegExp(`\\b${escapeRegExp(filler)}\\b`, "gi")
      : new RegExp(escapeRegExp(filler), "g");
    cleaned = cleaned.replace(pattern, " ");
  }
  return cleaned;
}

/** 英語の語（英数字）だけを数える。日本語のまとまりは語にしない。フィラーは除く。 */
export function countSpokenWords(text: string, fillers: readonly string[] = DEFAULT_FILLERS): number {
  const cleaned = removeFillers(text, fillers);
  const words = cleaned.match(/[A-Za-z0-9]+(?:'[A-Za-z0-9]+)?/g) ?? [];
  return words.filter((word) => !isFillerToken(word, fillers)).length;
}
