import AVFoundation
import Foundation

enum RealtimeEvent {
    case aiDelta(id: String, text: String, at: Int)
    case aiDone(id: String)
    case learnerStarted(id: String, at: Int)
    case learnerPartial(id: String, text: String)
    case learnerFinal(id: String, text: String, at: Int)
    case learnerStopped(id: String, at: Int)
    case level(Double)
    case disconnected
}

/// OpenAI Realtime の WebSocket。短命トークンだけを使い、APIキーは持たない。
/// 音声の中身はこのアプリのサーバーを通らない。
final class RealtimeSocket {
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

    func connect(instructions: String) async throws {
        var components = URLComponents(string: "wss://api.openai.com/v1/realtime")!
        components.queryItems = [URLQueryItem(name: "model", value: model)]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
        let update: [String: Any] = [
            "type": "session.update",
            "session": [
                "type": "realtime",
                "instructions": instructions,
                "audio": [
                    "input": [
                        "format": ["type": "audio/pcm", "rate": 24000],
                        "turn_detection": [
                            "type": "semantic_vad",
                            "eagerness": "low",
                            "create_response": true,
                            "interrupt_response": true,
                        ],
                    ],
                    "output": [
                        "format": ["type": "audio/pcm", "rate": 24000],
                    ],
                ],
            ],
        ]
        try await send(update)
        try await send(["type": "response.create"])
        Task { [weak self] in await self?.receiveLoop() }
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
        case "response.output_audio_transcript.done", "response.audio_transcript.done", "response.done":
            let id = (json["response_id"] as? String) ?? "ai"
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
            return .disconnected
        default:
            return nil
        }
    }
}

final class RealtimeAudio {
    private let engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private var converter: AVAudioConverter?

    func start(onLevel: @escaping (Double) -> Void, onPCM: @escaping (Data) -> Void) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: true) else { return }
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
            if let channel = converted.int16ChannelData {
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
        engine.connect(player, to: engine.mainMixerNode, format: target)
        try engine.start()
        player.play()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func play(_ pcm: Data) {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: true),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(pcm.count / 2))
        else { return }
        buffer.frameLength = buffer.frameCapacity
        pcm.withUnsafeBytes { raw in
            guard let base = raw.baseAddress, let channel = buffer.int16ChannelData else { return }
            memcpy(channel[0], base, pcm.count)
        }
        player.scheduleBuffer(buffer)
    }
}
