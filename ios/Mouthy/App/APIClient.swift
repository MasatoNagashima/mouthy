import Foundation

struct PublicConfig: Decodable {
    var voiceReady: Bool
    var model: String?
    var message: String?
}

struct MintedToken: Decodable {
    var token: String
    var model: String
    var expiresAt: String?
}

struct ServerReview: Decodable {
    struct Score: Decodable {
        var formulaVersion: String?
        var total: Int
        var communication: Int
        var fluency: Int
        var accuracy: Int
    }
    struct Correction: Decodable {
        var tag: String
        var original: String
        var better: String
        var reasonJa: String
    }
    var formulaVersion: String
    var score: Score
    var delta: Int?
    var strength: String
    var nextSteps: [String]
    var corrections: [Correction]
    var speakingWpm: Double?
}

enum APIError: LocalizedError {
    case badStatus(Int, String?)
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .badStatus(_, let message):
            return message ?? "サーバーに接続できませんでした。もう一度お試しください。"
        case .notConfigured:
            return "サーバーのURLが設定されていません。"
        }
    }
}

struct ServerAccount: Decodable {
    var uid: String
    var email: String
}

struct APIClient {
    var baseURL: URL
    var clientToken: String
    var session: URLSession = .shared
    /// 付いているとき、有料 API は Firebase の ID トークンを Bearer で送る。401 なら 1 回だけ取り直す。
    var tokenProvider: (@Sendable (_ forceRefresh: Bool) async throws -> String)?

    static func fromBundle() -> APIClient {
        let raw = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String
        let token = (Bundle.main.object(forInfoDictionaryKey: "MouthyClientToken") as? String) ?? ""
        let url = URL(string: raw ?? "") ?? URL(string: "http://127.0.0.1:8787")!
        return APIClient(baseURL: url, clientToken: token.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func me() async throws -> ServerAccount {
        let data = try await send(path: "/api/me", method: "GET", body: nil, authorize: true)
        return try JSONDecoder().decode(ServerAccount.self, from: data)
    }

    func deleteMe() async throws {
        _ = try await send(path: "/api/me", method: "DELETE", body: nil, authorize: true)
    }

    func config() async throws -> PublicConfig {
        let data = try await send(path: "/api/config", method: "GET", body: nil, authorize: false)
        return try JSONDecoder().decode(PublicConfig.self, from: data)
    }

    func mint(scene: SceneDef, settings: AppSettings, phrases: [String]) async throws -> MintedToken {
        let payload: [String: Any] = [
            "scenarioId": scene.category.legacyScenarioId,
            "level": scene.levelId,
            "goal": scene.goalEn,
            "extraInstructions": SceneLibrary.instructionBlock(for: scene, checkpointIndex: 0),
            "reusePhrases": phrases,
            "hintDelayMs": settings.hintDelaySec * 1000,
            "maxHints": 3,
            "vadMode": "semantic_vad",
            "eagerness": "low",
            "silenceDurationMs": 1200,
            "speechSpeed": settings.speechSpeed,
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await send(path: "/api/realtime/session", method: "POST", body: body, authorize: true)
        return try JSONDecoder().decode(MintedToken.self, from: data)
    }

    func review(turns: [StoredTurn], speakingWpm: Double?, reactionMedianMs: Double?, checkpointsDone: Int, checkpointsTotal: Int, previousTotal: Int?) async throws -> ServerReview {
        let turnPayload = turns.map { turn -> [String: Any] in
            ["id": turn.id, "role": turn.speaker == .ai ? "ai" : "learner", "text": turn.text, "finality": "final", "isHint": false]
        }
        var payload: [String: Any] = [
            "mode": speakingWpm == nil ? "mock" : "voice",
            "turns": turnPayload,
            "checkpointsDone": checkpointsDone,
            "checkpointsTotal": checkpointsTotal,
        ]
        if let reactionMedianMs { payload["reactionMedianMs"] = reactionMedianMs }
        if let previousTotal { payload["previousTotal"] = previousTotal }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await send(path: "/api/feedback/review", method: "POST", body: body, authorize: true)
        return try JSONDecoder().decode(ServerReview.self, from: data)
    }

    private func send(path: String, method: String, body: Data?, authorize: Bool) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if authorize, let tokenProvider {
            let first = try await perform(request, idToken: try await idToken(from: tokenProvider, forceRefresh: false))
            if statusCode(of: first.response) == 401 {
                let retry = try await perform(request, idToken: try await idToken(from: tokenProvider, forceRefresh: true))
                return try validated(retry.response, data: retry.data)
            }
            return try validated(first.response, data: first.data)
        }
        if authorize, !clientToken.isEmpty {
            request.setValue(clientToken, forHTTPHeaderField: "X-Mouthy-Client")
        }
        let (data, response) = try await session.data(for: request)
        return try validated(response, data: data)
    }

    private func perform(_ request: URLRequest, idToken: String) async throws -> (data: Data, response: URLResponse) {
        var authorized = request
        authorized.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: authorized)
        return (data, response)
    }

    private func idToken(from provider: @Sendable (Bool) async throws -> String, forceRefresh: Bool) async throws -> String {
        do {
            return try await provider(forceRefresh)
        } catch let error as AccountAuthError where error == .missingAccount {
            throw APIError.badStatus(401, "サインインが必要です。")
        }
    }

    private func statusCode(of response: URLResponse) -> Int {
        (response as? HTTPURLResponse)?.statusCode ?? 0
    }

    private func validated(_ response: URLResponse, data: Data) throws -> Data {
        let status = statusCode(of: response)
        guard (200..<300).contains(status) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            throw APIError.badStatus(status, message)
        }
        return data
    }
}
