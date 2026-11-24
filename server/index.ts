import dotenv from "dotenv";
import { createApp } from "./app.ts";
import { loadConfig } from "./config.ts";

dotenv.config();

const config = loadConfig();
const app = createApp({ config });

const host = process.env.HOST?.trim() || "127.0.0.1";
app.listen(config.port, host, () => {
  const ready = config.voiceProvider === "openai" && config.openaiApiKey ? "ready" : "missing-key";
  console.log(`mouthy token server on http://${host}:${config.port} (voice: ${config.voiceProvider}, ${ready})`);
});
