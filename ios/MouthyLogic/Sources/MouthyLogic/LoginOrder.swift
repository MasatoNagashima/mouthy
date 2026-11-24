import Foundation

public enum LoginMethod: String, CaseIterable, Codable, Equatable, Sendable {
    case apple
    case google
}

/// 最後にログインできた方法。ログアウトでは消さず、アカウント削除のときだけ消す。
public struct LastLoginStore {
    public static let key = "lastLoginMethod"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var method: LoginMethod? {
        defaults.string(forKey: Self.key).flatMap(LoginMethod.init(rawValue:))
    }

    public func save(_ method: LoginMethod) {
        defaults.set(method.rawValue, forKey: Self.key)
    }

    public func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}

public enum LoginButtonOrder {
    /// 前回の方法を上にする。履歴がなければ Apple、Google の順。
    public static func order(last: LoginMethod?) -> [LoginMethod] {
        last == .google ? [.google, .apple] : [.apple, .google]
    }
}

public enum LoginCopy {
    public static let lastLoginLabel = "前回のログイン"
    public static let appleButton = "Apple で続ける"
    public static let googleButton = "Google で続ける"
    public static let signingIn = "サインインしています…"
    public static let failureTitle = "サインインできませんでした"
}
