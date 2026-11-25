import AVFoundation
import Foundation
import WebRTC

enum RealtimeEvent {
    case aiDelta(id: String, text: String, at: Int)
    case aiDone(id: String)
    case aiAudioStarted
    case aiAudioStopped
    case learnerStarted(id: String, at: Int)
    case learnerPartial(id: String, text: String)
    case learnerFinal(id: String, text: String, at: Int)
    case learnerStopped(id: String, at: Int)
    case failure(String)
    case disconnected
}

/// WebRTC 接続の状態（STG の検証用に画面へ出す）。
struct RealtimeStatus {
    var connection = "未接続"
    var ice = "-"
    var dataChannel = "閉"
    var micEnabled = false
    var remoteAudio = false
    var output = ""
    var lastError: String?

    var line: String {
        var parts = [
            "接続 \(connection)",
            "ICE \(ice)",
            "データ \(dataChannel)",
            micEnabled ? "マイク オン" : "マイク オフ",
            remoteAudio ? "AI音声トラック あり" : "AI音声トラック なし",
            "出力 \(output.isEmpty ? "-" : output)",
        ]
        if let lastError { parts.append("エラー: \(lastError)") }
        return parts.joined(separator: " / ")
    }
}

enum RealtimeError: LocalizedError {
    case setup(String)
    case answer(Int, String)

    var errorDescription: String? {
        switch self {
        case .setup(let message): return message
        case .answer(let code, let body): return "音声サーバーが接続を受け付けませんでした（\(code)）\(body)"
        }
    }
}

/// OpenAI Realtime に WebRTC でつなぐ。マイクの取り込み・AI の声の再生・エコー除去・
/// 揺らぎの吸収は WebRTC が行い、AI の声は受信した音声トラックがそのまま鳴る。
/// 文字起こしなどのイベントはデータチャネル「oai-events」で受け取る。
/// 使うのはサーバーが発行した短命トークンだけで、APIキーはアプリに持たない。
/// セッションの設定（指示文・声・文字起こし・ノイズ除去・ターン検出）はサーバーが
/// トークン発行時に入れているので、ここでは上書きしない。
///
/// WebRTC のデリゲートは別スレッドから呼ばれるので、状態とイベントの列は lock で守る。
final class RealtimeRTC: NSObject, RTCPeerConnectionDelegate, RTCDataChannelDelegate, @unchecked Sendable {
    private static let factory: RTCPeerConnectionFactory = {
        _ = RTCInitializeSSL()
        return RTCPeerConnectionFactory()
    }()

    private let token: String
    private let started = Date()
    private let lock = NSLock()
    private var peer: RTCPeerConnection?
    private var channel: RTCDataChannel?
    private var micTrack: RTCAudioTrack?
    private var events: [RealtimeEvent] = []
    private var waiter: CheckedContinuation<RealtimeEvent?, Never>?
    private var closed = false
    private var greeted = false
    private var state = RealtimeStatus()

    init(token: String) {
        self.token = token
        super.init()
    }

