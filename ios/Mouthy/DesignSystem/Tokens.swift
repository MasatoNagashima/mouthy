import SwiftUI

enum MColor {
    static let green = Color("brand.green")
    static let apricot = Color("brand.apricot")
    static let apricotInk = Color("brand.apricotInk")
    static let amber = Color("hint.amber")
    static let fluency = Color("score.fluency")
    static let accuracy = Color("score.accuracy")
    static let danger = Color("status.danger")
    static let bg = Color("bg.base")
    static let surface = Color("bg.surface")
    static let fill = Color("bg.fill")
    static let line = Color("line")
    static let ink = Color("ink.primary")
    static let inkSecondary = Color("ink.secondary")
    static let inkTertiary = Color("ink.tertiary")
    static let tintGreen = Color("tint.green")
    static let tintApricot = Color("tint.apricot")
    static let tintAmber = Color("tint.amber")
    static let onGreen = Color("on.green")
}

enum MSpace {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum MRadius {
    static let tail: CGFloat = 6
    static let day: CGFloat = 10
    static let list: CGFloat = 14
    static let button: CGFloat = 16
    static let card: CGFloat = 20
}

enum ScoreAxis: CaseIterable, Identifiable {
    case communication, fluency, accuracy
    var id: Self { self }
    var weight: Double {
        switch self {
        case .communication: return 0.50
        case .fluency: return 0.35
        case .accuracy: return 0.15
        }
    }
    var title: String {
        switch self {
        case .communication: return "意思疎通"
        case .fluency: return "流暢さ"
        case .accuracy: return "正確さ"
        }
    }
    var color: Color {
        switch self {
        case .communication: return MColor.green
        case .fluency: return MColor.fluency
        case .accuracy: return MColor.accuracy
        }
    }
}

extension Font {
    static func mTotalScore(size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded).monospacedDigit()
    }
}

struct MouthyButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost }
    var kind: Kind = .primary
    var isLoading = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .foregroundStyle(foreground)
            .background(background.opacity(configuration.isPressed ? 0.85 : 1))
            .overlay(RoundedRectangle(cornerRadius: MRadius.button).stroke(border, lineWidth: kind == .primary ? 0 : 1))
            .clipShape(RoundedRectangle(cornerRadius: MRadius.button))
            .opacity(isLoading ? 0.7 : 1)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return MColor.onGreen
        case .secondary, .ghost: return MColor.ink
        }
    }

    private var background: Color {
        switch kind {
        case .primary: return MColor.green
        case .secondary: return MColor.surface
        case .ghost: return .clear
        }
    }

    private var border: Color {
        kind == .ghost ? .clear : MColor.line
    }
}

struct LevelBadge: View {
    var level: Int
    var comingSoon = false

    var body: some View {
        Text(comingSoon ? "近日公開" : "Lv\(level)")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(comingSoon ? MColor.inkTertiary : MColor.green)
            .background(comingSoon ? MColor.fill : MColor.tintGreen, in: Capsule())
    }
}

struct ScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(MColor.bg.ignoresSafeArea())
    }
}

extension View {
    func mouthyScreen() -> some View { modifier(ScreenBackground()) }
}
