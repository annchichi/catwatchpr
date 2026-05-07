// launcher/controlpanel/ActionButtons.swift
import SwiftUI
import AppKit

struct ActionButtons: View {
    @EnvironmentObject var state: AppState
    @Binding var showActivity: Bool
    @Binding var showCatPicker: Bool
    @Binding var showRepoEditor: Bool
    @Binding var showRemoveConfirm: Bool

    var crashed: Bool {
        if case .crashed = state.status.menubar { return true } else { return false }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Button("Restart all", action: restartAll)
                    .buttonStyle(PixelButtonStyle(primary: crashed))
                Button("Activity") { showActivity = true }
                    .buttonStyle(PixelButtonStyle())
            }
            HStack(spacing: 18) {
                Button("switch cat ▸") { showCatPicker = true }
                    .buttonStyle(.plain).foregroundColor(CatStyle.dim)
                    .font(CatStyle.monoTiny)
                Button("change repo ▸") { showRepoEditor = true }
                    .buttonStyle(.plain).foregroundColor(CatStyle.dim)
                    .font(CatStyle.monoTiny)
                Button("remove ▸") { showRemoveConfirm = true }
                    .buttonStyle(.plain).foregroundColor(CatStyle.red)
                    .font(CatStyle.monoTiny)
            }
            .padding(.top, 6)
            .overlay(Rectangle().frame(height:1)
                .foregroundColor(Color(red:0.16,green:0.16,blue:0.23)),
                     alignment: .top)
        }
    }

    private func restartAll() {
        for label in Installer.labels {
            let plist = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/LaunchAgents/\(label).plist")
            let p = Process()
            p.launchPath = "/bin/launchctl"
            p.arguments = ["kickstart", "-k", "gui/\(getuid())/\(label)"]
            p.standardOutput = Pipe(); p.standardError = Pipe()
            try? p.run(); p.waitUntilExit()
            if !FileManager.default.fileExists(atPath: plist.path) {
                // Plist missing — load from bundle template again.
                let inst = Installer(bundlePath: Bundle.main.bundlePath)
                _ = try? inst.install(repo: state.status.repo)
            }
        }
        state.refresh()
    }
}
