import dotenv from "dotenv";
import { createApp } from "./app.ts";
import { loadConfig } from "./config.ts";

dotenv.config();

const config = loadConfig();
const app = createApp({ config });

app.listen(config.port, "127.0.0.1", () => {
  const ready = config.voiceProvider === "openai" && config.openaiApiKey ? "ready" : "missing-key";
  console.log(`mouthy token server on http://127.0.0.1:${config.port} (voice: ${config.voiceProvider}, ${ready})`);
});
