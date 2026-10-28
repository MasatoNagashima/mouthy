import { useEffect } from "react";
import { scenarioById } from "../shared/scenarios.ts";
import { reasonLabel } from "../shared/stuck.ts";
import type { ChatTurn, FeedbackItem, SessionSettings, StuckExpression } from "../shared/types.ts";
import { loadPhrases, mergePhrases, savePhrases } from "../shared/memory.ts";

type Props = {
  settings: SessionSettings;
  turns: ChatTurn[];
  stuck: StuckExpression[];
  feedback: FeedbackItem[];
  onSaved: (phrases: string[]) => void;
  onAgain: () => void;
};

export function ReviewScreen(props: Props) {
  const { stuck, onSaved } = props;
  useEffect(() => {
    if (stuck.length === 0) return;
    const merged = mergePhrases(
      loadPhrases(),
      stuck.map((item) => item.text),
    );
    savePhrases(merged);
    onSaved(merged);
  }, [onSaved, stuck]);

  const scenario = scenarioById(props.settings.scenarioId);
  const learnerTurns = props.turns.filter((turn) => turn.role === "learner").length;
  return (
    <section className="panel">
      <p className="eyebrow">振り返り</p>
      <h1>{scenario.labelJa}を終えました</h1>
      <p className="lede">会話中には点数も正誤も出していません。ここだけ、1〜2点に絞っています。あなたの発話は {learnerTurns} 回でした。</p>

      <h2>フィードバック</h2>
      <ol className="feedback" data-testid="feedback">
        {props.feedback.map((item) => (
          <li key={item.titleJa}>
            <span>{item.category === "grammar" ? "文法" : "表現"}</span>
            <h3>{item.titleJa}</h3>
            <p>{item.detailJa}</p>
          </li>
        ))}
      </ol>

      <h2>詰まった表現</h2>
      {props.stuck.length === 0 ? (
        <p>今回、詰まった表現は記録されませんでした。</p>
      ) : (
        <ul className="stuck" data-testid="stuck-list">
          {props.stuck.map((item) => (
            <li key={item.id}>
              <p>{item.text}</p>
              <small>
                {item.reasons.map((reason) => reasonLabel(reason)).join(" / ")}
                {item.pauseMs ? ` / 約${Math.round(item.pauseMs / 1000)}秒の間` : ""}
              </small>
              <small>{item.noteJa}</small>
            </li>
          ))}
        </ul>
      )}
      {props.stuck.length > 0 ? <p className="hint">このブラウザに保存しました。次の会話の開始時に入れます。</p> : null}
      <p className="hint">発音の精密な採点はしていません。音の聞き取り方は未決で、このデモは文字からの指摘だけです。</p>
      <button type="button" onClick={props.onAgain}>
        もう一度
      </button>
    </section>
  );
}
