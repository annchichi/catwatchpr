// launcher/LauncherApp.swift
// @main entry. Intercepts CLI args before SwiftUI starts, otherwise shows
// a placeholder window. Wizard and control panel arrive in later tasks.
import SwiftUI

@main
struct LauncherApp: App {
    init() {
        // CLI mode short-circuits SwiftUI — used by tests and recovery shell.
        // Run synchronously on the main actor (we're already on it during init).
        MainActor.assumeIsolated {
            if handleCLIIfNeeded() { /* exits inside */ }
        }
    }

    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup("CatWatchPR") {
            PlaceholderView()
                .environmentObject(state)
                .frame(minWidth: 460, minHeight: 360)
                .background(CatStyle.bg)
                .onAppear { state.startPolling() }
                .onDisappear { state.stopPolling() }
        }
        .windowResizability(.contentSize)
    }
}

struct PlaceholderView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        VStack(spacing: 16) {
            Text("🐱").font(.system(size: 48))
            Text("CatWatchPR").font(CatStyle.mono).tracking(2)
                .foregroundColor(CatStyle.cyan)
            Text("installed: \(state.isInstalled ? "yes" : "no") · repo: \(state.status.repo.isEmpty ? "—" : state.status.repo)")
                .font(CatStyle.monoSmall).foregroundColor(CatStyle.dim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
