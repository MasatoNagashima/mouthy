import AVFoundation
import Foundation

enum RealtimeEvent {
    case aiDelta(id: String, text: String, at: Int)
    case aiAudio(Data)
    case aiDone(id: String)
    case learnerStarted(id: String, at: Int)
    case learnerPartial(id: String, text: String)
    case learnerFinal(id: String, text: String, at: Int)
    case learnerStopped(id: String, at: Int)
    case level(Double)
    case failure(String)
    case disconnected
}

/// OpenAI Realtime の WebSocket。短命トークンだけを使い、APIキーは持たない。
/// 音声の中身はこのアプリのサーバーを通らない。
/// セッションの設定（指示文・声・文字起こし・ノイズ除去・ターン検出）はサーバーが
/// 一時トークン発行時に入れているので、ここでは上書きしない。
actor RealtimeSocket {
    private let token: String
    private let model: String
    private let started = Date()
    private var task: URLSessionWebSocketTask?
    private var events: [RealtimeEvent] = []
    private var waiters: [CheckedContinuation<RealtimeEvent?, Never>] = []
    private var closed = false

    init(token: String, model: String) {
        self.token = token
        self.model = model
    }

    func connect() async throws {
        var components = URLComponents(string: "wss://api.openai.com/v1/realtime")!
        components.queryItems = [URLQueryItem(name: "model", value: model)]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = 16 * 1024 * 1024
        self.task = task
        task.resume()
        Task { [weak self] in await self?.receiveLoop() }
        try await send(["type": "response.create"])
    }

    func appendAudio(_ pcm: Data) async {
        guard !pcm.isEmpty else { return }
        try? await send(["type": "input_audio_buffer.append", "audio": pcm.base64EncodedString()])
    }

    func nextEvent() async -> RealtimeEvent? {
        if !events.isEmpty { return events.removeFirst() }
        if closed { return nil }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func close() async {
        closed = true
        task?.cancel(with: .goingAway, reason: nil)
        flush(nil)
    }

    private func send(_ object: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let text = String(data: data, encoding: .utf8) else { return }
        try await task?.send(.string(text))
    }

    private func receiveLoop() async {
        guard let task else { return }
        while !closed {
            do {
                let message = try await task.receive()
                let text: String?
                switch message {
                case .string(let value): text = value
                case .data(let data): text = String(data: data, encoding: .utf8)
                @unknown default: text = nil
                }
                if let text, let event = decode(text) { push(event) }
            } catch {
                if !closed { push(.disconnected) }
                closed = true
                flush(nil)
                return
            }
        }
    }

    private func push(_ event: RealtimeEvent) {
        if waiters.isEmpty {
            events.append(event)
        } else {
            waiters.removeFirst().resume(returning: event)
        }
    }

    private func flush(_ event: RealtimeEvent?) {
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume(returning: event) }
    }

    private func clock() -> Int { Int(Date().timeIntervalSince(started) * 1000) }

    private func decode(_ text: String) -> RealtimeEvent? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return nil }
        switch type {
        case "response.output_audio_transcript.delta", "response.audio_transcript.delta":
            let id = (json["response_id"] as? String) ?? (json["item_id"] as? String) ?? "ai"
            let delta = (json["delta"] as? String) ?? ""
            return delta.isEmpty ? nil : .aiDelta(id: id, text: delta, at: clock())
        case "response.output_audio.delta", "response.audio.delta":
            guard let delta = json["delta"] as? String, let pcm = Data(base64Encoded: delta), !pcm.isEmpty else { return nil }
            return .aiAudio(pcm)
        case "response.output_audio_transcript.done", "response.audio_transcript.done":
            let id = (json["response_id"] as? String) ?? "ai"
            return .aiDone(id: id)
        case "response.done":
            let response = json["response"] as? [String: Any]
            let id = (response?["id"] as? String) ?? "ai"
            return .aiDone(id: id)
        case "input_audio_buffer.speech_started":
            let id = (json["item_id"] as? String) ?? UUID().uuidString
            return .learnerStarted(id: id, at: clock())
        case "input_audio_buffer.speech_stopped":
            let id = (json["item_id"] as? String) ?? "learner"
            return .learnerStopped(id: id, at: clock())
        case "conversation.item.input_audio_transcription.delta":
            let id = (json["item_id"] as? String) ?? "learner"
            return .learnerPartial(id: id, text: (json["delta"] as? String) ?? "")
        case "conversation.item.input_audio_transcription.completed":
            let id = (json["item_id"] as? String) ?? "learner"
            return .learnerFinal(id: id, text: (json["transcript"] as? String) ?? "", at: clock())
        case "error":
            let detail = json["error"] as? [String: Any]
            let code = (detail?["code"] as? String) ?? ""
            // 発話がないまま確定しようとしたなど、会話を止めなくてよいエラーは無視する。
            if code == "input_audio_buffer_commit_empty" || code == "response_cancel_not_active" { return nil }
            return .failure((detail?["message"] as? String) ?? "音声サーバーでエラーが起きました。")
        default:
            return nil
        }
    }
}

