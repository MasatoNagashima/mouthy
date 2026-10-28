type Handlers = {
  onEvent: (event: unknown) => void;
  onOpen: () => void;
  onConnectionError: (message: string) => void;
};

export class OpenAIRealtimeSession {
  private pc: RTCPeerConnection | null = null;
  private dc: RTCDataChannel | null = null;
  private local: MediaStream | null = null;
  private audio: HTMLAudioElement | null = null;
  private closed = false;

  constructor(private readonly handlers: Handlers) {}

  async connect(ephemeralKey: string): Promise<void> {
    if (!navigator.mediaDevices?.getUserMedia) {
      throw new Error("このブラウザはマイクに対応していません。Chrome で開いてください。");
    }
    const pc = new RTCPeerConnection();
    this.pc = pc;
    const audio = document.createElement("audio");
    audio.autoplay = true;
    audio.setAttribute("data-mouthy-remote", "true");
    this.audio = audio;
    pc.ontrack = (event) => {
      audio.srcObject = event.streams[0];
      void audio.play().catch(() => {
        this.handlers.onConnectionError("音声の再生がブロックされました。画面をタップしてからもう一度お試しください。");
      });
    };
    pc.onconnectionstatechange = () => {
      if (this.closed) return;
      if (pc.connectionState === "failed") {
        this.handlers.onConnectionError("音声の接続が切れました。もう一度開始してください。");
      }
    };

    try {
      this.local = await navigator.mediaDevices.getUserMedia({
        audio: { echoCancellation: true, noiseSuppression: true, channelCount: 1 },
      });
    } catch {
      throw new Error("マイクを使えないため、音声会話を始められません。ブラウザの許可を確認するか、テキストで試してください。");
    }
    for (const track of this.local.getTracks()) pc.addTrack(track);

    const dc = pc.createDataChannel("oai-events");
    this.dc = dc;
    dc.addEventListener("open", () => {
      if (!this.closed) this.handlers.onOpen();
    });
    dc.addEventListener("message", (event) => {
      try {
        this.handlers.onEvent(JSON.parse(String(event.data)));
      } catch {
        this.handlers.onConnectionError("音声APIからのデータを読めませんでした。");
      }
    });

    const offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    await waitForIce(pc);
    const sdp = pc.localDescription?.sdp;
    if (!sdp) throw new Error("接続用のデータを作れませんでした。");

    const response = await fetch("https://api.openai.com/v1/realtime/calls", {
      method: "POST",
      body: sdp,
      headers: {
        Authorization: `Bearer ${ephemeralKey}`,
        "Content-Type": "application/sdp",
      },
    });
    const answer = await response.text();
    if (!response.ok || answer.trim().startsWith("{") || answer.trim().startsWith("<")) {
      throw new Error("OpenAI との音声接続に失敗しました。モデル名とキーの権限を確認してください。");
    }
    await pc.setRemoteDescription({ type: "answer", sdp: answer });
  }

  requestResponse(): void {
    this.send({ type: "response.create" });
  }

  requestHint(instructions: string): void {
    this.send({ type: "response.create", response: { instructions } });
  }

  close(): void {
    this.closed = true;
    this.dc?.close();
    this.pc?.close();
    this.local?.getTracks().forEach((track) => track.stop());
    if (this.audio) {
      this.audio.pause();
      this.audio.srcObject = null;
      this.audio.remove();
    }
    this.dc = null;
    this.pc = null;
    this.local = null;
    this.audio = null;
  }

  private send(payload: unknown): void {
    if (this.dc?.readyState === "open") this.dc.send(JSON.stringify(payload));
  }
}

function waitForIce(pc: RTCPeerConnection): Promise<void> {
  if (pc.iceGatheringState === "complete") return Promise.resolve();
  return new Promise((resolve) => {
    let timer = 0;
    const finish = () => {
      window.clearTimeout(timer);
      pc.removeEventListener("icegatheringstatechange", onChange);
      resolve();
    };
    const onChange = () => {
      if (pc.iceGatheringState === "complete") finish();
    };
    timer = window.setTimeout(finish, 2000);
    pc.addEventListener("icegatheringstatechange", onChange);
  });
}
