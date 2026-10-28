import { useEffect, useState } from "react";
import { DEFAULT_FILLERS } from "../shared/fillers.ts";
import { appendMetricLog, exportMetricLogs, loadMetricLogs } from "../shared/metricsLog.ts";
import { answerCounts, buildNarrative, judgeHeuristic, longestHelpfulStreak, QA_LEVEL_LABEL, type JudgeResult, type QaPair } from "../shared/qa.ts";
import { scenarioById } from "../shared/scenarios.ts";
import { reasonLabel } from "../shared/stuck.ts";
import type { ChatTurn, SessionSettings, StuckExpression } from "../shared/types.ts";
import { computeWpm, formatWpm, type SpeechSpan } from "../shared/wpm.ts";
import { loadPhrases, mergePhrases, savePhrases } from "../shared/memory.ts";

type Props = {
  settings: SessionSettings;
  mode: "mock" | "voice";
  turns: ChatTurn[];
  stuck: StuckExpression[];
  pairs: QaPair[];
  speechSpans: SpeechSpan[];
  fillers: string[];
  onSaved: (phrases: string[]) => void;
  onAgain: () => void;
};

async function loadJudge(pairs: QaPair[], fillers: readonly string[]): Promise<JudgeResult> {
  try {
    const response = await fetch("/api/feedback/judge", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ pairs }),
    });
    if (!response.ok) return judgeHeuristic(pairs, fillers);
    return (await response.json()) as JudgeResult;
  } catch {
    const local = judgeHeuristic(pairs, fillers);
    return { ...local, notice: "サーバーに届かなかったため、簡易判定です。" };
  }
}

export function ReviewScreen(props: Props) {
  const { stuck, onSaved, pairs } = props;
  const fillers = props.fillers.length > 0 ? props.fillers : DEFAULT_FILLERS;
  const [judge, setJudge] = useState<JudgeResult | null>(null);
  useEffect(() => {
    if (stuck.length === 0) return;
    const merged = mergePhrases(
      loadPhrases(),
      stuck.map((item) => item.text),
    );
    savePhrases(merged);
    onSaved(merged);
  }, [onSaved, stuck]);

  useEffect(() => {
    let cancelled = false;
    void loadJudge(pairs, fillers).then((result) => {
      if (!cancelled) setJudge(result);
    });
    return () => {
      cancelled = true;
    };
  }, [pairs, fillers]);

  useEffect(() => {
    if (!judge) return;
    const levels = judge.pairs.map((pair) => pair.level);
    const counts = answerCounts(levels);
    const speed = computeWpm({ mode: props.mode, turns: props.turns, spans: props.speechSpans, fillers });
    const last = loadMetricLogs().at(-1);
    if (last && last.mode === props.mode && last.pairCount === counts.total && Date.now() - Date.parse(last.at) < 3000) return;
    appendMetricLog({
      at: new Date().toISOString(),
      mode: props.mode,
      source: judge.source,
      answerCount: counts.answers,
      pairCount: counts.total,
      streak: longestHelpfulStreak(levels),
      learnerAskedOrExpanded: judge.learnerAskedOrExpanded,
      wordCount: props.mode === "voice" ? speed.wordCount : 0,
      speakingWpm: speed.speakingWpm,
      overallWpm: speed.overallWpm,
    });
  }, [judge, fillers, props.mode, props.speechSpans, props.turns]);

  const scenario = scenarioById(props.settings.scenarioId);
  const speed = computeWpm({ mode: props.mode, turns: props.turns, spans: props.speechSpans, fillers });
  const narrative = judge ? buildNarrative({ levels: judge.pairs.map((pair) => pair.level), learnerAskedOrExpanded: judge.learnerAskedOrExpanded }) : null;
  const counts = judge ? answerCounts(judge.pairs.map((pair) => pair.level)) : null;

  return (
    <section className="panel">
      <p className="eyebrow">振り返り</p>
      <h1>{scenario.labelJa}を終えました</h1>
      <p className="lede">流暢さ、発音、文法は点数にしません。見ているのは、質問に答えられたかと、話した速さだけです。</p>

      {!judge || !narrative || !counts ? <p>振り返りをまとめています。</p> : null}

      {judge && narrative && counts ? (
        <>
          <h2>この会話の様子</h2>
          <div className="metrics" data-testid="metrics">
            <p>質問に答えていた組: {counts.total === 0 ? "なし" : `${counts.answers} / ${counts.total}`}</p>
            <p className="hint">分子は「答えている」だけです。「一部だけ」は入れません。</p>
            <p>答えが続いた長さ: {longestHelpfulStreak(judge.pairs.map((pair) => pair.level))}</p>
            <p className="hint">「答えている」か「一部だけ答えている」が途切れずに続いた最長の組数です。</p>
            <p>自分から質問した、または話を広げた: {judge.learnerAskedOrExpanded ? "はい" : "いいえ"}</p>
            <p>発話しているあいだの速さ: {formatWpm(speed.speakingWpm, speed.available)}</p>
            <p className="hint">学習者が話していた区間だけを足した時間で割ります。考えている間は入れません。</p>
            <p>話し始めてから話し終えるまでの速さ: {formatWpm(speed.overallWpm, speed.available)}</p>
            <p className="hint">最初の発話開始から最後の発話終了までです。そのあいだの沈黙も、相手が話している時間も入ります。</p>
            {props.mode === "mock" ? <p data-testid="wpm-unavailable">テキストモードのため、速さは算出不可です。</p> : null}
            {judge.notice ? <p className="hint">{judge.notice}</p> : null}
            {judge.source === "llm" && judge.model ? <p className="hint">Q&Aの見立ては {judge.model} です。人の判断とずれることがあります。</p> : null}
          </div>

          {judge.pairs.length > 0 ? (
            <ul className="pair-list">
              {judge.pairs.map((pair) => (
                <li key={pair.index}>
                  <span>質問 {pair.index + 1}</span>
                  <p>{QA_LEVEL_LABEL[pair.level]}</p>
                </li>
              ))}
            </ul>
          ) : null}

          <h2>次に生かすこと</h2>
          <ol className="feedback" data-testid="feedback">
            <li>
              <span>続けたいこと</span>
              <p>{narrative.strength}</p>
            </li>
            {narrative.improvements.map((item) => (
              <li key={item}>
                <span>次の一手</span>
                <p>{item}</p>
              </li>
            ))}
          </ol>
        </>
      ) : null}

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
      {props.stuck.length > 0 ? <p className="hint">このブラウザに保存しました。次の会話の開始時に入れます。点数ではありません。</p> : null}
      <div className="actions">
        <button type="button" onClick={props.onAgain}>
          もう一度
        </button>
        <button type="button" className="secondary" onClick={() => exportMetricLogs()}>
          速さの記録を書き出す
        </button>
      </div>
    </section>
  );
}
