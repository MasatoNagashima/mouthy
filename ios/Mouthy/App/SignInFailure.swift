import Foundation

/// ログイン画面のエラーカード。開発者向けの説明は出さない。
struct SignInFailure: Identifiable {
    enum Reason: Equatable {
        case network
        case unavailable
        case verification
        case server
        case other
    }

    let id = UUID()
    var reason: Reason

    init(reason: Reason) {
        self.reason = reason
    }

    init(error: Error) {
        self.init(reason: Self.reason(for: error))
    }

    static let title = "サインインできませんでした"

    var message: String {
        switch reason {
        case .network: "通信が不安定なようです。電波のよい場所で、もう一度お試しください。"
        case .unavailable: "いまはこの方法でサインインできません。もう一方の方法をお試しください。"
        case .verification: "サインインの確認を受け取れませんでした。もう一度お試しください。"
        case .server: "サーバーにつながりませんでした。少し待ってから、もう一度お試しください。"
        case .other: "サインインできませんでした。もう一度お試しください。"
        }
    }

    static let firebaseAuthDomain = "FIRAuthErrorDomain"
    static let firebaseNetworkErrorCode = 17020

    static func reason(for error: Error) -> Reason {
        if error is URLError { return .network }
        if let auth = error as? AccountAuthError {
            switch auth {
            case .unavailable, .missingGoogleClient: return .unavailable
            case .missingIdentityToken, .missingAuthorizationCode, .missingPresenter: return .verification
            default: return .other
            }
        }
        if case let APIError.badStatus(status, _) = error {
            return status >= 500 ? .server : .other
        }
        if error is DecodingError { return .server }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain { return .network }
        if ns.domain == firebaseAuthDomain && ns.code == firebaseNetworkErrorCode { return .network }
        return .other
    }
}

enum AccountAuthError: LocalizedError, Equatable {
    case unavailable
    case missingAccount
    case missingGoogleClient
    case missingPresenter
    case cancelled
    case missingIdentityToken
    case missingAuthorizationCode
    case wrongAccount
    case needsRecentLogin
    case unsupportedProvider

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Firebase Auth を初期化できませんでした。GoogleService-Info.plist と FirebaseAuth が必要です。"
        case .missingAccount:
            return "ログイン中のアカウントが見つかりません"
        case .missingGoogleClient:
            return "Google でサインインする設定がまだありません。"
        case .missingPresenter:
            return "サインインの画面を表示できませんでした"
        case .cancelled:
            return "サインインをキャンセルしました"
        case .missingIdentityToken:
            return "サインインの確認を受け取れませんでした"
        case .missingAuthorizationCode:
            return "Apple の確認コードを受け取れませんでした。もう一度お試しください。"
        case .wrongAccount:
            return "サインイン中のアカウントと違うアカウントです"
        case .needsRecentLogin:
            return "もう一度サインインしてから削除してください"
        case .unsupportedProvider:
            return "このログイン方法ではアカウントを削除できません"
        }
    }
}
