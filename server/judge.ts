import { JUDGE_INSTRUCTIONS, judgeHeuristic, mergeJudgeResult, type JudgeResult, type QaPair } from "../src/shared/qa.ts";

export function judgeSchema(): Record<string, unknown> {
  return {
    type: "object",
    additionalProperties: false,
    properties: {
      pairs: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          properties: {
            index: { type: "integer" },
            level: { type: "string", enum: ["answers", "partial", "off_topic", "no_answer"] },
            note: { type: "string" },
          },
          required: ["index", "level", "note"],
        },
      },
      learnerAskedOrExpanded: { type: "boolean" },
    },
    required: ["pairs", "learnerAskedOrExpanded"],
  };
}

export function judgeUserContent(pairs: QaPair[]): string {
  return JSON.stringify({
    instruction: JUDGE_INSTRUCTIONS,
    pairs: pairs.map((pair) => ({ index: pair.index, question: pair.question, answer: pair.answer })),
  });
}

export async function judgePairs(input: {
  pairs: QaPair[];
  fillers: readonly string[];
  apiKey: string;
  model: string;
  fetchImpl: typeof fetch;
}): Promise<JudgeResult> {
  if (!input.apiKey) return judgeHeuristic(input.pairs, input.fillers);
  if (input.pairs.length === 0) {
    return { ...judgeHeuristic(input.pairs, input.fillers), source: "llm", model: input.model, notice: null };
  }
  try {
    const response = await input.fetchImpl("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${input.apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: input.model,
        reasoning_effort: "none",
        max_completion_tokens: 800,
        messages: [
          { role: "system", content: JUDGE_INSTRUCTIONS },
          { role: "user", content: judgeUserContent(input.pairs) },
        ],
        response_format: {
          type: "json_schema",
          json_schema: { name: "mouthy_qa_judgement", strict: true, schema: judgeSchema() },
        },
      }),
    });
    const raw = await response.text();
    if (!response.ok) {
      const failed = judgeHeuristic(input.pairs, input.fillers);
      return { ...failed, notice: "モデル呼び出しに失敗したため、簡易判定です。" };
    }
    const parsed = JSON.parse(raw) as { choices?: Array<{ message?: { content?: string } }> };
    const content = parsed.choices?.[0]?.message?.content;
    if (!content) {
      const failed = judgeHeuristic(input.pairs, input.fillers);
      return { ...failed, notice: "モデルの応答が空だったため、簡易判定です。" };
    }
    return mergeJudgeResult(input.pairs, JSON.parse(content) as unknown, input.fillers, input.model);
  } catch {
    const failed = judgeHeuristic(input.pairs, input.fillers);
    return { ...failed, notice: "モデル呼び出しに失敗したため、簡易判定です。" };
  }
}
