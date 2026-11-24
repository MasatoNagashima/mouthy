import AuthenticationServices
import CryptoKit
import Foundation
import UIKit
#if canImport(FirebaseAuth)
import FirebaseAuth
import FirebaseCore
#endif
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

struct DeletionSession: Equatable {
    var token: String
    var appleAuthorizationCode: String?
}

@MainActor
enum AccountAuth {
    static func signInWithApple(idToken: String, nonce: String, fullName: PersonNameComponents?) async throws -> (token: String, displayName: String?, isNewUser: Bool) {
        #if canImport(FirebaseAuth)
        try prepare()
        let credential = OAuthProvider.appleCredential(withIDToken: idToken, rawNonce: nonce, fullName: fullName)
        let result = try await Auth.auth().signIn(with: credential)
        let token = try await result.user.getIDToken()
        return (token, displayName(from: fullName) ?? result.user.displayName, result.additionalUserInfo?.isNewUser ?? false)
        #else
        throw AccountAuthError.unavailable
        #endif
    }

    static func signInWithGoogle() async throws -> (token: String, displayName: String?, isNewUser: Bool) {
        #if canImport(FirebaseAuth) && canImport(GoogleSignIn)
        try prepare()
        guard let clientID = FirebaseApp.app()?.options.clientID, !clientID.isEmpty else {
            throw AccountAuthError.missingGoogleClient
        }
        guard let presenter = topViewController() else { throw AccountAuthError.missingPresenter }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        let google: GIDSignInResult
        do {
            google = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        } catch let error as GIDSignInError where error.code == .canceled {
            throw AccountAuthError.cancelled
        }
        guard let idToken = google.user.idToken?.tokenString else { throw AccountAuthError.missingIdentityToken }
        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: google.user.accessToken.tokenString)
        let result = try await Auth.auth().signIn(with: credential)
        let token = try await result.user.getIDToken()
        return (token, google.user.profile?.name ?? result.user.displayName, result.additionalUserInfo?.isNewUser ?? false)
        #else
        throw AccountAuthError.unavailable
        #endif
    }

    /// Firebase がキーチェーンに残したユーザーが、起動時の「ログイン済み」の根拠。
    static func hasSignedInUser() -> Bool {
        #if canImport(FirebaseAuth)
        guard (try? prepare()) != nil else { return false }
        return Auth.auth().currentUser != nil
        #else
        return false
        #endif
    }

    static func currentIDToken(forcingRefresh: Bool) async throws -> String {
        #if canImport(FirebaseAuth)
        try prepare()
        guard let user = Auth.auth().currentUser else { throw AccountAuthError.missingAccount }
        do {
            return try await user.getIDToken(forcingRefresh: forcingRefresh)
        } catch {
            if Auth.auth().currentUser == nil { throw AccountAuthError.missingAccount }
            throw error
        }
        #else
        throw AccountAuthError.unavailable
        #endif
    }

    static func signOut() {
        #if canImport(FirebaseAuth)
        try? prepare()
        try? Auth.auth().signOut()
        #endif
        #if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.signOut()
        #endif
    }

    static func reauthenticateForDeletion() async throws -> DeletionSession {
        #if canImport(FirebaseAuth)
        try prepare()
        guard let user = Auth.auth().currentUser else { throw AccountAuthError.missingAccount }
        let providers = Set(user.providerData.map(\.providerID))
        var appleCode: String?
        if providers.contains("apple.com") {
            let nonce = randomNonce()
            let apple = try await AppleSignInCoordinator().credential(nonceHash: sha256(nonce))
            guard let tokenData = apple.identityToken, let idToken = String(data: tokenData, encoding: .utf8) else {
                throw AccountAuthError.missingIdentityToken
            }
            guard let codeData = apple.authorizationCode,
                  let code = String(data: codeData, encoding: .utf8),
                  !code.isEmpty else {
                throw AccountAuthError.missingAuthorizationCode
            }
            let credential = OAuthProvider.appleCredential(withIDToken: idToken, rawNonce: nonce, fullName: apple.fullName)
            do {
                _ = try await user.reauthenticate(with: credential)
            } catch {
                throw map(error)
            }
            appleCode = code
        } else if providers.contains("google.com") {
            #if canImport(GoogleSignIn)
            try await reauthenticateWithGoogle(user)
            #else
            throw AccountAuthError.unavailable
            #endif
        } else {
            throw AccountAuthError.unsupportedProvider
        }
        let token: String
        do {
            token = try await user.getIDToken(forcingRefresh: true)
        } catch {
            throw map(error)
        }
        return DeletionSession(token: token, appleAuthorizationCode: appleCode)
        #else
        throw AccountAuthError.unavailable
        #endif
    }

    static func revokeAppleForDeletion(appleAuthorizationCode: String?) async throws {
        #if canImport(FirebaseAuth)
        guard let appleAuthorizationCode, !appleAuthorizationCode.isEmpty else { return }
        try prepare()
        do {
            try await Auth.auth().revokeToken(withAuthorizationCode: appleAuthorizationCode)
        } catch {
            throw map(error)
        }
        #else
        throw AccountAuthError.unavailable
        #endif
    }

    static func finishDeletion() async throws {
        #if canImport(FirebaseAuth)
        try prepare()
        guard let user = Auth.auth().currentUser else { throw AccountAuthError.missingAccount }
        do {
            try await user.delete()
        } catch {
            throw map(error)
        }
        #else
        throw AccountAuthError.unavailable
        #endif
    }

    static func randomNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func handle(url: URL) -> Bool {
        #if canImport(GoogleSignIn)
        return GIDSignIn.sharedInstance.handle(url)
        #else
        return false
        #endif
    }

    private static func displayName(from components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let formatted = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return formatted.isEmpty ? nil : formatted
    }

    #if canImport(FirebaseAuth) && canImport(GoogleSignIn)
    private static func reauthenticateWithGoogle(_ user: FirebaseAuth.User) async throws {
        guard let clientID = FirebaseApp.app()?.options.clientID, !clientID.isEmpty else {
            throw AccountAuthError.missingGoogleClient
        }
        guard let presenter = topViewController() else { throw AccountAuthError.missingPresenter }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        let google: GIDSignInResult
        do {
            google = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        } catch let error as GIDSignInError where error.code == .canceled {
            throw AccountAuthError.cancelled
        }
        guard let idToken = google.user.idToken?.tokenString else { throw AccountAuthError.missingIdentityToken }
        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: google.user.accessToken.tokenString)
        do {
            _ = try await user.reauthenticate(with: credential)
        } catch {
            throw map(error)
        }
    }
    #endif

    #if canImport(FirebaseAuth)
    private static func map(_ error: Error) -> Error {
        let ns = error as NSError
        guard ns.domain == AuthErrorDomain else { return error }
        switch AuthErrorCode(rawValue: ns.code) {
        case .userMismatch:
            return AccountAuthError.wrongAccount
        case .requiresRecentLogin:
            return AccountAuthError.needsRecentLogin
        default:
            return error
        }
    }

    private static func prepare() throws {
        if FirebaseApp.app() != nil { return }
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            throw AccountAuthError.unavailable
        }
        FirebaseApp.configure()
    }
    #endif

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var controller = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}

