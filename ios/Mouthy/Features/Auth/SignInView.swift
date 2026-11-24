import AuthenticationServices
import SwiftUI
import MouthyLogic

struct SignInView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @State private var appleNonce = ""
    @State private var showPolicy = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: MSpace.l) {
                    Text("完璧より、\n伝わる英語。")
                        .font(.largeTitle.bold())
                    Text("サインインすると、会話と記録をこのアカウントに残します。")
                        .font(.title3)
                        .foregroundStyle(MColor.inkSecondary)
                    feature("bubble.left.and.bubble.right.fill", "AIが質問でリード", "話題を考えなくていい。答えやすい質問から順に聞きます")
                    feature("hourglass", "詰まっても大丈夫", "黙っても急かしません。3段階のヒントで背中を押します")
                    if model.accountDeletedNotice, !model.busy {
                        Text("アカウントを削除しました")
                            .font(.headline)
                        Text("ご利用ありがとうございました。")
                            .font(.footnote)
                            .foregroundStyle(MColor.inkSecondary)
                    }
                    if let failure = model.signInError, !model.busy {
                        errorCard(failure.message)
                    }
                }
                .padding(MSpace.l)
            }
            VStack(spacing: MSpace.m) {
                if model.busy {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(LoginCopy.signingIn).font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                } else {
                    ForEach(LoginButtonOrder.order(last: model.lastLoginMethod), id: \.self) { method in
                        loginButton(method)
                    }
                }
                Button("プライバシーポリシー") { showPolicy = true }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MColor.inkSecondary)
                Text("続けると、音声を会話中だけ OpenAI に送ることと、録音を保存しないことに同意したものとみなされます。")
                    .font(.caption)
                    .foregroundStyle(MColor.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(MSpace.l)
        }
        .mouthyScreen()
        .onOpenURL { url in
            _ = AccountAuth.handle(url: url)
        }
        .sheet(isPresented: $showPolicy) {
            NavigationStack {
                ScrollView {
                    Text("これは下書きです。サインインに使う Apple または Google の識別子と、このアプリが発行するセッションだけを端末のキーチェーンに残します。会話の音声は応答のために OpenAI に送られ、録音は保存しません。")
                        .font(.body)
                        .padding()
                }
                .navigationTitle("プライバシーポリシー")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { showPolicy = false } } }
            }
        }
    }

    @ViewBuilder
    private func loginButton(_ method: LoginMethod) -> some View {
        let isLast = method == model.lastLoginMethod
        VStack(spacing: 8) {
            if isLast {
                Text(LoginCopy.lastLoginLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MColor.onGreen)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(MColor.green, in: Capsule())
                    .accessibilityHidden(true)
            }
            Group {
                switch method {
                case .apple: appleButton
                case .google: googleButton
                }
            }
            .overlay {
                if isLast {
                    Capsule()
                        .strokeBorder(MColor.green, lineWidth: 3)
                        .padding(-6)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityHint(isLast ? LoginCopy.lastLoginLabel : "")
        }
    }

    private var appleButton: some View {
        SignInWithAppleButton(.continue, onRequest: configureApple, onCompletion: completeApple)
            .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .clipShape(Capsule())
    }

    private var googleButton: some View {
        Button {
            Task { await model.signInWithGoogle() }
        } label: {
            HStack(spacing: 10) {
                Text("G")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
                Text(LoginCopy.googleButton)
                    .font(.body.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.12))
            .background(Color.white, in: Capsule())
            .overlay(Capsule().strokeBorder(Color(red: 0.45, green: 0.47, blue: 0.46), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func feature(_ symbol: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(MColor.green).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(body).font(.footnote).foregroundStyle(MColor.inkSecondary)
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(SignInFailure.title).font(.headline)
            Text(message).font(.footnote).foregroundStyle(MColor.inkSecondary)
        }
        .padding(MSpace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MColor.surface, in: RoundedRectangle(cornerRadius: MRadius.card))
        .overlay(RoundedRectangle(cornerRadius: MRadius.card).stroke(MColor.line))
    }

    private func configureApple(_ request: ASAuthorizationAppleIDRequest) {
        model.signInError = nil
        let nonce = AccountAuth.randomNonce()
        appleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = AccountAuth.sha256(nonce)
    }

    private func completeApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                model.signInError = SignInFailure(reason: .verification)
                return
            }
            let nonce = appleNonce
            let fullName = credential.fullName
            Task { await model.signInWithApple(idToken: idToken, nonce: nonce, fullName: fullName) }
        case .failure(let error):
            if let auth = error as? ASAuthorizationError, auth.code == .canceled { return }
            model.signInError = SignInFailure(error: error)
        }
    }
}
