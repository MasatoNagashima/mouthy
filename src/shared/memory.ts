import { clip } from "./textRules.ts";

const KEY = "mouthy.reusePhrases.v1";

export function mergePhrases(existing: string[], added: string[]): string[] {
  const seen = new Set<string>();
  const merged: string[] = [];
  for (const phrase of [...added, ...existing]) {
    const text = clip(phrase, 80);
    if (!text) continue;
    const id = text.toLowerCase();
    if (seen.has(id)) continue;
    seen.add(id);
    merged.push(text);
    if (merged.length >= 8) break;
  }
  return merged;
}

export function loadPhrases(): string[] {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return [];
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed.filter((item): item is string => typeof item === "string").slice(0, 8);
  } catch {
    return [];
  }
}

export function savePhrases(phrases: string[]): void {
  localStorage.setItem(KEY, JSON.stringify(mergePhrases([], phrases)));
}

export function clearPhrases(): void {
  localStorage.removeItem(KEY);
}
