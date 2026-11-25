import SwiftUI
import MouthyLogic

struct SceneCatalogView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var category: SceneCategory?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MSpace.l) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chip("すべて", selected: category == nil) { category = nil }
                            ForEach(SceneCategory.allCases, id: \.self) { item in
                                chip(item.chip, selected: category == item) { category = item }
                            }
                        }
                    }
                    let groups = SceneCategory.allCases.filter { category == nil || $0 == category }
                    ForEach(groups, id: \.self) { item in
                        section(item)
                    }
                }
                .padding(MSpace.l)
            }
            .mouthyScreen()
            .navigationTitle("シーン")
            .searchable(text: $query, prompt: "シーンを検索")
        }
    }

    private func section(_ item: SceneCategory) -> some View {
        let scenes = SceneLibrary.all.filter { scene in
            scene.category == item && (query.isEmpty || scene.title.contains(query))
        }
        return VStack(alignment: .leading, spacing: MSpace.m) {
            HStack {
                Text(item.title).font(.mRounded(.title3, weight: .heavy))
                Spacer()
                Text("\(SceneLibrary.releasedCount(in: item)) / 10")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(MColor.inkSecondary)
            }
            let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(scenes) { scene in
                    Button { open(scene) } label: { SceneCard(scene: scene, best: model.bestScore(sceneId: scene.id)) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func open(_ scene: SceneDef) {
        guard scene.released else {
            model.toast = SceneLibrary.comingSoonMessage
            return
        }
        model.briefMinutes = 5
        model.briefScene = scene
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(.footnote, design: .rounded, weight: .bold))
            .padding(.horizontal, 14)
            .frame(height: 36)
            .foregroundStyle(selected ? MColor.onCoral : MColor.ink)
            .background(selected ? MColor.coral : MColor.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.clear : MColor.line, lineWidth: 1))
    }
}

struct SceneCard: View {
    var scene: SceneDef
    var best: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: scene.category.symbol)
                    .foregroundStyle(scene.released ? MColor.coralInk : MColor.inkTertiary)
                    .frame(width: 32, height: 32)
                    .background(scene.released ? MColor.tintCoral : MColor.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Spacer()
                if scene.released, best != nil {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(MColor.success)
                }
            }
            Text(scene.title).font(.mRounded(.headline)).foregroundStyle(MColor.ink).multilineTextAlignment(.leading)
            LevelBadge(level: scene.level, comingSoon: !scene.released)
            if let best, scene.released {
                Text("最高 \(best)").font(.system(.caption, design: .rounded, weight: .semibold)).monospacedDigit().foregroundStyle(MColor.inkSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(scene.released ? MColor.surface : MColor.fill.opacity(0.4), in: RoundedRectangle(cornerRadius: MRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: MRadius.card)
                .stroke(scene.released ? MColor.line : MColor.inkTertiary, style: StrokeStyle(lineWidth: 1, dash: scene.released ? [] : [4, 4]))
        }
    }
}

struct SceneBriefSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var scene: SceneDef

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MSpace.l) {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: scene.category.symbol)
                            .font(.title2)
                            .foregroundStyle(MColor.coralInk)
                            .frame(width: 56, height: 56)
                            .background(MColor.tintCoral, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(scene.category.title) · パクが\(scene.roleJa)役")
                                .font(.footnote)
                                .foregroundStyle(MColor.inkSecondary)
                            Text(scene.title).font(.system(.title2, design: .rounded, weight: .heavy))
                        }
                    }
                    HStack(spacing: 6) {
                        LevelBadge(level: scene.level)
                        Text(scene.cefrLabel)
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .foregroundStyle(MColor.inkSecondary)
                            .background(MColor.fill, in: Capsule())
                    }
                    if let best = model.bestScore(sceneId: scene.id) {
                        Text("前回の総合点 \(best)").font(.footnote).foregroundStyle(MColor.inkSecondary)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Label("今日のゴール", systemImage: "target")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(MColor.coralInk)
                        Text(scene.goalJa).foregroundStyle(MColor.ink)
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(scene.checkpoints.enumerated()), id: \.offset) { index, checkpoint in
                                HStack {
                                    Text("\(index + 1)")
                                        .font(.system(.caption, design: .rounded, weight: .heavy))
                                        .foregroundStyle(MColor.coralInk)
                                        .frame(width: 24, height: 24)
                                        .background(MColor.tintCoral, in: Circle())
                                    Text(checkpoint.titleJa).font(.subheadline).foregroundStyle(MColor.inkSecondary)
                                }
                            }
                        }
                    }
                    .padding(MSpace.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MColor.surface, in: RoundedRectangle(cornerRadius: MRadius.card, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: MRadius.card, style: .continuous).stroke(MColor.line))
                    Text("使える表現").font(.mRounded(.headline))
                    VStack(spacing: 0) {
                        ForEach(Array(scene.phrases.enumerated()), id: \.offset) { index, phrase in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(phrase.en).font(.body.weight(.semibold)).foregroundStyle(MColor.ink)
                                Text(phrase.ja).font(.caption).foregroundStyle(MColor.inkSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, MSpace.l)
                            .padding(.vertical, MSpace.m)
                            if index < scene.phrases.count - 1 {
                                Divider().overlay(MColor.line)
                            }
                        }
                    }
                    .background(MColor.surface, in: RoundedRectangle(cornerRadius: MRadius.card, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: MRadius.card, style: .continuous).stroke(MColor.line))
                    HStack {
                        Text("会話の長さ").font(.mRounded(.headline))
                        Spacer()
                        HStack(spacing: 2) {
                            ForEach([3, 5, 10], id: \.self) { minutes in
                                let isOn = model.briefMinutes == minutes
                                Button("\(minutes)分") { model.briefMinutes = minutes }
                                    .font(.system(.footnote, design: .rounded, weight: .bold))
                                    .frame(width: 64, height: 34)
                                    .foregroundStyle(MColor.ink)
                                    .background(isOn ? MColor.surface : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .accessibilityAddTraits(isOn ? .isSelected : [])
                            }
                        }
                        .padding(3)
                        .background(MColor.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    Button {
                        let minutes = model.briefMinutes
                        dismiss()
                        model.talk = TalkLaunch(scene: scene, minutes: minutes, diagnostic: false)
                    } label: {
                        Label("会話をはじめる", systemImage: "mic.fill")
                    }
                    .buttonStyle(MouthyButtonStyle())
                }
                .padding(MSpace.l)
            }
            .mouthyScreen()
            .navigationTitle("事前ブリーフ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
        }
    }
}
