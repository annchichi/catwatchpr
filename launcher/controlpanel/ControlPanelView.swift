// launcher/controlpanel/ControlPanelView.swift
import SwiftUI

struct ControlPanelView: View {
    @EnvironmentObject var state: AppState
    @State private var showActivity      = false
    @State private var showCatPicker     = false
    @State private var showRepoEditor    = false
    @State private var showRemoveConfirm = false

    var crashedExcerpt: String? {
        if case .crashed(let msg) = state.status.menubar { return msg } else { return nil }
    }

    var body: some View {
        VStack(spacing: 14) {
            // Header
            HStack(spacing: 12) {
                Text("🐱").font(.system(size: 28))
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.status.catName.uppercased())
                        .font(CatStyle.monoSmall).tracking(1.5)
                        .foregroundColor(CatStyle.cyan)
                    Text("~ watching \(state.status.repo) ~")
                        .font(CatStyle.monoTiny).foregroundColor(CatStyle.dim)
                }
                Spacer()
            }
            if let excerpt = crashedExcerpt {
                AlertBanner(excerpt: excerpt)
            }
            StatusGrid()
            ActionButtons(
                showActivity: $showActivity,
                showCatPicker: $showCatPicker,
                showRepoEditor: $showRepoEditor,
                showRemoveConfirm: $showRemoveConfirm
            )
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $showCatPicker) {
            CatPickerSheet(close: { showCatPicker = false })
        }
        .sheet(isPresented: $showRepoEditor) {
            RepoEditorSheet(close: { showRepoEditor = false })
        }
        .alert("Remove CatWatchPR?", isPresented: $showRemoveConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Soft uninstall", role: .destructive) {
                Installer(bundlePath: Bundle.main.bundlePath).uninstall()
                state.refresh()
            }
            Button("Reset everything (wipe config too)", role: .destructive) {
                Installer(bundlePath: Bundle.main.bundlePath).reset()
                state.refresh()
            }
        } message: {
            Text("Soft uninstall keeps your repo + cat preferences. Reset everything wipes them too.")
        }
    }
}

struct CatPickerSheet: View {
    let close: () -> Void
    var body: some View {
        CatPickerView(onDone: close)
            .padding(24)
            .frame(width: 460, height: 360)
            .background(CatStyle.bg)
    }
}

struct RepoEditorSheet: View {
    @EnvironmentObject var state: AppState
    let close: () -> Void
    @State private var repo: String = ""
    @State private var error: String? = nil
    var body: some View {
        VStack(spacing: 14) {
            Text("change watched repo")
                .font(CatStyle.monoTiny).tracking(2).textCase(.uppercase)
                .foregroundColor(CatStyle.dim)
            TextField("org/repo", text: $repo)
                .textFieldStyle(.plain)
                .font(CatStyle.mono).foregroundColor(CatStyle.cyan)
                .padding(10).background(CatStyle.panelBg)
                .frame(width: 280)
            if let e = error { Text(e).font(CatStyle.monoTiny).foregroundColor(CatStyle.red) }
            HStack(spacing: 8) {
                Button("Cancel", action: close).buttonStyle(PixelButtonStyle())
                Button("Save") { save() }.buttonStyle(PixelButtonStyle(primary: true))
                    .disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 360, height: 220)
        .background(CatStyle.bg)
        .onAppear { repo = state.status.repo }
    }
    var isValid: Bool {
        repo.range(of: WizardState.repoRegex, options: .regularExpression) != nil
    }
    func save() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/woo-sprinkles")
        do {
            try repo.write(to: dir.appendingPathComponent("repo"),
                           atomically: true, encoding: .utf8)
            // Restart watch agent so it picks up the new repo.
            let p = Process()
            p.launchPath = "/bin/launchctl"
            p.arguments = ["kickstart", "-k",
                           "gui/\(getuid())/com.annchiahui.woo-sprinkles.watch"]
            try? p.run()
            state.refresh()
            close()
        } catch {
            self.error = "Could not write: \(error.localizedDescription)"
        }
    }
}
