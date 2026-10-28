import { buildInstructions, vadModeLabel } from "../shared/prompt.ts";
import { LEVELS, MAX_HINT_DELAY_MS, MAX_SILENCE_DURATION_MS, MIN_HINT_DELAY_MS, MIN_SILENCE_DURATION_MS, SCENARIOS, scenarioById } from "../shared/scenarios.ts";
import type { Eagerness, PublicConfig, ScenarioId, SessionSettings, VadMode } from "../shared/types.ts";

type Props = {
  config: PublicConfig | null;
  configError: string | null;
  settings: SessionSettings;
  phrases: string[];
  speak: boolean;
  consent: boolean;
  onChange: (settings: SessionSettings) => void;
  onSpeak: (speak: boolean) => void;
  onConsent: (consent: boolean) => void;
  onClearPhrases: () => void;
  onStart: (mode: "mock" | "voice") => void;
};

function clamp(value: number, min: number, max: number): number {
  if (!Number.isFinite(value)) return min;
  return Math.min(max, Math.max(min, value));
}

export function SetupScreen(props: Props) {
  const preview = buildInstructions({ ...props.settings, reusePhrases: props.phrases });
  const voiceDisabled = !props.config?.voiceReady || !props.consent;
  const voiceReason = !props.config
    ? "サーバーの状態を確認しています。"
    : props.config.voiceReady && !props.consent
      ? "音声を始めるには、音声の送信についての説明にチェックしてください。"
      : null;

  return (
    <section className="panel">
      <header className="hero">
        <p className="eyebrow">ローカルデモ</p>
        <h1>Mouthy</h1>
        <p className="lede">考えている間も待ってくれる、日本人のための英会話です。会話は英語、画面は日本語です。</p>
      </header>

      {props.configError ? <p className="banner bad">{props.configError}</p> : null}
      {props.config?.message ? <p className="banner">{props.config.message}</p> : null}
      {props.config && !props.config.message ? (
        <p className="banner ok">音声の準備ができています。モデル: {props.config.model}</p>
      ) : null}

      <ul className="points">
        <li>AIが先に話し、毎ターン短い反応と質問を1つだけ返します。</li>
        <li>沈黙では割り込まず、長く続いたときだけヒントを出します。</li>
        <li>会話が終わってから、指摘は1〜2点。詰まった表現も残します。</li>
      </ul>

      <fieldset>
        <legend>ロール</legend>
        <div className="choices">
          {SCENARIOS.map((scenario) => (
            <label className="choice" key={scenario.id}>
              <input
                type="radio"
                name="scenario"
                value={scenario.id}
                checked={props.settings.scenarioId === scenario.id}
                onChange={() => {
                  const next = scenarioById(scenario.id as ScenarioId);
                  props.onChange({ ...props.settings, scenarioId: next.id, goal: next.goalEn });
                }}
              />
              <span>
                <strong>{scenario.labelJa}</strong>
                <small>{scenario.descriptionJa}</small>
              </span>
            </label>
          ))}
        </div>
      </fieldset>

      <fieldset>
        <legend>話し方の目安</legend>
        <div className="choices compact">
          {LEVELS.map((level) => (
            <label className="choice" key={level.id}>
              <input
                type="radio"
                name="level"
                value={level.id}
                checked={props.settings.level === level.id}
                onChange={() => props.onChange({ ...props.settings, level: level.id })}
              />
              <span>
                <strong>{level.labelJa}</strong>
                <small>{level.descriptionJa}</small>
              </span>
            </label>
          ))}
        </div>
        <p className="hint">自動のレベル判定は入れていません。選んだ目安を、速度と語彙の指示に使います。</p>
      </fieldset>

      <label className="field">
        <span>今日のゴール</span>
        <input
          value={props.settings.goal}
          onChange={(event) => props.onChange({ ...props.settings, goal: event.target.value })}
        />
      </label>

      <label className="field">
        <span>追加の役割指示（任意）</span>
        <textarea
          rows={3}
          value={props.settings.extraInstructions}
          placeholder="例: ソフトウェアエンジニアの面接にしてください。"
          onChange={(event) => props.onChange({ ...props.settings, extraInstructions: event.target.value })}
        />
      </label>

      {props.phrases.length > 0 ? (
        <div className="saved">
          <h2>前回詰まった表現</h2>
          <p>このブラウザに残っています。次の会話の開始時に、自然に再登場させます。</p>
          <ul>
            {props.phrases.map((phrase) => (
              <li key={phrase}>{phrase}</li>
            ))}
          </ul>
          <button type="button" className="ghost" onClick={props.onClearPhrases}>
            記録を消す
          </button>
        </div>
      ) : null}

      <details className="advanced">
        <summary>間とヒントの設定</summary>
        <div className="grid">
          <label className="field">
            <span>ヒントまでの待ち（秒）</span>
            <input
              type="number"
              min={MIN_HINT_DELAY_MS / 1000}
              max={MAX_HINT_DELAY_MS / 1000}
              value={Math.round(props.settings.hintDelayMs / 1000)}
              onChange={(event) =>
                props.onChange({
                  ...props.settings,
                  hintDelayMs: clamp(Number(event.target.value) * 1000, MIN_HINT_DELAY_MS, MAX_HINT_DELAY_MS),
                })
              }
            />
          </label>
          <label className="field">
            <span>ヒントの上限（回）</span>
            <input
              type="number"
              min={1}
              max={5}
              value={props.settings.maxHints}
              onChange={(event) =>
                props.onChange({ ...props.settings, maxHints: clamp(Number(event.target.value), 1, 5) })
              }
            />
          </label>
        </div>
        <fieldset>
          <legend>ターンの取り方</legend>
          {(["semantic_vad", "server_vad"] as VadMode[]).map((mode) => (
            <label className="inline" key={mode}>
              <input
                type="radio"
                name="vad"
                checked={props.settings.vadMode === mode}
                onChange={() => props.onChange({ ...props.settings, vadMode: mode })}
              />
              {vadModeLabel(mode)}
            </label>
          ))}
          <p className="hint">
            意味で待つ方式が既定です。low は言いよどみをターンの終わりと判断せず、最大約8秒待ちます。無音タイマーを選ぶと、下のミリ秒が効きます。
          </p>
        </fieldset>
        <div className="grid">
          <label className="field">
            <span>待つ強さ（semantic VAD）</span>
            <select
              value={props.settings.eagerness}
              disabled={props.settings.vadMode !== "semantic_vad"}
              onChange={(event) => props.onChange({ ...props.settings, eagerness: event.target.value as Eagerness })}
            >
              <option value="low">low（いちばん待つ）</option>
              <option value="medium">medium</option>
              <option value="high">high</option>
              <option value="auto">auto</option>
            </select>
          </label>
          <label className="field">
            <span>無音の長さ（ミリ秒、server VAD）</span>
            <input
              type="number"
              min={MIN_SILENCE_DURATION_MS}
              max={MAX_SILENCE_DURATION_MS}
              disabled={props.settings.vadMode !== "server_vad"}
              value={props.settings.silenceDurationMs}
              onChange={(event) =>
                props.onChange({
                  ...props.settings,
                  silenceDurationMs: clamp(Number(event.target.value), MIN_SILENCE_DURATION_MS, MAX_SILENCE_DURATION_MS),
                })
              }
            />
          </label>
        </div>
      </details>

      <details>
        <summary>モデルへの指示を見る</summary>
        <pre className="prompt">{preview}</pre>
      </details>

      <label className="inline consent">
        <input type="checkbox" checked={props.speak} onChange={(event) => props.onSpeak(event.target.checked)} />
        テキストモードでは、ブラウザの読み上げで英語を再生する
      </label>

      <label className="inline consent">
        <input type="checkbox" checked={props.consent} onChange={(event) => props.onConsent(event.target.checked)} />
        音声はデモのサーバーに保存しません。音声モードでは、マイクの音声が短命のトークン経由で OpenAI に送られます。詰まった表現の記録はこのブラウザだけに残ります。
      </label>

      <div className="actions">
        <button type="button" onClick={() => props.onStart("mock")}>
          テキストで試す
        </button>
        <button type="button" className="secondary" disabled={voiceDisabled} onClick={() => props.onStart("voice")}>
          音声で話す
        </button>
      </div>
      {voiceReason ? <p className="hint">{voiceReason}</p> : null}
    </section>
  );
}
