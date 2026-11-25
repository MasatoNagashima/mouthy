import SwiftUI
import UIKit
import MouthyLogic

@main
struct MouthyApp: App {
    @State private var model = AppModel()

    init() {
        // Tabs use SF Pro Rounded (v0.7).
        let base = UIFont.systemFont(ofSize: 10, weight: .bold)
        if let rounded = base.fontDescriptor.withDesign(.rounded) {
            let font = UIFont(descriptor: rounded, size: 10)
            UITabBarItem.appearance().setTitleTextAttributes([.font: font], for: .normal)
            UITabBarItem.appearance().setTitleTextAttributes([.font: font], for: .selected)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(MColor.coralInk)
                .preferredColorScheme(nil)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.restoringSession {
                ProgressView(LoginCopy.signingIn)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !model.isSignedIn {
                SignInView()
            } else if model.profile.onboardingComplete {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .mouthyScreen()
        .onOpenURL { url in
            _ = AccountAuth.handle(url: url)
        }
        .task { await model.restoreIfNeeded() }
        .fullScreenCover(item: $model.talk, onDismiss: {
            if let pending = model.pendingReview {
                model.finishedSession = pending
                model.pendingReview = nil
            }
        }) { launch in
            TalkView(launch: launch)
        }
        .fullScreenCover(item: $model.finishedSession) { session in
            if session.isDiagnostic && !model.profile.onboardingComplete {
                DiagnosisResultView(session: session)
            } else {
                FeedbackView(session: session, showsDone: true)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Text(toast)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(MColor.ink, in: Capsule())
                    .foregroundStyle(MColor.bg)
                    .padding(.bottom, 24)
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 2_200_000_000)
                            if model.toast == toast { model.toast = nil }
                        }
                    }
            }
        }
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            HomeView().tag(AppTab.home).tabItem { Label("ホーム", systemImage: "house.fill") }
            SceneCatalogView().tag(AppTab.scenes).tabItem { Label("シーン", systemImage: "square.grid.2x2.fill") }
            RecordsView().tag(AppTab.records).tabItem { Label("記録", systemImage: "checklist") }
            ProfileView().tag(AppTab.profile).tabItem { Label("プロフィール", systemImage: "person.crop.circle.fill") }
        }
        .sheet(item: $model.briefScene) { scene in
            SceneBriefSheet(scene: scene)
                .presentationDetents([.large])
        }
    }
}
