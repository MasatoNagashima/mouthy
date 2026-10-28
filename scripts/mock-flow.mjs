import { mkdir } from "node:fs/promises";
import path from "node:path";
import puppeteer from "puppeteer-core";

const base = process.env.MOUTHY_URL ?? "http://127.0.0.1:5173";
const outDir = process.env.ARTIFACT_DIR ?? "/opt/cursor/artifacts";
const chrome = process.env.CHROME_PATH ?? "/usr/local/bin/google-chrome";

const browser = await puppeteer.launch({
  executablePath: chrome,
  headless: true,
  args: ["--no-sandbox", "--disable-dev-shm-usage"],
});

async function clickText(page, label) {
  const clicked = await page.evaluate((text) => {
    const nodes = [...document.querySelectorAll("button, summary, label")];
    const node = nodes.find((element) => element.textContent?.includes(text));
    if (!(node instanceof HTMLElement)) return false;
    node.click();
    return true;
  }, label);
  if (!clicked) throw new Error(`click target missing: ${label}`);
}

try {
  await mkdir(outDir, { recursive: true });
  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 900 });
  await page.goto(base, { waitUntil: "networkidle0" });
  await page.waitForFunction(() => document.body.innerText.includes("Mouthy"));
  await page.waitForFunction(() => document.body.innerText.includes("OPENAI_API_KEY"));
  await page.screenshot({ path: path.join(outDir, "mouthy_setup.png"), fullPage: true });

  await clickText(page, "間とヒントの設定");
  await page.evaluate(() => {
    const input = document.querySelector("input[type=number]");
    if (!(input instanceof HTMLInputElement)) throw new Error("hint input missing");
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")?.set;
    setter?.call(input, "5");
    input.dispatchEvent(new Event("input", { bubbles: true }));
    input.dispatchEvent(new Event("change", { bubbles: true }));
  });
  await clickText(page, "ブラウザの読み上げ");
  await clickText(page, "テキストで試す");
  await page.waitForFunction(() => document.body.innerText.includes("Could you tell me a little about yourself"));
  await page.waitForFunction(() => document.body.innerText.includes("No rush"), { timeout: 8000 });
  await new Promise((resolve) => setTimeout(resolve, 1500));
  const hintCount = await page.evaluate(() => document.querySelectorAll("[data-testid=ai-turn] em").length);
  if (hintCount !== 1) throw new Error(`expected one hint, saw ${hintCount}`);
  await page.evaluate(() => {
    const input = document.querySelector("textarea");
    if (!(input instanceof HTMLTextAreaElement)) throw new Error("composer missing");
    const setter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, "value")?.set;
    setter?.call(input, "えーと、営業です");
    input.dispatchEvent(new Event("input", { bubbles: true }));
  });
  await clickText(page, "送る");
  await page.waitForFunction(() => document.body.innerText.includes("What would you like to try?"));
  const during = await page.evaluate(() => document.body.innerText);
  if (during.includes("点数") || during.includes("評価")) {
    throw new Error("evaluation language appeared during the conversation");
  }
  await page.screenshot({ path: path.join(outDir, "mouthy_conversation.png"), fullPage: true });

  await clickText(page, "会話を終えて振り返る");
  await page.waitForFunction(() => document.body.innerText.includes("日本語から英語へ戻す"));
  await page.waitForFunction(() => document.body.innerText.includes("詰まった表現"));
  const feedbackCount = await page.evaluate(() => document.querySelectorAll("[data-testid=feedback] li").length);
  if (feedbackCount < 1 || feedbackCount > 2) throw new Error(`expected 1-2 feedback items, saw ${feedbackCount}`);
  const review = await page.evaluate(() => document.body.innerText);
  if (!review.includes("えーと、営業です") || !review.includes("日本語への切り替え")) {
    throw new Error("stuck expression was not listed");
  }
  await page.screenshot({ path: path.join(outDir, "mouthy_review.png"), fullPage: true });

  await page.setViewport({ width: 390, height: 844 });
  await clickText(page, "もう一度");
  await page.waitForFunction(() => document.body.innerText.includes("前回詰まった表現"));
  await page.screenshot({ path: path.join(outDir, "mouthy_setup_mobile.png"), fullPage: true });
  console.log("mock flow ok");
} finally {
  await browser.close();
}
