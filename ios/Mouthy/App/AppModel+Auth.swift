import Foundation
import MouthyLogic

extension AppModel {
    func api() -> APIClient {
        var client = APIClient.fromBundle()
        if isSignedIn || authenticating {
            client.tokenProvider = { forceRefresh in
                try await IDTokenSource.shared.token(forceRefresh: forceRefresh)
            }
        }
        return client
    }

    /// Firebase にユーザーが残っていれば、/api/me が返ってからタブを開く。
    func restoreIfNeeded() async {
        guard restoringSession else { return }
        authenticating = true
        defer {
            authenticating = false
            restoringSession = false
        }
        do {
            _ = try await api().me()
            isSignedIn = true
        } catch {
            AccountAuth.signOut()
            isSignedIn = false
        }
    }

    func signInWithApple(idToken: String, nonce: String, fullName: PersonNameComponents?) async {
        await signIn(method: .apple) {
            try await AccountAuth.signInWithApple(idToken: idToken, nonce: nonce, fullName: fullName)
        }
    }

    func signInWithGoogle() async {
        await signIn(method: .google) {
            try await AccountAuth.signInWithGoogle()
        }
    }

    /// /api/me が返ってから isSignedIn = true にする。失敗したら Firebase のログインも消す。
    private func signIn(method: LoginMethod, _ authenticate: () async throws -> (token: String, displayName: String?, isNewUser: Bool)) async {
        busy = true
        signInError = nil
        accountDeletedNotice = false
        defer {
            busy = false
            authenticating = false
        }
        do {
            let session = try await authenticate()
            authenticating = true
            _ = try await api().me()
            isSignedIn = true
            lastLogin.save(method)
            lastLoginMethod = method
            if let name = session.displayName, !name.isEmpty, profile.name.isEmpty {
                profile.name = name
                save()
            }
        } catch let error as AccountAuthError where error == .cancelled {
            return
        } catch {
            if authenticating {
                AccountAuth.signOut()
                isSignedIn = false
            }
            signInError = SignInFailure(error: error)
        }
    }

    func signOut() {
        AccountAuth.signOut()
        isSignedIn = false
        authenticating = false
        signInError = nil
        deletingAccount = false
    }

    func deleteAccount() async {
        guard !deletingAccount else { return }
        deletingAccount = true
        var appleCode: String?
        let result = await AccountDeletionFlow.run(
            reauthenticate: {
                let session = try await AccountAuth.reauthenticateForDeletion()
                appleCode = session.appleAuthorizationCode
            },
            revokeProvider: {
                try await AccountAuth.revokeAppleForDeletion(appleAuthorizationCode: appleCode)
            },
            deleteOnServer: { try await self.api().deleteMe() },
            finishProvider: { try await AccountAuth.finishDeletion() },
            signOutAndClear: { self.clearAfterDeletion() },
            isCancelled: { ($0 as? AccountAuthError) == .cancelled }
        )
        if case .failed(let error) = result {
            toast = (error as? LocalizedError)?.errorDescription ?? "アカウントを削除できませんでした。"
            deletingAccount = false
        }
    }

    private func clearAfterDeletion() {
        lastLogin.clear()
        lastLoginMethod = nil
        accountDeletedNotice = true
        wipeLocal()
        signOut()
    }
}
