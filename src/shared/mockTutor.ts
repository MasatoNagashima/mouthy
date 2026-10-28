import { scenarioById } from "./scenarios.ts";
import { clip, containsBannedJudgement, containsJapanese, isHesitationHeavy, questionCount } from "./textRules.ts";
import type { LevelId, ScenarioId, SessionSettings } from "./types.ts";

const OPENINGS: Record<ScenarioId, string> = {
  interview: "Thanks for coming in today. Could you tell me a little about yourself?",
  daily: "Hey, it is good to see you. How was your weekend?",
  business: "Hi, thanks for joining the call. How is the project going?",
  travel: "Welcome. How can I help you today?",
  warmup: "Hi. What is one small thing that happened today?",
};

const HINTS: Record<ScenarioId, string> = {
  interview: "No rush. You could start with \"I am a...\". What do you do now?",
  daily: "No rush. You could start with \"I went...\". What did you do?",
  business: "No rush. You could start with \"We are working on...\". What is the status?",
  travel: "No rush. You could start with \"I would like...\". What do you need?",
  warmup: "No rush. You could start with \"Today I...\". What happened?",
};

const QUESTIONS: Record<ScenarioId, Record<LevelId, string[]>> = {
  interview: {
    beginner: ["What job do you want?", "What did you study?", "Why this company?"],
    intermediate: ["What made you interested in this role?", "What is a result you are proud of?", "What kind of team do you want?"],
    advanced: ["What would you change in your current process?", "How do you handle a tight deadline?", "What do you want from the next role?"],
  },
  daily: {
    beginner: ["What did you eat?", "Where did you go?", "Who did you meet?"],
    intermediate: ["What was the best part?", "What happened after that?", "How did you spend the evening?"],
    advanced: ["What would you do differently next time?", "How did that change your week?", "What are you planning next?"],
  },
  business: {
    beginner: ["What are you working on?", "Is it on time?", "What do you need?"],
    intermediate: ["What is blocking the work?", "Who needs to know about this?", "What should we do next?"],
    advanced: ["What tradeoff are you making?", "How will you know it worked?", "What support do you need from us?"],
  },
  travel: {
    beginner: ["What would you like?", "For what time?", "How many people?"],
    intermediate: ["Would you like anything else?", "What time works for you?", "Where would you like to sit?"],
    advanced: ["Is there a preference I should know?", "What time should I note?", "How else can I help?"],
  },
  warmup: {
    beginner: ["What did you do today?", "Was it a good day?", "What is next?"],
    intermediate: ["What stayed with you?", "What happened next?", "How are you feeling now?"],
    advanced: ["What detail do you remember most?", "Why did that stand out?", "Where does the story go next?"],
  },
};

const REACTIONS = ["Mm-hmm, that helps.", "I see.", "Right, thank you.", "Got it."];

const RECASTS: Array<{ pattern: RegExp; text: string }> = [
  { pattern: /\bhe go\b/i, text: "Mm-hmm, he goes there a lot. Where does he go?" },
  { pattern: /\bi am agree\b/i, text: "I see, you agree. What do you agree with?" },
  { pattern: /\bmore better\b/i, text: "Right, so it felt better. What made it better?" },
  { pattern: /\b(i|we|they) go\b[^.?!]{0,40}\byesterday\b/i, text: "Got it, so you went yesterday. What did you do there?" },
];

const FALLBACK = "Mm-hmm, I am with you. What would you like to say next?";

function safePhrase(phrase: string): string {
  return clip(phrase, 60).replace(/["\n\r?？]/g, "");
}

function ensureSpeakable(text: string): string {
  if (questionCount(text) === 1 && !containsBannedJudgement(text)) return text;
  return FALLBACK;
}

export function mockTutorReply(input: {
  scenarioId: ScenarioId;
  level: LevelId;
  userText: string | null;
  turnIndex: number;
  hint: boolean;
  reusePhrases: string[];
}): { text: string; isHint: boolean } {
  const scenario = scenarioById(input.scenarioId);
  if (input.hint) {
    return { text: ensureSpeakable(HINTS[scenario.id]), isHint: true };
  }
  const userText = input.userText?.trim() ?? "";
  if (!userText && input.turnIndex === 0) {
    const phrase = input.reusePhrases.map((item) => item.trim()).find(Boolean);
    const opening = phrase
      ? `Last time, "${safePhrase(phrase)}" was hard to say. Could you try using it once today?`
      : OPENINGS[scenario.id];
    return { text: ensureSpeakable(opening), isHint: false };
  }
  if (userText && containsJapanese(userText)) {
    return { text: ensureSpeakable("That is okay. In English you might say \"I want to say this in English.\" What would you like to try?"), isHint: false };
  }
  if (userText && isHesitationHeavy(userText)) {
    return { text: ensureSpeakable("Mm-hmm, take your time. Could you start with \"I usually\"?"), isHint: false };
  }
  if (userText) {
    const recast = RECASTS.find((item) => item.pattern.test(userText));
    if (recast) return { text: ensureSpeakable(recast.text), isHint: false };
  }
  const reaction = REACTIONS[Math.abs(input.turnIndex) % REACTIONS.length];
  const pool = QUESTIONS[scenario.id][input.level];
  const question = pool[Math.abs(input.turnIndex) % pool.length];
  return { text: ensureSpeakable(`${reaction} ${question}`), isHint: false };
}

export function mockReplyForSettings(settings: SessionSettings, userText: string | null, turnIndex: number, hint: boolean): { text: string; isHint: boolean } {
  return mockTutorReply({
    scenarioId: settings.scenarioId,
    level: settings.level,
    userText,
    turnIndex,
    hint,
    reusePhrases: settings.reusePhrases,
  });
}
