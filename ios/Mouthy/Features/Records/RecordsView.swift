import SwiftUI
import MouthyLogic

struct RecordsView: View {
    @Environment(AppModel.self) private var model
    @State private var path = NavigationPath()
    @State private var filter: RecordFilter = .all

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip("すべて", selected: filter == .all) { filter = .all }
                        filterChip("指摘あり", selected: filter == .hasCorrections) { filter = .hasCorrections }
                        ForEach(SceneCategory.allCases, id: \.self) { category in
                            filterChip(category.chip, selected: filter == .category(category)) { filter = .category(category) }
                        }
                    }
                    .padding(.horizontal, MSpace.l)
                    .padding(.vertical, 8)
                }
                let items = model.filteredSessions(filter: filter)
                if items.isEmpty {
                    VStack(spacing: MSpace.m) {
                        PakuView(expression: .hello, width: 120)
                        Text("最初の会話をすると、ここに添削結果が並びます。")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(MColor.inkSecondary)
                        Button("話す") {
                            model.tab = .home
                            model.briefScene = model.recommendation
                        }
                        .buttonStyle(MouthyButtonStyle())
                    }
                    .padding(MSpace.xl)
                    Spacer()
                } else {
                    List {
                        ForEach(grouped(items), id: \.key) { group in
                            Section(group.title) {
                                ForEach(group.sessions) { session in
                                    NavigationLink(value: ReviewRoute.session(session.id)) {
                                        CorrectionRow(session: session)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .mouthyScreen()
            .navigationTitle("記録")
            .navigationDestination(for: ReviewRoute.self) { route in
                if case .session(let id) = route, let session = model.session(id: id) {
                    FeedbackView(session: session, showsDone: false)
                }
            }
        }
    }

    private func grouped(_ items: [PracticeSession]) -> [(key: String, title: String, sessions: [PracticeSession])] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "M月d日（E）"
        var order: [String] = []
        var map: [String: [PracticeSession]] = [:]
        for session in items {
            let key = StudyCalendar.dayKey(session.startedAt)
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(session)
        }
        return order.map { key in
            let date = map[key]?.first?.startedAt ?? Date()
            let title = StudyCalendar.dayKey(date) == StudyCalendar.dayKey(Date()) ? "今日 · \(formatter.string(from: date))" : formatter.string(from: date)
            return (key, title, map[key] ?? [])
        }
    }

    private func filterChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(.footnote, design: .rounded, weight: .bold))
            .padding(.horizontal, 14)
            .frame(height: 36)
            .foregroundStyle(selected ? MColor.onCoral : MColor.ink)
            .background(selected ? MColor.coral : MColor.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.clear : MColor.line, lineWidth: 1))
    }
}

struct CorrectionRow: View {
    var session: PracticeSession

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(session.sceneTitle).font(.mRounded(.headline))
                    LevelBadge(level: session.level)
                }
                Text("\(clock) · \(max(1, session.durationSec / 60))分")
                    .font(.caption)
                    .foregroundStyle(MColor.inkSecondary)
                Text("指摘 \(session.corrections.count) · 詰まった表現 \(session.stuck.count)")
                    .font(.caption)
                    .foregroundStyle(MColor.inkSecondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("総合点").font(.caption2).foregroundStyle(MColor.inkSecondary)
                Text("\(session.total)").font(.mRounded(.title2)).monospacedDigit().foregroundStyle(MColor.ink)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var clock: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: session.startedAt)
    }
}
