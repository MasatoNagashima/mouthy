import Charts
import SwiftUI
import MouthyLogic

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var path = NavigationPath()
    @State private var monthOffset = 0
    @State private var range: TrendRange = .fourWeeks

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: MSpace.l) {
                    header
                    recommendCard
                    calendarCard
                    trendCard
                }
                .padding(MSpace.l)
            }
            .mouthyScreen()
            .navigationDestination(for: ReviewRoute.self) { route in
                if case .session(let id) = route, let session = model.session(id: id) {
                    FeedbackView(session: session, showsDone: false)
                }
            }
            .sheet(isPresented: dayPresented) {
                DaySessionsSheet(dayKey: model.dayKey ?? "", onOpen: { id in
                    model.dayKey = nil
                    path.append(ReviewRoute.session(id))
                })
                .presentationDetents([.medium, .large])
            }
        }
    }

    private var dayPresented: Binding<Bool> {
        Binding(get: { model.dayKey != nil }, set: { if !$0 { model.dayKey = nil } })
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(dateLabel).font(.subheadline).foregroundStyle(MColor.inkSecondary)
            Text(greeting).font(.system(.largeTitle, design: .rounded, weight: .heavy))
        }
        .accessibilityElement(children: .combine)
    }

    private var recommendCard: some View {
        let scene = model.recommendation
        return VStack(alignment: .leading, spacing: MSpace.m) {
            Label("今日のおすすめ", systemImage: "target")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(MColor.coralInk)
            VStack(alignment: .leading, spacing: 4) {
                Text(scene.title).font(.system(.title2, design: .rounded, weight: .heavy))
                Text("Lv\(scene.level) · 5分 · \(scene.goalJa)").font(.footnote).foregroundStyle(MColor.inkSecondary)
            }
            .padding(.trailing, 96)
            Button {
                model.briefMinutes = 5
                model.briefScene = scene
            } label: {
                Label("話す", systemImage: "mic.fill")
            }
            .buttonStyle(MouthyButtonStyle())
            .frame(maxWidth: 160)
        }
        .padding(MSpace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MColor.tintCoral, in: RoundedRectangle(cornerRadius: MRadius.card))
        .overlay(alignment: .topTrailing) {
            PakuView(expression: .hello, width: 104)
                .padding(.top, 8)
                .padding(.trailing, 6)
        }
    }

    private var calendarCard: some View {
        let calendar = StudyCalendar.tokyo()
        let today = Date()
        let shown = calendar.date(byAdding: .month, value: monthOffset, to: today) ?? today
        let parts = calendar.dateComponents([.year, .month], from: shown)
        let year = parts.year ?? 2026
        let month = parts.month ?? 11
        let grid = StudyCalendar.month(year, month, today: today, calendar: calendar)
        let counts = model.counts(in: year, month: month)
        return VStack(alignment: .leading, spacing: MSpace.m) {
            HStack {
                Text("学習記録").font(.mRounded(.headline))
                if model.streak > 0 {
                    Label("\(model.streak)日連続", systemImage: "flame.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(MColor.onCoral)
                        .background(MColor.sun, in: Capsule())
                }
                Spacer()
                Text("今月 \(model.monthPracticeDays)日").font(.caption).foregroundStyle(MColor.inkSecondary)
            }
            if model.loadFailed {
                Text("記録を読み込めませんでした").font(.footnote)
                Button("再試行") { model.reload() }.buttonStyle(MouthyButtonStyle(kind: .secondary))
            } else {
                HStack {
                    Button { monthOffset -= 1 } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    Spacer()
                    Text("\(year)年\(month)月").font(.mRounded(.headline))
                    Spacer()
                    Button { if StudyCalendar.canMoveForward(year: year, month: month, today: today) { monthOffset += 1 } } label: {
                        Image(systemName: "chevron.right").frame(width: 44, height: 44)
                    }
                    .disabled(!StudyCalendar.canMoveForward(year: year, month: month, today: today))
                }
                .foregroundStyle(MColor.ink)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                    ForEach(["日", "月", "火", "水", "木", "金", "土"], id: \.self) { label in
                        Text(label).font(.caption2).foregroundStyle(MColor.inkTertiary).frame(maxWidth: .infinity)
                    }
                    ForEach(Array(grid.cells.enumerated()), id: \.offset) { _, cell in
                        dayCell(cell, counts: counts)
                    }
                }
            }
        }
        .padding(MSpace.l)
        .background(MColor.surface, in: RoundedRectangle(cornerRadius: MRadius.card))
        .overlay(RoundedRectangle(cornerRadius: MRadius.card).stroke(MColor.line))
    }

    private func dayCell(_ cell: StudyCalendar.Cell, counts: [String: Int]) -> some View {
        let count = cell.key.flatMap { counts[$0] } ?? 0
        let level = StudyCalendar.intensity(sessionCount: count)
        return Button {
            guard let key = cell.key, !cell.isFuture else { return }
            model.dayKey = key
        } label: {
            Text(cell.day.map(String.init) ?? "")
                .font(.system(.footnote, design: .rounded, weight: cell.isToday ? .bold : .medium))
                .frame(width: 36, height: 36)
                .foregroundStyle(level >= 2 ? MColor.onCoral : MColor.ink)
                .background(dayFill(level), in: RoundedRectangle(cornerRadius: MRadius.day))
                .overlay {
                    RoundedRectangle(cornerRadius: MRadius.day)
                        .stroke(cell.isToday ? MColor.coralInk : (model.dayKey == cell.key ? MColor.ink : .clear), lineWidth: cell.isToday || model.dayKey == cell.key ? 2 : 0)
                }
                .frame(width: 44, height: 44)
                .opacity(cell.isFuture ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .disabled(cell.day == nil || cell.isFuture)
        .accessibilityLabel(accessibilityDay(cell, count: count))
        .accessibilityAddTraits(model.dayKey == cell.key ? .isSelected : [])
    }

    private func dayFill(_ level: Int) -> Color {
        switch level {
        case 1: return MColor.coral.opacity(0.45)
        case 2: return MColor.coral.opacity(0.75)
        case 3: return MColor.coral
        default: return MColor.fill
        }
    }

    private func accessibilityDay(_ cell: StudyCalendar.Cell, count: Int) -> String {
        guard let day = cell.day else { return "" }
        var label = "\(day)日、\(count)回"
        if cell.isToday { label += "、今日" }
        return label
    }

    private var trendCard: some View {
        let points = ProgressMath.series(model.sessions.map(\.snapshot), range: range, today: Date())
        let totals = model.sessions.map(\.total).reversed()
        return VStack(alignment: .leading, spacing: MSpace.m) {
            Text("伸び").font(.mRounded(.title3, weight: .heavy))
            Picker("期間", selection: $range) {
                ForEach(TrendRange.allCases, id: \.self) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            if points.isEmpty {
                Text("会話をすると、ここに伸びが出ます。").font(.footnote).foregroundStyle(MColor.inkSecondary)
            } else {
                if let median = ProgressMath.medianLast(Array(totals), limit: 5) {
                    Text("総合点（直近5回の中央値）").font(.caption).foregroundStyle(MColor.inkSecondary)
                    Text("\(median)").font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                }
                Chart {
                    ForEach(points) { point in
                        LineMark(x: .value("日", point.dayKey), y: .value("点", point.total), series: .value("軸", "総合点"))
                            .foregroundStyle(by: .value("軸", "総合点"))
                            .lineStyle(StrokeStyle(lineWidth: 3))
                        LineMark(x: .value("日", point.dayKey), y: .value("点", point.communication), series: .value("軸", "意思疎通"))
                        LineMark(x: .value("日", point.dayKey), y: .value("点", point.fluency), series: .value("軸", "流暢さ"))
                        LineMark(x: .value("日", point.dayKey), y: .value("点", point.accuracy), series: .value("軸", "正確さ"))
                    }
                }
                .chartForegroundStyleScale([
                    "総合点": MColor.ink,
                    "意思疎通": MColor.communication,
                    "流暢さ": MColor.fluency,
                    "正確さ": MColor.accuracy,
                ])
                .chartYScale(domain: 0...100)
                .frame(height: 180)
                metricRow
            }
        }
        .padding(MSpace.l)
        .background(MColor.surface, in: RoundedRectangle(cornerRadius: MRadius.card))
        .overlay(RoundedRectangle(cornerRadius: MRadius.card).stroke(MColor.line))
    }

    private var metricRow: some View {
        let latest = model.sessions.first
        let previous = model.sessions.dropFirst().first
        return ViewThatFits {
            HStack(spacing: 8) {
                metric("話した割合", ratio(latest?.talkRatio), deltaPoints(latest?.talkRatio, previous?.talkRatio))
                metric("反応までの時間", seconds(latest?.reactionSec), deltaSeconds(latest?.reactionSec, previous?.reactionSec))
                metric("1回の発話", words(latest?.averageWords), deltaWords(latest?.averageWords, previous?.averageWords))
            }
            VStack(spacing: 8) {
                metric("話した割合", ratio(latest?.talkRatio), deltaPoints(latest?.talkRatio, previous?.talkRatio))
                metric("反応までの時間", seconds(latest?.reactionSec), deltaSeconds(latest?.reactionSec, previous?.reactionSec))
                metric("1回の発話", words(latest?.averageWords), deltaWords(latest?.averageWords, previous?.averageWords))
            }
        }
    }

    private func metric(_ title: String, _ value: String, _ delta: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(MColor.inkSecondary)
            Text(value).font(.mRounded(.headline)).monospacedDigit()
            if let delta { Text(delta).font(.caption2).foregroundStyle(MColor.inkTertiary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(MColor.fill, in: RoundedRectangle(cornerRadius: 12))
    }

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: Date())
    }

    private var greeting: String {
        let hour = StudyCalendar.tokyo().component(.hour, from: Date())
        if hour < 11 { return "おはようございます" }
        if hour < 18 { return "こんにちは" }
        return "こんばんは"
    }

    private func ratio(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int((value * 100).rounded()))%"
    }
    private func seconds(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f秒", value)
    }
    private func words(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))語"
    }
    private func deltaPoints(_ current: Double?, _ previous: Double?) -> String? {
        guard let current, let previous else { return nil }
        return signed(Int(((current - previous) * 100).rounded()), suffix: "pt")
    }
    private func deltaSeconds(_ current: Double?, _ previous: Double?) -> String? {
        guard let current, let previous else { return nil }
        let text = String(format: "%+.1f秒", current - previous)
        return text.replacingOccurrences(of: "-", with: "−")
    }
    private func deltaWords(_ current: Double?, _ previous: Double?) -> String? {
        guard let current, let previous else { return nil }
        return signed(Int((current - previous).rounded()), suffix: "語")
    }
    private func signed(_ value: Int, suffix: String) -> String {
        if value > 0 { return "+\(value)\(suffix)" }
        if value < 0 { return "−\(abs(value))\(suffix)" }
        return "±0"
    }
}

struct DaySessionsSheet: View {
    @Environment(AppModel.self) private var model
    var dayKey: String
    var onOpen: (String) -> Void

    var body: some View {
        let items = model.sessions(on: dayKey)
        NavigationStack {
            Group {
                if items.isEmpty {
                    Text("この日の会話はありません")
                        .foregroundStyle(MColor.inkSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(items) { session in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(session.sceneTitle).font(.headline)
                                LevelBadge(level: session.level)
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text("総合点").font(.caption2).foregroundStyle(MColor.inkSecondary)
                                    Text("\(session.total)").font(.mRounded(.title2)).monospacedDigit()
                                }
                            }
                            Text("\(time(session.startedAt)) · \(max(1, session.durationSec / 60))分")
                                .font(.caption)
                                .foregroundStyle(MColor.inkSecondary)
                            HStack {
                                Text("意思疎通 \(session.communication)").font(.caption)
                                Text("流暢さ \(session.fluency)").font(.caption)
                                Text("正確さ \(session.accuracy)").font(.caption)
                            }
                            .foregroundStyle(MColor.inkSecondary)
                            Button("添削結果") { onOpen(session.id) }
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.vertical, 4)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .mouthyScreen()
            .navigationTitle(dayKey)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
