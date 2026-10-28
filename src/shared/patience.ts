import type { TalkStatus } from "./types.ts";

const LISTEN_PHRASES = ["Mm-hmm.", "I see.", "Right.", "Okay."];

export type PatienceView = {
  status: Extract<TalkStatus, "ai_speaking" | "waiting" | "listening">;
  backchannel: string | null;
};

export class PatienceController {
  private hintTimer: ReturnType<typeof setTimeout> | null = null;
  private reassuranceTimer: ReturnType<typeof setTimeout> | null = null;
  private listenTimer: ReturnType<typeof setTimeout> | null = null;
  private listening = false;
  private hintsGiven = 0;
  private unansweredHint = false;
  private listenIndex = 0;
  private disposed = false;

  constructor(
    private readonly options: {
      hintDelayMs: number;
      maxHints: number;
      waitReassuranceMs: number;
      listenBackchannelMs: number;
      onChange: (view: PatienceView) => void;
      onHint: () => void;
    },
  ) {}

  aiStarted(): void {
    this.clearWaitTimers();
    this.clearListenTimer();
    this.listening = false;
    this.emit("ai_speaking", null);
  }

  aiFinished(): void {
    if (this.disposed || this.listening) return;
    this.armWait();
    this.emit("waiting", null);
  }

  userSpeechStarted(): void {
    if (this.disposed) return;
    this.unansweredHint = false;
    this.clearWaitTimers();
    this.listening = true;
    this.emit("listening", null);
    this.clearListenTimer();
    this.listenTimer = setTimeout(() => {
      if (!this.listening || this.disposed) return;
      const phrase = LISTEN_PHRASES[this.listenIndex % LISTEN_PHRASES.length];
      this.listenIndex += 1;
      this.emit("listening", phrase);
    }, this.options.listenBackchannelMs);
  }

  userSpeechStopped(): void {
    if (this.disposed) return;
    this.listening = false;
    this.clearListenTimer();
    this.emit("waiting", null);
  }

  resumeWaiting(): void {
    if (this.disposed) return;
    this.listening = false;
    this.clearListenTimer();
    this.armWait();
    this.emit("waiting", null);
  }

  dispose(): void {
    this.disposed = true;
    this.clearWaitTimers();
    this.clearListenTimer();
  }

  private armWait(): void {
    this.clearWaitTimers();
    this.reassuranceTimer = setTimeout(() => {
      if (this.disposed || this.listening) return;
      this.emit("waiting", "Mm-hmm.");
    }, this.options.waitReassuranceMs);
    if (this.unansweredHint || this.hintsGiven >= this.options.maxHints) return;
    this.hintTimer = setTimeout(() => {
      if (this.disposed || this.listening || this.unansweredHint) return;
      if (this.hintsGiven >= this.options.maxHints) return;
      this.hintsGiven += 1;
      this.unansweredHint = true;
      this.options.onHint();
    }, this.options.hintDelayMs);
  }

  private emit(status: PatienceView["status"], backchannel: string | null): void {
    if (this.disposed) return;
    this.options.onChange({ status, backchannel });
  }

  private clearWaitTimers(): void {
    if (this.hintTimer) clearTimeout(this.hintTimer);
    if (this.reassuranceTimer) clearTimeout(this.reassuranceTimer);
    this.hintTimer = null;
    this.reassuranceTimer = null;
  }

  private clearListenTimer(): void {
    if (this.listenTimer) clearTimeout(this.listenTimer);
    this.listenTimer = null;
  }
}
