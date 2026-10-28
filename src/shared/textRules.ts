const BANNED_DURING_CONVERSATION =
  /\b(score|grade|points|incorrect|wrong|mistake)s?\b|評価|点数|減点|間違い/i;

export function questionCount(text: string): number {
  return text.match(/[?？]/g)?.length ?? 0;
}

export function containsBannedJudgement(text: string): boolean {
  return BANNED_DURING_CONVERSATION.test(text);
}

export function clip(text: string, max = 80): string {
  const trimmed = text.replace(/\s+/g, " ").trim();
  if (trimmed.length <= max) return trimmed;
  return `${trimmed.slice(0, max - 1)}…`;
}

export function containsJapanese(text: string): boolean {
  return /[\u3040-\u30ff\u4e00-\u9faf]/.test(text);
}

export function japaneseSnippet(text: string): string {
  const parts = text.match(/[\u3040-\u30ff\u4e00-\u9fafー]+/g);
  return clip((parts ?? []).join(""), 40);
}

function fillerPattern(): RegExp {
  return /\b(um+|uh+|erm+|hmm+|er+)\b|えーと|えっと|あのー?|そのー?|うーん/gi;
}

export function fillerCount(text: string): number {
  return text.match(fillerPattern())?.length ?? 0;
}

export function isHesitationHeavy(text: string): boolean {
  if (/how do (i|you) say|i don't know how|なんて言う|わからない|分かんない/i.test(text)) {
    return true;
  }
  const fillers = fillerCount(text);
  const stripped = text
    .replace(fillerPattern(), " ")
    .replace(/\s+/g, " ")
    .trim();
  if (fillers >= 2 && stripped.length < 24) return true;
  if (fillers >= 1 && stripped.length < 8) return true;
  return false;
}
