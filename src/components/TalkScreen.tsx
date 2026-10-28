import { presentCaption } from "../shared/captions.ts";
import { scenarioById } from "../shared/scenarios.ts";
import type { ChatTurn, SessionSettings, TalkStatus } from "../shared/types.ts";

type Props = {
  settings: SessionSettings;
  mode: "mock" | "voice";
  status: TalkStatus;
  backchannel: string | null;
  turns: ChatTurn[];
  error: string | null;
  notice: string | null;
  draft: string;
  onDraft: (value: string) => void;
  onSend: () => void;
  onEnd: () => void;
};

const STATUS_LABEL: Record<TalkStatus, string> = {
  connecting: "接続しています",
  ai_speaking: "AIが話しています",
  waiting: "待っています。考えている間で大丈夫です",
  listening: "聞いています",
  error: "接続に問題があります",
};

function speakerLabel(role: ChatTurn["role"]): string {
  return role === "ai" ? "Mouthy" : "あなた";
}

function captionText(turn: ChatTurn): string {
  if (turn.text.trim()) return turn.text;
  if (turn.finality === "partial") return turn.role === "learner" ? "話しています…" : "…";
  return "";
}

export function TalkScreen(props: Props) {
  const scenario = scenarioById(props.settings.scenarioId);
  const shown = presentCaption(props.turns, props.mode === "mock" ? props.draft : "");
  const liveText = shown.live ? captionText(shown.live) : "";
  return (
    <section className="panel talk">
      <header className="talk-bar">
        <div>
          <p className="eyebrow">{props.mode === "mock" ? "テキスト（モック）" : "音声"}</p>
          <h1>{scenario.labelJa}</h1>
        </div>
        <button type="button" className="ghost" onClick={props.onEnd}>
          会話を終えて振り返る
        </button>
      </header>
      <p className="status" role="status">
        {STATUS_LABEL[props.status]}
        <span className="hint-inline">ヒントまでは {Math.round(props.settings.hintDelayMs / 1000)} 秒、最大 {props.settings.maxHints} 回</span>
      </p>
      {props.backchannel ? <p className="backchannel">相づち {props.backchannel}</p> : null}
      {props.error ? <p className="banner bad">{props.error}</p> : null}
      {props.notice ? <p className="banner">{props.notice}</p> : null}

      <div data-testid="transcript">
        <h2 className="section-label">会話</h2>
        <ol className="history">
          {shown.history.length === 0 ? <li className="empty">終わった発話がここに残ります。</li> : null}
          {shown.history.map((turn) => (
            <li
              key={turn.id}
              className={`${turn.role === "ai" ? "ai" : "learner"}${turn.finality === "partial" ? " partial" : ""}${turn.finality === "failed" ? " failed" : ""}`}
              data-testid={turn.role === "ai" ? "ai-turn" : "learner-turn"}
            >
              <span>{speakerLabel(turn.role)}</span>
              {turn.isHint ? <em>ヒント</em> : null}
              <p>{turn.text}</p>
            </li>
          ))}
        </ol>
        <div
          className={`live-caption${shown.live?.finality === "partial" ? " partial" : ""}`}
          data-testid="live-caption"
          aria-live="polite"
        >
          <span>{shown.live ? speakerLabel(shown.live.role) : "いまの発話"}</span>
          {shown.live?.isHint ? <em>ヒント</em> : null}
          <p>{liveText || "いま話している内容がここに出ます。"}</p>
        </div>
      </div>

      {props.mode === "mock" ? (
        <form
          className="composer"
          onSubmit={(event) => {
            event.preventDefault();
            props.onSend();
          }}
        >
          <label>
            <span className="visually-hidden">英語のメッセージ</span>
            <textarea
              rows={3}
              value={props.draft}
              placeholder="英語で話してみてください。詰まったら日本語でも大丈夫です。"
              onChange={(event) => props.onDraft(event.target.value)}
            />
          </label>
          <button type="submit">送る</button>
        </form>
      ) : (
        <p className="hint">マイクで話してください。考えている間は、そのまま黙っていて大丈夫です。Chrome でマイクを許可してください。</p>
      )}
    </section>
  );
}
