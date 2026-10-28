import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { App } from "../src/App.tsx";

const missingKey = {
  provider: "openai",
  model: "gpt-realtime-2.1",
  transcribeModel: "gpt-4o-mini-transcribe",
  voice: "marin",
  voiceReady: false,
  browserVoiceImplemented: true,
  message:
    "音声会話を始めるには、サーバーの環境変数 OPENAI_API_KEY が必要です。.env に設定してからサーバーを再起動してください。キーがなくても「テキストで試す」で、ロール選択から会話、振り返りまで確認できます。",
};

beforeEach(() => {
  localStorage.clear();
  vi.stubGlobal(
    "fetch",
    vi.fn(async (url: string) => {
      if (String(url).includes("/api/config")) {
        return new Response(JSON.stringify(missingKey), { status: 200, headers: { "Content-Type": "application/json" } });
      }
      throw new Error(`unexpected fetch ${url}`);
    }),
  );
});

afterEach(() => {
  cleanup();
  vi.useRealTimers();
  vi.unstubAllGlobals();
  localStorage.clear();
});

async function startMock() {
  render(<App />);
  expect(await screen.findByText(/OPENAI_API_KEY/)).toBeTruthy();
  expect(screen.getByRole("button", { name: "音声で話す" }).hasAttribute("disabled")).toBe(true);
  fireEvent.click(screen.getByRole("button", { name: "テキストで試す" }));
  expect(await screen.findByText(/Could you tell me a little about yourself/)).toBeTruthy();
}

test("mock flow records a stuck phrase and reuses it next time", async () => {
  await startMock();
  fireEvent.change(screen.getByPlaceholderText(/英語で話してみてください/), {
    target: { value: "えーと、営業です" },
  });
  expect(screen.getByTestId("live-caption").textContent).toContain("えーと、営業です");
  fireEvent.click(screen.getByRole("button", { name: "送る" }));
  expect(await screen.findByText("えーと、営業です")).toBeTruthy();
  const aiTurns = screen.getAllByTestId("ai-turn").map((node) => node.textContent ?? "");
  expect(aiTurns.some((text) => text.includes("What would you like to try?"))).toBe(true);
  expect(screen.getByTestId("transcript").textContent).not.toMatch(/点数|評価/);
  fireEvent.click(screen.getByRole("button", { name: "会話を終えて振り返る" }));
  expect(await screen.findByTestId("feedback")).toBeTruthy();
  const feedback = screen.getByTestId("feedback");
  expect(feedback.querySelectorAll("li").length).toBeLessThanOrEqual(2);
  expect(feedback.textContent).toContain("日本語から英語へ戻す");
  expect(screen.getByTestId("stuck-list").textContent).toContain("えーと、営業です");
  expect(screen.getByTestId("stuck-list").textContent).toContain("日本語への切り替え");
  fireEvent.click(screen.getByRole("button", { name: "もう一度" }));
  expect(await screen.findByText(/前回詰まった表現/)).toBeTruthy();
  expect(screen.getByText("えーと、営業です")).toBeTruthy();
  fireEvent.click(screen.getByRole("button", { name: "テキストで試す" }));
  expect(await screen.findByText(/Could you try using it once today/)).toBeTruthy();
});

test("a long silence produces one hint and no second question", async () => {
  render(<App />);
  await screen.findByText(/OPENAI_API_KEY/);
  fireEvent.click(screen.getByLabelText(/ブラウザの読み上げ/));
  fireEvent.change(screen.getByLabelText("ヒントまでの待ち（秒）"), { target: { value: "5" } });
  vi.useFakeTimers();
  fireEvent.click(screen.getByRole("button", { name: "テキストで試す" }));
  expect(screen.getByText(/Could you tell me a little about yourself/)).toBeTruthy();
  await act(async () => {
    vi.advanceTimersByTime(2000);
  });
  expect(screen.getByText(/相づち/)).toBeTruthy();
  await act(async () => {
    vi.advanceTimersByTime(3000);
  });
  const hint = screen.getByText(/No rush/);
  expect(hint.textContent?.match(/[?？]/g)).toHaveLength(1);
  expect(screen.getAllByText("ヒント")).toHaveLength(1);
  await act(async () => {
    vi.advanceTimersByTime(10_000);
  });
  expect(screen.getAllByText("ヒント")).toHaveLength(1);
});