    /// 音声セッションを会話向け（スピーカーから出す・エコー除去）にして、接続する。
    @MainActor
    func connect() async throws {
        try Self.configureAudioSession()

        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let peer = Self.factory.peerConnection(with: config, constraints: constraints, delegate: self) else {
            throw RealtimeError.setup("音声の接続を作れませんでした。")
        }
        let source = Self.factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
        let track = Self.factory.audioTrack(with: source, trackId: "mouthy-mic")
        track.isEnabled = true
        _ = peer.add(track, streamIds: ["mouthy"])
        let dataConfig = RTCDataChannelConfiguration()
        dataConfig.isOrdered = true
        let channel = peer.dataChannel(forLabel: "oai-events", configuration: dataConfig)
        channel?.delegate = self
        lock.lock()
        self.peer = peer
        self.channel = channel
        self.micTrack = track
        state.micEnabled = true
        state.connection = "接続中"
        lock.unlock()

        let offerConstraints = RTCMediaConstraints(
            mandatoryConstraints: ["OfferToReceiveAudio": "true", "OfferToReceiveVideo": "false"],
            optionalConstraints: nil
        )
        let offer: RTCSessionDescription = try await withCheckedThrowingContinuation { continuation in
            peer.offer(for: offerConstraints) { sdp, error in
                if let sdp {
                    continuation.resume(returning: sdp)
                } else {
                    continuation.resume(throwing: error ?? RealtimeError.setup("接続の準備（offer）に失敗しました。"))
                }
            }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peer.setLocalDescription(offer) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        // 候補（ICE）を少し集めてから送る。集まりきらなくても 1.5 秒で先に進む。
        for _ in 0..<15 where peer.iceGatheringState != .complete {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        let localSDP = peer.localDescription?.sdp ?? offer.sdp

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/realtime/calls")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/sdp", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(localSDP.utf8)
        request.timeoutInterval = 20
        let (body, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(data: body, encoding: .utf8) ?? ""
        guard (200..<300).contains(code), text.hasPrefix("v=") else {
            throw RealtimeError.answer(code, Self.errorMessage(from: text))
        }
        let answer = RTCSessionDescription(type: .answer, sdp: text)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peer.setRemoteDescription(answer) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        // データチャネルがすでに開いていたら、ここで最初のあいさつを頼む。
        greetIfReady()
    }

    /// 一時停止中はマイクを止める（相手に音を送らない）。
    func setMicEnabled(_ enabled: Bool) {
        lock.lock()
        micTrack?.isEnabled = enabled
        state.micEnabled = enabled
        lock.unlock()
    }

    func nextEvent() async -> RealtimeEvent? {
        await withCheckedContinuation { continuation in
            lock.lock()
            if !events.isEmpty {
                let event = events.removeFirst()
                lock.unlock()
                continuation.resume(returning: event)
            } else if closed {
                lock.unlock()
                continuation.resume(returning: nil)
            } else {
                // 待つのは1か所（TalkSession の受信ループ）だけ。
                let previous = waiter
                waiter = continuation
                lock.unlock()
                previous?.resume(returning: nil)
            }
        }
    }

    /// 何度呼んでもよい。
    func close() {
        lock.lock()
        if closed {
            lock.unlock()
            return
        }
        closed = true
        let peer = self.peer
        let channel = self.channel
        let waiter = self.waiter
        self.waiter = nil
        self.peer = nil
        self.channel = nil
        micTrack?.isEnabled = false
        micTrack = nil
        state.connection = "終了"
        lock.unlock()
        channel?.delegate = nil
        channel?.close()
        peer?.delegate = nil
        peer?.close()
        waiter?.resume(returning: nil)
        DispatchQueue.main.async {
            let session = RTCAudioSession.sharedInstance()
            session.lockForConfiguration()
            try? session.setActive(false)
            session.unlockForConfiguration()
        }
    }

    func status() -> RealtimeStatus {
        lock.lock()
        var copy = state
        lock.unlock()
        copy.output = AVAudioSession.sharedInstance().currentRoute.outputs.map { $0.portName }.joined(separator: ",")
        return copy
    }

    // MARK: - 内部

    @MainActor
    private static func configureAudioSession() throws {
        let configuration = RTCAudioSessionConfiguration.webRTC()
        configuration.category = AVAudioSession.Category.playAndRecord.rawValue
        configuration.mode = AVAudioSession.Mode.voiceChat.rawValue
        configuration.categoryOptions = [.defaultToSpeaker, .allowBluetooth]
        // WebRTC が自分で音声セッションを設定し直すときも、スピーカー出力を保つ。
        RTCAudioSessionConfiguration.setWebRTC(configuration)
        let session = RTCAudioSession.sharedInstance()
        session.useManualAudio = false
        session.lockForConfiguration()
        defer { session.unlockForConfiguration() }
        try session.setConfiguration(configuration, active: true)
    }

    private static func errorMessage(from text: String) -> String {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let detail = json["error"] as? [String: Any],
              let message = detail["message"] as? String else { return "" }
        return "：" + String(message.prefix(160))
    }

    private func clock() -> Int { Int(Date().timeIntervalSince(started) * 1000) }

    private func push(_ event: RealtimeEvent) {
        lock.lock()
        if closed {
            lock.unlock()
            return
        }
        if let waiter {
            self.waiter = nil
            lock.unlock()
            waiter.resume(returning: event)
        } else {
            events.append(event)
            lock.unlock()
        }
    }

    private func updateState(_ change: (inout RealtimeStatus) -> Void) {
        lock.lock()
        change(&state)
        lock.unlock()
    }

    private func send(_ object: [String: Any]) {
        lock.lock()
        let channel = self.channel
        lock.unlock()
        guard let channel, channel.readyState == .open,
              let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        _ = channel.sendData(RTCDataBuffer(data: data, isBinary: false))
    }

    /// 最初の一言は AI から（接続が開いたら1回だけ response.create を送る）。
    private func greetIfReady() {
        lock.lock()
        let ready = !greeted && !closed && channel?.readyState == .open
        if ready { greeted = true }
        lock.unlock()
        if ready { send(["type": "response.create"]) }
    }

    private func decode(_ text: String) -> RealtimeEvent? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return nil }
        switch type {
        case "response.output_audio_transcript.delta", "response.audio_transcript.delta":
            let id = (json["response_id"] as? String) ?? (json["item_id"] as? String) ?? "ai"
            let delta = (json["delta"] as? String) ?? ""
            return delta.isEmpty ? nil : .aiDelta(id: id, text: delta, at: clock())
        case "response.output_audio_transcript.done", "response.audio_transcript.done":
            let id = (json["response_id"] as? String) ?? "ai"
            return .aiDone(id: id)
        case "response.done":
            let response = json["response"] as? [String: Any]
            let id = (response?["id"] as? String) ?? "ai"
            return .aiDone(id: id)
        case "output_audio_buffer.started":
            return .aiAudioStarted
        case "output_audio_buffer.stopped", "output_audio_buffer.cleared":
            return .aiAudioStopped
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
            let message = (detail?["message"] as? String) ?? "音声サーバーでエラーが起きました。"
            updateState { $0.lastError = String(message.prefix(80)) }
            return .failure(message)
        default:
            return nil
        }
    }

    // MARK: - RTCPeerConnectionDelegate（別スレッドから呼ばれる）

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        if !stream.audioTracks.isEmpty { updateState { $0.remoteAudio = true } }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        let label: String
        switch newState {
        case .new: label = "new"
        case .checking: label = "checking"
        case .connected: label = "connected"
        case .completed: label = "completed"
        case .failed: label = "failed"
        case .disconnected: label = "disconnected"
        case .closed: label = "closed"
        case .count: label = "-"
        @unknown default: label = "?"
        }
        updateState { $0.ice = label }
        if newState == .failed {
            updateState { $0.lastError = "ICE 接続に失敗" }
            push(.disconnected)
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        let label: String
        switch newState {
        case .new: label = "new"
        case .connecting: label = "接続中"
        case .connected: label = "接続済み"
        case .disconnected: label = "切断"
        case .failed: label = "失敗"
        case .closed: label = "終了"
        @unknown default: label = "?"
        }
        updateState { $0.connection = label }
        if newState == .failed {
            updateState { $0.lastError = "接続に失敗" }
            push(.disconnected)
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        if rtpReceiver.track?.kind == kRTCMediaStreamTrackKindAudio {
            updateState { $0.remoteAudio = true }
        }
    }

    // MARK: - RTCDataChannelDelegate（別スレッドから呼ばれる）

    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        switch dataChannel.readyState {
        case .open:
            updateState { $0.dataChannel = "開" }
            greetIfReady()
        case .closed:
            updateState { $0.dataChannel = "閉" }
            push(.disconnected)
        default:
            break
        }
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        guard let text = String(data: buffer.data, encoding: .utf8), let event = decode(text) else { return }
        push(event)
    }
}
