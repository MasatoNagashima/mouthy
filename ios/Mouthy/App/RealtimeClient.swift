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
final class RealtimeAudio {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var converter: AVAudioConverter?
    /// AVAudioPlayerNode は Float32 の非インターリーブしか再生できないので、受け取った PCM16 を変換して流す。
    private let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!

    func start(onLevel: @escaping (Double) -> Void, onPCM: @escaping (Data) -> Void) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        let input = engine.inputNode
        try input.setVoiceProcessingEnabled(true)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0,
              let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: true)
        else { throw RealtimeAudioError.microphoneUnavailable }
        converter = AVAudioConverter(from: format, to: target)
        input.installTap(onBus: 0, bufferSize: 2400, format: format) { [weak self] buffer, _ in
            guard let self, let converter = self.converter else { return }
            let ratio = 24_000 / format.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
            guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var error: NSError?
            var consumed = false
            converter.convert(to: converted, error: &error) { _, status in
                if consumed {
                    status.pointee = .noDataNow
                    return nil
                }
                consumed = true
                status.pointee = .haveData
                return buffer
            }
            if let channel = converted.int16ChannelData, converted.frameLength > 0 {
                let count = Int(converted.frameLength)
                let data = Data(bytes: channel[0], count: count * MemoryLayout<Int16>.size)
                onPCM(data)
            }
            if let floats = buffer.floatChannelData {
                let count = Int(buffer.frameLength)
                var sum = 0.0
                for index in 0..<count { sum += Double(abs(floats[0][index])) }
                onLevel(min(1, (sum / Double(max(count, 1))) * 8))
            }
        }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
        engine.prepare()
        try engine.start()
        player.play()
    }

    func stop() {
        player.stop()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// AI の音声（24kHz・モノラル・PCM16 リトルエンディアン）を再生キューに積む。
    func play(_ pcm: Data) {
        let frames = pcm.count / MemoryLayout<Int16>.size
        guard frames > 0,
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
    }

    /// 学習者が話しはじめたら、残っている AI の音声を捨てる（割り込み）。
    func interrupt() {
        player.stop()
        player.play()
    }
}

enum RealtimeAudioError: LocalizedError {
    case microphoneUnavailable

    var errorDescription: String? { "マイクを使えませんでした。設定でマイクの許可を確認してください。" }
}
