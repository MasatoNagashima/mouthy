import SwiftUI
import UserNotifications
import MouthyLogic

struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @State private var editing = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Text(model.profile.initial)
                            .font(.title2.bold())
                            .frame(width: 56, height: 56)
                            .background(MColor.green, in: Circle())
                            .foregroundStyle(MColor.onGreen)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.profile.displayName).font(.headline)
                            Text(levelLine).font(.footnote).foregroundStyle(MColor.inkSecondary)
                            Text("TOEIC \(model.profile.toeic.title)").font(.caption).foregroundStyle(MColor.inkTertiary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editing = true }
                }
                Section {
                    HStack {
                        stat("連続", "\(model.streak)日")
                        stat("合計", "\(model.sessions.count)回")
                        stat("話した時間", ProgressMath.talkTimeLabel(seconds: model.totalTalkSeconds))
                    }
                }
                Section("会話") {
                    Picker("AIの話す速さ", selection: Bindable(model).settings.speechSpeed) {
                        Text("ゆっくり").tag(0.9)
                        Text("ふつう").tag(1.0)
                        Text("少し速く").tag(1.05)
                    }
                    Stepper(value: Bindable(model).settings.hintDelaySec, in: 5...30) {
                        Text("ヒントまでの間  \(model.settings.hintDelaySec)秒")
                    }
                    Toggle("字幕を表示", isOn: Bindable(model).settings.captionsOn)
                }
                Section("通知") {
                    Toggle("練習リマインダー", isOn: reminderBinding)
                    if model.settings.reminderOn {
                        Text(model.settings.reminderLabel).font(.footnote).foregroundStyle(MColor.inkSecondary)
                    }
                }
                Section("データとプライバシー") {
                    Toggle("録音を保存する", isOn: recordingBinding)
                    ShareLink(item: exportFile) { Text("履歴を書き出す（JSON）") }
                }
                Section {
                    Button("アカウントを削除", role: .destructive) { confirmDelete = true }
                } footer: {
                    Text("この端末のプロフィール、同意の記録、会話の添削結果を消します。音声の録音は残していません。")
                }
            }
            .scrollContentBackground(.hidden)
            .mouthyScreen()
            .navigationTitle("プロフィール")
            .onChange(of: model.settings) { _, _ in model.save() }
            .sheet(isPresented: $editing) { editSheet }
            .confirmationDialog("アカウントを削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("削除する", role: .destructive) { model.wipe() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("この端末の記録は元に戻せません。")
            }
        }
    }

    private var levelLine: String {
        let level = model.profile.cefr ?? "未診断"
        return "推定レベル \(level) · 目標：\(model.profile.goal.title)"
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption).foregroundStyle(MColor.inkSecondary)
            Text(value).font(.headline).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    private var reminderBinding: Binding<Bool> {
        Binding(get: { model.settings.reminderOn }, set: { on in
            model.settings.reminderOn = on
            if on { schedule() }
            else { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["mouthy.reminder"]) }
            model.save()
        })
    }

    private var recordingBinding: Binding<Bool> {
        Binding(get: { false }, set: { wantsOn in
            if wantsOn { model.toast = "録音の保存は、同意画面ができてからにします。" }
        })
    }

    private var exportFile: URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mouthy-export.json")
        try? model.exportData().write(to: url)
        return url
    }

    private var editSheet: some View {
        NavigationStack {
            Form {
                TextField("名前", text: Bindable(model).profile.name)
                Picker("話したい場面", selection: Bindable(model).profile.goal) {
                    ForEach(PracticeGoal.allCases, id: \.self) { goal in
                        Text(goal.title).tag(goal)
                    }
                }
                Picker("TOEICの目安", selection: Bindable(model).profile.toeic) {
                    ForEach(ToeicBand.allCases, id: \.self) { band in
                        Text(band.title).tag(band)
                    }
                }
            }
            .navigationTitle("プロフィール")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { model.save(); editing = false } } }
        }
    }

    private func schedule() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in
                guard granted else {
                    model.settings.reminderOn = false
                    model.toast = "通知が許可されていません。"
                    model.save()
                    return
                }
                let content = UNMutableNotificationContent()
                content.title = "Mouthy"
                content.body = "今日の英語、5分だけ話してみませんか。"
                var date = DateComponents()
                date.hour = model.settings.reminderHour
                date.minute = model.settings.reminderMinute
                let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "mouthy.reminder", content: content, trigger: trigger))
            }
        }
    }
}
