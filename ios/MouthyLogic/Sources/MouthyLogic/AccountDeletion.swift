import Foundation

/// アカウント削除の結果。サーバーの削除が通ったあとだけ `deleted`。
public enum AccountDeletionResult {
    case deleted
    case cancelled
    /// サーバーの削除より前の失敗。端末の記録は残す。
    case failed(Error)

    public var isDeleted: Bool {
        if case .deleted = self { return true }
        return false
    }
}

/// 本人確認 → Apple の取り消し → サーバーの削除 → Firebase のユーザー削除 → 端末の片づけ。
/// 取り消しが失敗しても削除は続ける。サーバーの削除が通ったあとは、Firebase 側の片づけが失敗してもログアウトする。
public enum AccountDeletionFlow {
    public static func run(
        reauthenticate: () async throws -> Void,
        revokeProvider: () async throws -> Void = {},
        deleteOnServer: () async throws -> Void,
        finishProvider: () async throws -> Void,
        signOutAndClear: () -> Void,
        isCancelled: (Error) -> Bool
    ) async -> AccountDeletionResult {
        do {
            try await reauthenticate()
        } catch {
            return isCancelled(error) ? .cancelled : .failed(error)
        }
        do {
            try await revokeProvider()
        } catch {
            // Apple の取り消しに失敗しても、削除自体は止めない。
        }
        do {
            try await deleteOnServer()
        } catch {
            return isCancelled(error) ? .cancelled : .failed(error)
        }
        do {
            try await finishProvider()
        } catch {
            // サーバーが先にユーザーを消していると、ここは失敗する。ログイン画面には戻す。
        }
        signOutAndClear()
        return .deleted
    }
}
