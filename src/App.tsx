import { useEffect, useState } from "react";
import { ReviewScreen } from "./components/ReviewScreen.tsx";
import { SetupScreen } from "./components/SetupScreen.tsx";
import { TalkScreen } from "./components/TalkScreen.tsx";
import { clearPhrases, loadPhrases } from "./shared/memory.ts";
import { defaultSettings } from "./shared/scenarios.ts";
import type { ChatTurn, FeedbackItem, PublicConfig, SessionSettings, StuckExpression } from "./shared/types.ts";
import { useConversation, type TalkSession } from "./useConversation.ts";

type Phase =
  | { name: "setup" }
  | { name: "talk"; session: TalkSession }
  | { name: "review"; settings: SessionSettings; turns: ChatTurn[]; stuck: StuckExpression[]; feedback: FeedbackItem[] };

export function App() {
  const [config, setConfig] = useState<PublicConfig | null>(null);
  const [configError, setConfigError] = useState<string | null>(null);
  const [settings, setSettings] = useState<SessionSettings>(() => defaultSettings());
  const [phrases, setPhrases] = useState<string[]>(() => loadPhrases());
  const [speak, setSpeak] = useState(true);
  const [consent, setConsent] = useState(false);
  const [phase, setPhase] = useState<Phase>({ name: "setup" });
  const live = useConversation(phase.name === "talk" ? phase.session : null);

  useEffect(() => {
    let cancelled = false;
    fetch("/api/config")
      .then(async (response) => {
        if (!response.ok) throw new Error("設定を読めませんでした。");
        return (await response.json()) as PublicConfig;
      })
      .then((body) => {
        if (!cancelled) setConfig(body);
      })
      .catch(() => {
        if (!cancelled) setConfigError("サーバーに接続できません。npm run dev が動いているか確認し、http://127.0.0.1:5173 を開いてください。");
      });
    return () => {
      cancelled = true;
    };
  }, []);

  if (phase.name === "talk") {
    return (
      <main>
        <TalkScreen
          settings={phase.session.settings}
          mode={phase.session.mode}
          status={live.status}
          backchannel={live.backchannel}
          turns={live.turns}
          error={live.error}
          notice={live.notice}
          draft={live.draft}
          onDraft={live.setDraft}
          onSend={live.sendDraft}
          onEnd={() => {
            const snapshot = live.endConversation();
            setPhase({ name: "review", settings: phase.session.settings, ...snapshot });
          }}
        />
      </main>
    );
  }

  if (phase.name === "review") {
    return (
      <main>
        <ReviewScreen
          settings={phase.settings}
          turns={phase.turns}
          stuck={phase.stuck}
          feedback={phase.feedback}
          onSaved={setPhrases}
          onAgain={() => setPhase({ name: "setup" })}
        />
      </main>
    );
  }

  return (
    <main>
      <SetupScreen
        config={config}
        configError={configError}
        settings={settings}
        phrases={phrases}
        speak={speak}
        consent={consent}
        onChange={setSettings}
        onSpeak={setSpeak}
        onConsent={setConsent}
        onClearPhrases={() => {
          clearPhrases();
          setPhrases([]);
        }}
        onStart={(mode) => {
          const nonce = Date.now();
          setPhase({
            name: "talk",
            session: {
              settings: { ...settings, reusePhrases: phrases },
              mode,
              speak: mode === "mock" && speak,
              nonce,
            },
          });
        }}
      />
    </main>
  );
}
