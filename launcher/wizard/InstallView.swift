// launcher/wizard/InstallView.swift
import SwiftUI

struct InstallView: View {
    @EnvironmentObject var wizard: WizardState
    @EnvironmentObject var state:  AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("step 4 / 4 — install")
                .font(CatStyle.monoTiny).tracking(2).textCase(.uppercase)
                .foregroundColor(CatStyle.dim)
            Text("about to do:")
                .font(CatStyle.mono).foregroundColor(CatStyle.text)
            Group {
                Text("· save repo: \(wizard.repo)")
                Text("· install 3 background agents")
                Text("· build menu bar app")
                Text("· run a one-time check to verify it works")
            }
            .font(CatStyle.monoSmall).foregroundColor(CatStyle.dim)

            if let err = wizard.installError {
                Text("⚠ \(err)").font(CatStyle.monoSmall).foregroundColor(CatStyle.red)
                    .padding(8).background(CatStyle.panelBg)
            }

            HStack(spacing: 8) {
                Button("Back") { wizard.step = .repoPicker }
                    .buttonStyle(PixelButtonStyle())
                Button(wizard.installing ? "Installing…" : "Install") {
                    runInstall()
                }
                .buttonStyle(PixelButtonStyle(primary: true))
                .disabled(wizard.installing)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(32)
    }

    private func runInstall() {
        wizard.installing = true
        wizard.installError = nil
        let repo = wizard.repo
        let bundlePath = Bundle.main.bundlePath
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let inst = Installer(bundlePath: bundlePath)
                try inst.install(repo: repo)
                // One-time smoke run of watch.sh; surface failure inline but don't abort.
                let p = Process()
                p.launchPath = "/bin/bash"
                p.arguments = ["\(bundlePath)/Contents/Resources/scripts/watch.sh"]
                p.standardOutput = Pipe(); p.standardError = Pipe()
                try? p.run(); p.waitUntilExit()
                DispatchQueue.main.async {
                    wizard.installing = false
                    state.refresh()
                    wizard.step = .catPicker
                }
            } catch {
                DispatchQueue.main.async {
                    wizard.installing = false
                    wizard.installError = error.localizedDescription
                }
            }
        }
    }
}
