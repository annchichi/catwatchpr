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
        Self.refreshDeployedPlists()
    }

    /// Re-write the deployed launch agent plists from this bundle's templates
    /// on every launch. Keeps the deployed plists in sync with the .app so
    /// plist-level changes (e.g. KeepAlive tweaks) take effect on upgrade
    /// without making the user re-run the wizard. Idempotent.
    private static func refreshDeployedPlists() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let menubarPlist = home.appendingPathComponent(
            "Library/LaunchAgents/com.annchiahui.woo-sprinkles.menubar.plist")
        guard FileManager.default.fileExists(atPath: menubarPlist.path) else { return }

        try? Installer(bundlePath: Bundle.main.bundlePath).install()
    }

    @StateObject private var state  = AppState()
    @StateObject private var wizard = WizardState()

    var body: some Scene {
        WindowGroup("CatWatchPR") {
            RootView()
                .environmentObject(state)
                .environmentObject(wizard)
                .frame(minWidth: 440, idealWidth: 480, maxWidth: 560,
                       minHeight: 420, idealHeight: 540, maxHeight: 720)
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
                ControlPanelView()
            } else {
                switch wizard.step {
                case .welcome:    WelcomeView()
                case .authCheck:  AuthCheckView()
                case .install:    InstallView()
                case .catPicker:  CatPickerView(onDone: { wizard.step = .allDone })
                case .allDone:    AllDoneView()
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
