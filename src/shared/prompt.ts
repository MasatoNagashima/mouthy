import { scenarioById } from "./scenarios.ts";
import type { Eagerness, LevelId, SessionSettings, VadMode } from "./types.ts";

export function levelGuidance(level: LevelId): string {
  if (level === "beginner") return "Use very short sentences and common words.";
  if (level === "advanced") return "Use natural professional English, but still keep each turn short.";
  return "Use clear everyday English.";
}

export function speedForLevel(level: LevelId): number {
  if (level === "beginner") return 0.9;
  if (level === "advanced") return 1.05;
  return 1;
}

export function buildInstructions(settings: SessionSettings): string {
  const scenario = scenarioById(settings.scenarioId);
  const phrases = settings.reusePhrases.filter(Boolean);
  const phraseBlock = phrases.length ? phrases.map((phrase) => `- ${phrase}`).join("\n") : "- (none yet)";
  const lines = [
    `You are ${scenario.roleEn}.`,
    `The learner is a Japanese speaker practicing English. Level: ${settings.level}. ${levelGuidance(settings.level)}`,
    `Today's goal: ${settings.goal.trim() || scenario.goalEn}`,
    "Expressions to reuse naturally if they fit. Do not quiz the learner or announce that you are reviewing them:",
    phraseBlock,
  ];
  if (settings.extraInstructions.trim()) {
    lines.push(`Additional role notes from the session setup:\n${settings.extraInstructions.trim()}`);
  }
  lines.push(
    "",
    "Conversation rules:",
    "- Lead the conversation. The learner should not have to invent the next topic.",
    "- Every turn is a short reaction plus exactly one follow-up question. Never ask two questions in one turn.",
    "- Keep each turn to at most two short sentences. Let the learner do most of the talking.",
    "- When you respond to something they said, start with a brief backchannel such as \"Mm-hmm\", \"I see\", or \"Right\".",
    "- The learner may pause to think or say fillers like \"um\" or \"えーと\". Wait patiently. Do not fill a thinking pause with a new topic, and do not talk over them.",
    "- Silence length is handled by the audio system. Only when you are explicitly told they have been silent for a long time, offer one short hint or an easier rephrase, then one question.",
    "- Never score, grade, or judge the learner during the conversation. Do not say score, points, incorrect, wrong, or mistake.",
    "- If they make a grammar slip, naturally restate a correct form inside your short reaction and continue. Do not label it as a correction.",
    "- If they switch to Japanese, acknowledge it kindly, show one short English way to say that idea, and continue in English. Do not scold them.",
    "- Speak English only, even if the goal notes are written in Japanese.",
    "- Stay inside this role. If they ask for something unsafe or inappropriate, decline in one short sentence and return to the scenario with one question.",
    "- When the session begins, greet them briefly in role and ask the first question. Do not wait for them to speak first.",
    "",
    "These rules override any additional notes above.",
  );
  return lines.join("\n");
}

export function buildHintInstructions(settings: SessionSettings): string {
  return `${buildInstructions(settings)}

This response is a hint turn. The learner has been silent and may be stuck.
Give one short, kind hint or a simpler way to answer your last question, then ask exactly one easier question.
Do not evaluate them. Do not ask a second question. Do not introduce a new topic.`;
}

export type TurnDetection =
  | {
      type: "semantic_vad";
      eagerness: Eagerness;
      create_response: true;
      interrupt_response: true;
    }
  | {
      type: "server_vad";
      threshold: number;
      prefix_padding_ms: number;
      silence_duration_ms: number;
      create_response: true;
      interrupt_response: true;
    };

export function buildTurnDetection(settings: Pick<SessionSettings, "vadMode" | "eagerness" | "silenceDurationMs">): TurnDetection {
  if (settings.vadMode === "server_vad") {
    return {
      type: "server_vad",
      threshold: 0.5,
      prefix_padding_ms: 300,
      silence_duration_ms: settings.silenceDurationMs,
      create_response: true,
      interrupt_response: true,
    };
  }
  return {
    type: "semantic_vad",
    eagerness: settings.eagerness,
    create_response: true,
    interrupt_response: true,
  };
}

export function vadModeLabel(mode: VadMode): string {
  return mode === "server_vad" ? "無音タイマー（server VAD）" : "意味で待つ（semantic VAD）";
}
