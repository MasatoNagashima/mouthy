import AuthenticationServices
import UIKit
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
                VStack(spacing: 0) {
                    hero
                    VStack(spacing: MSpace.m) {
                        Text("TOEIC600でも、\n英語はしゃべれる。")
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .lineSpacing(4)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(MColor.ink)
                            .accessibilityAddTraits(.isHeader)
                        Text("完璧じゃなくていい。\nパクと話して、まず口をひらこう。")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(MColor.inkSecondary)
                    }
                    .padding(.top, MSpace.xl)
                    .padding(.horizontal, MSpace.xl)
                    VStack(spacing: MSpace.m) {
                        if model.accountDeletedNotice, !model.busy {
                            notice(title: "アカウントを削除しました", body: "ご利用ありがとうございました。")
                        }
                        if let failure = model.signInError, !model.busy {
                            notice(title: SignInFailure.title, body: failure.message, isError: true)
                        }
                    }
                    .padding(.horizontal, MSpace.xl)
                    .padding(.top, MSpace.l)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            // Let the coral dome behind Paku reach up under the status bar.
            .scrollClipDisabled()
            actions
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

    private var hasLastLogin: Bool { model.lastLoginMethod != nil }

    /// パクのあいさつ。初回は「Hi! ぼくはパク。」、前回のログインがあれば「おかえり！ またはなそう。」。
    private var hero: some View {
        VStack(spacing: 8) {
            Text(hasLastLogin ? "おかえり！ またはなそう。" : "Hi! ぼくはパク。")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(MColor.coralInk)
            PakuView(expression: .hello, width: hasLastLogin ? 204 : 222)
        }
        .padding(.top, hasLastLogin ? 24 : 36)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .background(alignment: .bottom) {
            // The coral-tint dome behind Paku. It reaches up under the status bar.
            Ellipse()
                .fill(MColor.tintCoral)
                .frame(width: 760, height: 1000)
                .offset(y: -12)
                .accessibilityHidden(true)
        }
    }

    private var actions: some View {
        VStack(spacing: 0) {
            if model.busy {
                HStack(spacing: 10) {
                    ProgressView().tint(MColor.coralInk)
                    Text(LoginCopy.signingIn)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MColor.ink)
                }
                .frame(maxWidth: .infinity)
                .frame(height: LoginStyle.buttonHeight)
                .background(MColor.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(MColor.line, lineWidth: 1))
            } else {
                VStack(spacing: LoginStyle.buttonGap) {
                    ForEach(LoginButtonOrder.order(last: model.lastLoginMethod), id: \.self) { method in
                        loginButton(method)
                    }
                }
            }
            VStack(spacing: 6) {
                Text(consentText)
                    .font(.system(size: 12))
                    .lineSpacing(3)
                    .foregroundStyle(MColor.inkSecondary)
                    .tint(MColor.coralInk)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .environment(\.openURL, OpenURLAction { url in
                        guard url == Self.policyURL else { return .systemAction }
                        showPolicy = true
                        return .handled
                    })
                    .accessibilityAction(named: "プライバシーポリシー") { showPolicy = true }
            }
            .padding(.top, LoginStyle.legalTop)
        }
        .dynamicTypeSize(.xSmall ... .xxxLarge)
        .padding(.horizontal, LoginStyle.sideInset)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    /// In-app link that opens the privacy policy sheet (there is no public policy page yet).
    private static let policyURL = URL(string: "mouthy-app://privacy")!

    private var consentText: AttributedString {
        var link = AttributedString("プライバシーポリシー")
        link.link = Self.policyURL
        link[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = MColor.coralInk
        link[AttributeScopes.SwiftUIAttributes.FontAttribute.self] = .system(size: 12, weight: .bold)
        link[AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute.self] = .single
        var text = AttributedString("続けると、")
        text += link
        text += AttributedString("と、音声を会話中だけ OpenAI に送り録音を保存しないことに\n同意したものとみなされます")
        return text
    }

    /// 前回ログインした方法のボタンは、上に「前回のログイン」のピルを置き、外側にリングを回す (Shadowly と同じ形)。
    /// ボタン本体 (大きさ・配色・文字) は Apple / Google のガイドラインのまま。
    @ViewBuilder
    private func loginButton(_ method: LoginMethod) -> some View {
        let isLast = method == model.lastLoginMethod
        VStack(spacing: LoginStyle.lastLoginPillGap) {
            if isLast {
                Label(LoginCopy.lastLoginLabel, systemImage: "clock.arrow.circlepath")
                    .labelStyle(LastLoginPillLabelStyle())
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(MColor.onCoral)
                    .padding(.horizontal, 12)
                    .frame(height: LoginStyle.lastLoginPillHeight)
                    .background(MColor.coral, in: Capsule())
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
                        .strokeBorder(MColor.coralInk, lineWidth: LoginStyle.lastLoginRing)
                        .padding(-(LoginStyle.lastLoginRingGap + LoginStyle.lastLoginRing))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityHint(isLast ? LoginCopy.lastLoginLabel : "")
        }
    }

    /// Apple の HIG どおり、配色は .black / .white だけを使い、文字は自分で描かない。
    private var appleButton: some View {
        SignInWithAppleButton(.continue, onRequest: configureApple, onCompletion: completeApple)
            .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
            .id(scheme)
            .frame(maxWidth: .infinity)
            .frame(height: LoginStyle.buttonHeight)
            .clipShape(Capsule())
    }

    /// Google ボタン。形と寸法は Shadowly と同じカプセル。ロゴは単色の G (多色のロゴは使わない)。
    private var googleButton: some View {
        Button {
            Task { await model.signInWithGoogle() }
        } label: {
            HStack(spacing: 10) {
                GoogleMonoMark()
                    .fill(GoogleBrand.text)
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                Text(LoginCopy.googleButton)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .frame(height: LoginStyle.buttonHeight)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(GoogleBrand.text)
        .background(GoogleBrand.fill, in: Capsule())
        .overlay(Capsule().strokeBorder(GoogleBrand.stroke, lineWidth: 1))
    }

    private func notice(title: String, body: String, isError: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? MColor.danger : MColor.success)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(MColor.ink)
                Text(body).font(.footnote).foregroundStyle(MColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(MSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(MColor.line))
        .accessibilityElement(children: .combine)
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

/// ログイン画面の寸法 (Shadowly の DS.Auth と同じ値)。
private enum LoginStyle {
    static let buttonHeight: CGFloat = 54
    static let buttonGap: CGFloat = 12
    static let lastLoginPillHeight: CGFloat = 24
    static let lastLoginPillGap: CGFloat = 10
    static let lastLoginRing: CGFloat = 2.5
    static let lastLoginRingGap: CGFloat = 3
    static let sideInset: CGFloat = 24
    static let legalTop: CGFloat = 14
}

/// Google ボタンの配色 (Designer の v0.7 login v2 仕様 4.1)。多色・青のロゴは使わず、G は文字と同じ単色。
private enum GoogleBrand {
    static let fill = Color(light: 0xFFFFFF, dark: 0x261B18)
    static let stroke = Color(light: 0x7E5E55, dark: 0xA88E84)
    static let text = Color(light: 0x4A1416, dark: 0xFFFFFF)
}

private struct LastLoginPillLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 13, weight: .bold))
            configuration.title
        }
    }
}

private extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

/// The Google "G" silhouette (standard 48×48 mark), drawn in a single color.
private struct GoogleMonoMark: Shape {
    private static let d = "M43.611,20.083H42V20H24v8h11.303c-1.649,4.657-6.08,8-11.303,8c-6.627,0-12-5.373-12-12c0-6.627,5.373-12,12-12c3.059,0,5.842,1.154,7.961,3.039l5.657-5.657C34.046,6.053,29.268,4,24,4C12.955,4,4,12.955,4,24c0,11.045,8.955,20,20,20c11.045,0,20-8.955,20-20C44,22.659,43.862,21.35,43.611,20.083z"

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 48
        return SVGPathParser.path(Self.d)
            .applying(CGAffineTransform(scaleX: scale, y: scale))
            .offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// Minimal SVG path parser (M/H/V/h/v/l/C/c/Z), the same one Shadowly uses for its Google mark.
private enum SVGPathParser {
    static func path(_ d: String) -> Path {
        let tokens = tokenize(d)
        var path = Path()
        var index = 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var start = CGPoint.zero

        func number() -> CGFloat {
            defer { index += 1 }
            guard index < tokens.count else { return 0 }
            return CGFloat(Double(tokens[index]) ?? 0)
        }

        while index < tokens.count {
            let command = tokens[index]
            index += 1
            switch command {
            case "M":
                x = number(); y = number()
                path.move(to: CGPoint(x: x, y: y))
                start = CGPoint(x: x, y: y)
            case "H":
                x = number()
                path.addLine(to: CGPoint(x: x, y: y))
            case "V":
                y = number()
                path.addLine(to: CGPoint(x: x, y: y))
            case "h":
                x += number()
                path.addLine(to: CGPoint(x: x, y: y))
            case "v":
                y += number()
                path.addLine(to: CGPoint(x: x, y: y))
            case "l":
                x += number(); y += number()
                path.addLine(to: CGPoint(x: x, y: y))
            case "C":
                let x1 = number(), y1 = number(), x2 = number(), y2 = number()
                let endX = number(), endY = number()
                path.addCurve(to: CGPoint(x: endX, y: endY), control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
                x = endX; y = endY
            case "c":
                let ox = x, oy = y
                let x1 = ox + number(), y1 = oy + number()
                let x2 = ox + number(), y2 = oy + number()
                x = ox + number(); y = oy + number()
                path.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
            case "Z", "z":
                path.closeSubpath()
                x = start.x; y = start.y
            default:
                break
            }
        }
        return path
    }

    private static func tokenize(_ d: String) -> [String] {
        var tokens: [String] = []
        let chars = Array(d)
        var index = 0
        func digit(_ c: Character) -> Bool { c >= "0" && c <= "9" }
        while index < chars.count {
            let c = chars[index]
            if c == " " || c == "," { index += 1; continue }
            if "MmLlHhVvCcZz".contains(c) {
                tokens.append(String(c))
                index += 1
                continue
            }
            let start = index
            if c == "-" || c == "+" { index += 1 }
            while index < chars.count && digit(chars[index]) { index += 1 }
            if index < chars.count && chars[index] == "." {
                index += 1
                while index < chars.count && digit(chars[index]) { index += 1 }
            }
            if index > start {
                tokens.append(String(chars[start..<index]))
            } else {
                index += 1
            }
        }
        return tokens
    }
}
