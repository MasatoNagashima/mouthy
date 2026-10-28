export type SessionMetricLog = {
  at: string;
  mode: "mock" | "voice";
  source: "llm" | "heuristic";
  answerCount: number;
  pairCount: number;
  streak: number;
  learnerAskedOrExpanded: boolean;
  wordCount: number;
  speakingWpm: number | null;
  overallWpm: number | null;
};

const KEY = "mouthy.sessionMetrics.v1";

export function loadMetricLogs(): SessionMetricLog[] {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return [];
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed.filter((item): item is SessionMetricLog => !!item && typeof item === "object").slice(-100);
  } catch {
    return [];
  }
}

export function appendMetricLog(entry: SessionMetricLog): SessionMetricLog[] {
  const next = [...loadMetricLogs(), entry].slice(-100);
  localStorage.setItem(KEY, JSON.stringify(next));
  return next;
}

export function exportMetricLogs(): void {
  const blob = new Blob([JSON.stringify(loadMetricLogs(), null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = "mouthy-session-metrics.json";
  link.click();
  URL.revokeObjectURL(url);
}
