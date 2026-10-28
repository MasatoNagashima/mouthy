import { clip, containsJapanese, japaneseSnippet } from "./textRules.ts";
import type { FeedbackItem, StuckExpression } from "./types.ts";

const GRAMMAR: Array<{ pattern: RegExp; titleJa: string; detail: (quote: string) => string }> = [
  {
    pattern: /\b(i|we|they) go\b[^.?!]{0,40}\byesterday\b/i,
    titleJa: "過去の言い方",
    detail: (quote) => `「${quote}」は、過去なら "I went yesterday." のように言うと自然です。会話の途中では止めず、ここだけ残します。`,
  },
  {
    pattern: /\bhe go\b/i,
    titleJa: "三人称の動詞",
    detail: (quote) => `「${quote}」は "he goes" とすると形が揃います。次に使うときだけ意識すれば十分です。`,
  },
  {
    pattern: /\bmore better\b/i,
    titleJa: "比較の形",
    detail: (quote) => `「${quote}」は "better" だけで比較になります。`,
  },
  {
    pattern: /\bi am agree\b/i,
    titleJa: "agree の形",
    detail: (quote) => `「${quote}」は "I agree" が自然です。`,
  },
];

function grammarItem(learnerTexts: string[]): FeedbackItem | null {
  for (const text of learnerTexts) {
    for (const rule of GRAMMAR) {
      if (rule.pattern.test(text)) {
        const quote = clip(text, 80);
        return { category: "grammar", titleJa: rule.titleJa, detailJa: rule.detail(quote), quote };
      }
    }
  }
  return null;
}

export function buildFeedback(learnerTexts: string[], stuck: StuckExpression[]): FeedbackItem[] {
  const items: FeedbackItem[] = [];
  const grammar = grammarItem(learnerTexts);
  if (grammar) items.push(grammar);

  const japanese = stuck.find((item) => item.reasons.includes("japanese"));
  if (japanese && items.length < 2) {
    const snippet = japaneseSnippet(japanese.text) || clip(japanese.text, 40);
    items.push({
      category: "expression",
      titleJa: "日本語から英語へ戻す",
      detailJa: `「${snippet}」で日本語が出ていました。会話中は受け止め、あとから英語の一文にすると定着しやすいです。次は "Let me say that in English." から入ってみてください。`,
      quote: snippet,
    });
  }

  const hesitation = stuck.find((item) => item.reasons.includes("hesitation"));
  if (hesitation && items.length < 2 && !items.some((item) => item.quote === clip(hesitation.text, 80))) {
    items.push({
      category: "expression",
      titleJa: "言い出しのフィラー",
      detailJa: `「${clip(hesitation.text, 80)}」のあたりで言葉を探していました。最初の3語だけ決めてから話すと楽になります。例: "I used to..."`,
      quote: clip(hesitation.text, 80),
    });
  }

  const paused = stuck.find((item) => item.reasons.includes("long_pause") || item.reasons.includes("hint_needed"));
  if (paused && items.length < 2) {
    items.push({
      category: "expression",
      titleJa: "間が長くなった表現",
      detailJa: `「${clip(paused.text, 80)}」の前に考える間がありました。この表現は次回の開始時に、自然にもう一度出てきます。`,
      quote: clip(paused.text, 80),
    });
  }

  if (items.length === 0) {
    items.push({
      category: "expression",
      titleJa: "今回は指摘を増やしません",
      detailJa: containsJapanese(learnerTexts.join(" "))
        ? "会話の途中では正誤を重ねません。次は日本語で言いたかったことを、短い英語一文にしてみてください。"
        : "会話の途中では正誤を重ねません。文字の上では、絞って返すような詰まりは見つかりませんでした。次回はいつもの一文より、少しだけ長く話してみてください。",
    });
  }

  return items.slice(0, 2);
}
