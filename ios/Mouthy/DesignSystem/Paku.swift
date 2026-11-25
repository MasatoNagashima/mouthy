import SwiftUI

/// パク (R1 コーラル, soft bumps). Vector PDFs generated from the designer's paku.mjs.
enum PakuExpression: String, CaseIterable {
    /// 話す
    case talk
    /// 聞く
    case listen
    /// ほめる
    case cheer
    /// 考え中 (電球つき)
    case think
    /// あいさつ
    case hello

    var assetName: String { "paku.\(rawValue)" }

    /// Width / height of the artwork (viewBox of each PDF).
    var aspectRatio: CGFloat {
        switch self {
        case .think: return 620.0 / 652.0
        case .cheer: return 660.0 / 562.0
        default: return 600.0 / 552.0
        }
    }
}

struct PakuView: View {
    var expression: PakuExpression
    var width: CGFloat
    /// 0...1 voice level; makes Paku bob gently while talking.
    var level: Double = 0
    var animated = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animated || reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let moving = animated && !reduceMotion
            let amount = moving ? max(level, 0.35) : 0
            let bob = moving ? CGFloat(abs(sin(t * 5.5)) * 0.045 * amount) : 0
            Image(expression.assetName)
                .resizable()
                .interpolation(.high)
                .aspectRatio(expression.aspectRatio, contentMode: .fit)
                .frame(width: width)
                .scaleEffect(x: 1 - bob * 0.3, y: 1 + bob, anchor: .bottom)
        }
        .accessibilityHidden(true)
    }
}

/// Paku on a soft coral disc, as used in the talk header and the mic consent screen.
struct PakuBadge: View {
    var expression: PakuExpression
    var size: CGFloat
    var level: Double = 0
    var animated = false

    var body: some View {
        ZStack {
            Circle().fill(MColor.tintCoral)
            PakuView(expression: expression, width: size * 0.78, level: level, animated: animated)
        }
        .frame(width: size, height: size)
    }
}
