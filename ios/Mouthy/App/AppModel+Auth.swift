import Foundation
import MouthyLogic

extension AppModel {
    func restoreSession() {
        guard let raw = Keychain.load(account: Keychain.sessionAccount),
              let data = raw.data(using: .utf8),
              let stored = try? JSONDecoder.mouthy.decode(StoredSession.self, from: data),
              !stored.isExpired
        else {
            Keychain.delete(account: Keychain.sessionAccount)
            sessionToken = nil
            SessionAccess.token = nil
            isSignedIn = false
            return
        }
        sessionToken = stored.token
        SessionAccess.token = stored.token
        isSignedIn = true
        if profile.name.isEmpty, let name = stored.name, !name.isEmpty {
            profile.name = name
        }
    }

    func signIn(provider: LoginMethod, idToken: String, nonce: String?, name: String?) async {
        busy = true
        signInError = nil
        defer { busy = false }
        do {
            let issued = try await APIClient.fromBundle().exchange(provider: provider, idToken: idToken, nonce: nonce, name: name)
            let stored = StoredSession(token: issued.token, expiresAt: issued.expiresAt, provider: provider, name: name ?? issued.name)
            guard let data = try? JSONEncoder.mouthy.encode(stored),
                  let raw = String(data: data, encoding: .utf8),
                  Keychain.save(raw, account: Keychain.sessionAccount)
            else {
                signInError = "サインインを端末に保存できませんでした。もう一度お試しください。"
                return
            }
            sessionToken = issued.token
            SessionAccess.token = issued.token
            isSignedIn = true
            lastLogin.save(provider)
            lastLoginMethod = provider
            if let name, !name.isEmpty { profile.name = name }
            save()
        } catch {
            signInError = (error as? LocalizedError)?.errorDescription ?? "サインインできませんでした。もう一度お試しください。"
        }
    }

    func signInWithGoogle() async {
        signInError = nil
        do {
            let google = try await AccountAuth.signInWithGoogle()
            await signIn(provider: .google, idToken: google.idToken, nonce: nil, name: google.name)
        } catch AccountAuthError.cancelled {
            return
        } catch AccountAuthError.missingGoogleClient {
            signInError = "いまは Google でサインインできません。Apple で続けるか、設定を確認してください。"
        } catch {
            signInError = "サインインできませんでした。もう一度お試しください。"
        }
    }

    func signOut() {
        AccountAuth.signOutGoogle()
        Keychain.delete(account: Keychain.sessionAccount)
        sessionToken = nil
        SessionAccess.token = nil
        isSignedIn = false
        signInError = nil
    }
}
