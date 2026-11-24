import AuthenticationServices
import CryptoKit
import Foundation
import UIKit
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

enum AccountAuthError: Error {
    case unavailable
    case missingGoogleClient
    case missingPresenter
    case missingIdentityToken
    case cancelled
}

enum AccountAuth {
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

    static func googleClientID() -> String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty || trimmed.contains("$(") { return nil }
        return trimmed
    }

    static func signInWithGoogle() async throws -> (idToken: String, name: String?) {
        #if canImport(GoogleSignIn)
        guard let clientID = googleClientID() else { throw AccountAuthError.missingGoogleClient }
        guard let presenter = topViewController() else { throw AccountAuthError.missingPresenter }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        let google: GIDSignInResult
        do {
            google = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        } catch let error as GIDSignInError where error.code == .canceled {
            throw AccountAuthError.cancelled
        }
        guard let idToken = google.user.idToken?.tokenString else { throw AccountAuthError.missingIdentityToken }
        return (idToken, google.user.profile?.name)
        #else
        throw AccountAuthError.unavailable
        #endif
    }

    static func handle(url: URL) -> Bool {
        #if canImport(GoogleSignIn)
        return GIDSignIn.sharedInstance.handle(url)
        #else
        return false
        #endif
    }

    static func signOutGoogle() {
        #if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.signOut()
        #endif
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var controller = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}