/// 期限切れの ID トークンを、同時の 401 では 1 回だけ取り直す。
actor IDTokenSource {
    static let shared = IDTokenSource()

    private var refreshing: Task<String, Error>?

    func token(forceRefresh: Bool) async throws -> String {
        guard forceRefresh else {
            return try await AccountAuth.currentIDToken(forcingRefresh: false)
        }
        if let refreshing {
            return try await refreshing.value
        }
        let task = Task { try await AccountAuth.currentIDToken(forcingRefresh: true) }
        refreshing = task
        defer { refreshing = nil }
        return try await task.value
    }
}

private final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?
    private var controller: ASAuthorizationController?
    private var anchor: ASPresentationAnchor?
    private var keepAlive: AppleSignInCoordinator?

    func credential(nonceHash: String) async throws -> ASAuthorizationAppleIDCredential {
        try await withCheckedThrowingContinuation { continuation in
            guard let anchor = Self.keyWindow() else {
                continuation.resume(throwing: AccountAuthError.missingPresenter)
                return
            }
            self.keepAlive = self
            self.continuation = continuation
            self.anchor = anchor
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = nonceHash
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            finish(throwing: AccountAuthError.missingIdentityToken)
            return
        }
        finish(returning: credential)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if let auth = error as? ASAuthorizationError, auth.code == .canceled {
            finish(throwing: AccountAuthError.cancelled)
            return
        }
        finish(throwing: error)
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        if let anchor { return anchor }
        if let window = Self.keyWindow() { return window }
        preconditionFailure("Sign in with Apple started without a window")
    }

    private static func keyWindow() -> UIWindow? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first
    }

    private func finish(returning credential: ASAuthorizationAppleIDCredential) {
        let continuation = self.continuation
        self.continuation = nil
        self.controller = nil
        continuation?.resume(returning: credential)
        keepAlive = nil
    }

    private func finish(throwing error: Error) {
        let continuation = self.continuation
        self.continuation = nil
        self.controller = nil
        continuation?.resume(throwing: error)
        keepAlive = nil
    }
}
