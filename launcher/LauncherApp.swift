// launcher/LauncherApp.swift
// @main entry. Intercepts CLI args before SwiftUI starts. Otherwise routes:
// - First-run / not yet onboarded → wizard
// - Returning user (already installed + has repo config) → control panel placeholder
// The control panel itself arrives in Task 6.
import SwiftUI

@main
struct LauncherApp: App {
    init() {
        // CLI mode short-circuits SwiftUI — used by tests and recovery shell.
        MainActor.assumeIsolated {
            if handleCLIIfNeeded() { /* exits inside */ }
        }
    }

    @StateObject private var state  = AppState()
    @StateObject private var wizard = WizardState()

    var body: some Scene {
        WindowGroup("CatWatchPR") {
            RootView()
                .environmentObject(state)
                .environmentObject(wizard)
                .frame(minWidth: 460, minHeight: 360)
                .background(CatStyle.bg)
                .onAppear { state.startPolling() }
                .onDisappear { state.stopPolling() }
        }
        .windowResizability(.contentSize)
    }
}

struct RootView: View {
    @EnvironmentObject var state:  AppState
    @EnvironmentObject var wizard: WizardState
    var body: some View {
        Group {
            if state.isInstalled && state.hasRepoConfig && wizard.isFinished {
                // Control panel comes online in Task 6.
                PlaceholderControlPanelView()
            } else {
                switch wizard.step {
                case .welcome:    WelcomeView()
                case .authCheck:  AuthCheckView()
                case .repoPicker: RepoPickerView()
                case .install:    InstallView()
                case .catPicker:  CatPickerView(onDone: { wizard.isFinished = true })
                }
            }
        }
        .onAppear {
            // Returning user (already installed): skip the wizard entirely.
            if state.isInstalled && state.hasRepoConfig {
                wizard.isFinished = true
            }
        }
    }
}

struct PlaceholderControlPanelView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        VStack(spacing: 12) {
            Text("✓ installed").font(CatStyle.mono).foregroundColor(CatStyle.green)
            Text("repo: \(state.status.repo)")
                .font(CatStyle.monoSmall).foregroundColor(CatStyle.dim)
            Text("control panel arrives in Task 6")
                .font(CatStyle.monoTiny).foregroundColor(CatStyle.dim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