/// マイク入力（24kHz PCM16 に変換して送る）と、AI の音声（24kHz PCM16）の再生。
/// 入力ノードの Voice Processing を有効にして、スピーカーから出た AI の声を
/// マイクが拾わないようにする（エコーキャンセル）。
///
/// iPhone は Voice Processing を有効にしたときや、音の出口（スピーカー・イヤホン）が
/// 変わったときに AVAudioEngine を黙って止めることがある。止まるとマイクも再生も
/// 同時に無音になるので、構成変更・中断の通知と1秒ごとの見回りで作り直す。
final class RealtimeAudio {
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    /// AVAudioPlayerNode は Float32 の非インターリーブしか再生できないので、受け取った PCM16 を変換して流す。
    private let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
    private var onLevel: ((Double) -> Void)?
    private var onPCM: ((Data) -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var running = false
    private let lock = NSLock()
    private var micSamples = 0
    private var micPeak: Float = 0
    private var aiSamples = 0
    private(set) var restarts = 0
    private(set) var voiceProcessing = false
    private(set) var lastError: String?

    func start(onLevel: @escaping (Double) -> Void, onPCM: @escaping (Data) -> Void) throws {
        self.onLevel = onLevel
        self.onPCM = onPCM
        try configureSession()
        running = true
        observe()
        try build()
    }

    func stop() {
        running = false
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        teardown()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// AI の音声（24kHz・モノラル・PCM16 リトルエンディアン）を再生キューに積む。
    func play(_ pcm: Data) {
        let frames = pcm.count / MemoryLayout<Int16>.size
        guard frames > 0 else { return }
        if engine?.isRunning != true { rebuild(reason: "再生前にエンジンが止まっていた") }
        guard let engine, engine.isRunning, let player,
              let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: AVAudioFrameCount(frames)),
              let out = buffer.floatChannelData
        else { return }
        buffer.frameLength = AVAudioFrameCount(frames)
        pcm.withUnsafeBytes { raw in
            for index in 0..<frames {
                let sample = Int16(littleEndian: raw.loadUnaligned(fromByteOffset: index * 2, as: Int16.self))
                out[0][index] = Float(sample) / 32_768
            }
        }
        if !player.isPlaying { player.play() }
        player.scheduleBuffer(buffer)
        lock.lock(); aiSamples += frames; lock.unlock()
    }

    /// 学習者が話しはじめたら、残っている AI の音声を捨てる（割り込み）。
    func interrupt() {
        guard let engine, engine.isRunning, let player else { return }
        player.stop()
        player.play()
    }

    /// 1秒ごとに呼ぶ。止まっていたら作り直し、画面に出す短い状態を返す。
    func healthCheck() -> String {
        if running, engine?.isRunning != true { rebuild(reason: "エンジンが止まっていた") }
        lock.lock()
        let micSec = Double(micSamples) / 24_000
        let aiSec = Double(aiSamples) / 24_000
        let peak = micPeak
        micPeak = 0
        lock.unlock()
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs.map { $0.portName }.joined(separator: ",")
        var parts = [
            String(format: "マイク送信 %.0f秒", micSec),
            String(format: "入力音量 %.2f", peak),
            String(format: "AI音声 %.0f秒", aiSec),
            engine?.isRunning == true ? "エンジン動作中" : "エンジン停止",
            "出力 \(outputs.isEmpty ? "なし" : outputs)",
            voiceProcessing ? "エコー除去オン" : "エコー除去オフ",
        ]
        if restarts > 0 { parts.append("再起動 \(restarts)回") }
        if let lastError { parts.append("エラー: \(lastError)") }
        return parts.joined(separator: " / ")
    }

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setPreferredSampleRate(48_000)
        try? session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true)
    }

    /// エンジンは毎回新しく作る（構成変更のあとで古いエンジンをつなぎ直すより確実）。
    private func build() throws {
        teardown()
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let input = engine.inputNode
        do {
            try input.setVoiceProcessingEnabled(true)
            voiceProcessing = true
        } catch {
            voiceProcessing = false
            lastError = "エコー除去を使えません"
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw RealtimeAudioError.microphoneUnavailable
        }
        let rate = format.sampleRate
        input.installTap(onBus: 0, bufferSize: 4_800, format: format) { [weak self] buffer, _ in
            self?.capture(buffer, rate: rate)
        }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
        engine.mainMixerNode.outputVolume = 1
        engine.prepare()
        try engine.start()
        player.play()
        self.engine = engine
        self.player = player
    }

    private func teardown() {
        player?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        player = nil
        engine = nil
    }

    private func rebuild(reason: String) {
        guard running, restarts < 10 else { return }
        restarts += 1
        do {
            try? AVAudioSession.sharedInstance().setActive(true)
            try build()
        } catch {
            lastError = "\(reason)・再開できず（\(error.localizedDescription)）"
        }
    }

    private func observe() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] note in
            guard let self, let changed = note.object as? AVAudioEngine, changed === self.engine else { return }
            self.rebuild(reason: "構成が変わった")
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            self.rebuild(reason: "中断から戻った")
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            try? self.configureSession()
            self.rebuild(reason: "音声サービスがリセットされた")
        })
    }

    /// マイクの音（48kHz などの Float32）を 24kHz・モノラル・PCM16 にして送る。
    /// AVAudioConverter は1回ずつ呼ぶと出力が空になることがあるので、平均を取って自前で間引く。
    private func capture(_ buffer: AVAudioPCMBuffer, rate: Double) {
        let frames = Int(buffer.frameLength)
        guard frames > 0, let onPCM else { return }
        var mono = [Float](repeating: 0, count: frames)
        if let floats = buffer.floatChannelData {
            for index in 0..<frames { mono[index] = floats[0][index] }
        } else if let ints = buffer.int16ChannelData {
            for index in 0..<frames { mono[index] = Float(ints[0][index]) / 32_768 }
        } else {
            return
        }
        let step = rate / 24_000
        let count = max(0, Int(Double(frames) / step))
        guard count > 0 else { return }
        var samples = [Int16](repeating: 0, count: count)
        var peak: Float = 0
        var sum: Double = 0
        for index in 0..<count {
            let from = Int(Double(index) * step)
            let to = min(frames, max(from + 1, Int(Double(index + 1) * step)))
            var acc: Float = 0
            for source in from..<to { acc += mono[source] }
            let value = max(-1, min(1, acc / Float(to - from)))
            peak = max(peak, abs(value))
            sum += Double(abs(value))
            samples[index] = Int16(value * 32_767)
        }
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        onPCM(data)
        onLevel?(min(1, (sum / Double(count)) * 8))
        lock.lock()
        micSamples += count
        micPeak = max(micPeak, peak)
        lock.unlock()
    }
}

enum RealtimeAudioError: LocalizedError {
    case microphoneUnavailable

    var errorDescription: String? { "マイクを使えませんでした。設定でマイクの許可を確認してください。" }
}
