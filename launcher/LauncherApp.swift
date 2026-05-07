// launcher/LauncherApp.swift
// @main entry. For now: shows a placeholder window so we can validate the
// .app bundle compiles, launches, and shows up correctly. The wizard and
// control panel are wired in later tasks.
import SwiftUI

@main
struct LauncherApp: App {
    var body: some Scene {
        WindowGroup("CatWatchPR") {
            PlaceholderView()
                .frame(minWidth: 460, minHeight: 360)
                .background(CatStyle.bg)
        }
        .windowResizability(.contentSize)
    }
}

struct PlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("🐱")
                .font(.system(size: 48))
            Text("CatWatchPR")
                .font(CatStyle.mono)
                .tracking(2)
                .foregroundColor(CatStyle.cyan)
            Text("scaffold OK · wizard wired in Task 4")
                .font(CatStyle.monoSmall)
                .foregroundColor(CatStyle.dim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
