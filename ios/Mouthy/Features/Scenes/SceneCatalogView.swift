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
                Text(item.title).font(.title3.bold())
                Spacer()
                Text("\(SceneLibrary.releasedCount(in: item)) / 10")
                    .font(.caption.weight(.semibold))
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
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12)
            .frame(height: 36)
            .foregroundStyle(selected ? MColor.onGreen : MColor.ink)
            .background(selected ? MColor.green : MColor.fill, in: Capsule())
    }
}

struct SceneCard: View {
    var scene: SceneDef
    var best: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: scene.category.symbol)
                    .foregroundStyle(scene.released ? MColor.green : MColor.inkTertiary)
                Spacer()
                if scene.released, best != nil {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(MColor.green)
                }
            }
            Text(scene.title).font(.headline).foregroundStyle(MColor.ink).multilineTextAlignment(.leading)
            LevelBadge(level: scene.level, comingSoon: !scene.released)
            if let best, scene.released {
                Text("最高 \(best)").font(.caption).foregroundStyle(MColor.inkSecondary)
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
                    Text("\(scene.category.title) · AI役：\(scene.roleJa)")
                        .font(.footnote)
                        .foregroundStyle(MColor.inkSecondary)
                    HStack {
                        Text(scene.title).font(.title2.bold())
                        LevelBadge(level: scene.level)
                        Text(scene.cefrLabel).font(.caption).foregroundStyle(MColor.inkSecondary)
                    }
                    if let best = model.bestScore(sceneId: scene.id) {
                        Text("前回の総合点 \(best)").font(.footnote).foregroundStyle(MColor.inkSecondary)
                    }
                    Text("今日のゴール").font(.headline)
                    Text(scene.goalJa)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(scene.checkpoints.enumerated()), id: \.offset) { index, checkpoint in
                            HStack {
                                Text("\(index + 1)").font(.caption.bold()).frame(width: 22, height: 22).background(MColor.fill, in: Circle())
                                Text(checkpoint.titleJa)
                            }
                        }
                    }
                    Text("使える表現").font(.headline)
                    ForEach(Array(scene.phrases.enumerated()), id: \.offset) { _, phrase in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(phrase.en).font(.body)
                            Text(phrase.ja).font(.caption).foregroundStyle(MColor.inkSecondary)
                        }
                    }
                    Text("会話の長さ").font(.headline)
                    HStack {
                        ForEach([3, 5, 10], id: \.self) { minutes in
                            Button("\(minutes)分") { model.briefMinutes = minutes }
                                .font(.footnote.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .foregroundStyle(model.briefMinutes == minutes ? MColor.onGreen : MColor.ink)
                                .background(model.briefMinutes == minutes ? MColor.green : MColor.fill, in: Capsule())
                        }
                    }
                    Button("会話をはじめる") {
                        let minutes = model.briefMinutes
                        dismiss()
                        model.talk = TalkLaunch(scene: scene, minutes: minutes, diagnostic: false)
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
