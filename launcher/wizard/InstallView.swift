// launcher/wizard/InstallView.swift
import SwiftUI

struct InstallView: View {
    @EnvironmentObject var wizard: WizardState
    @EnvironmentObject var state:  AppState
    var body: some View {
        VStack(spacing: 14) {
            Text("step 3 / 4 — install")
                .font(CatStyle.monoTiny).tracking(2).textCase(.uppercase)
                .foregroundColor(CatStyle.dim)
            VStack(alignment: .leading, spacing: 8) {
                Text("about to do:")
                    .font(CatStyle.mono).foregroundColor(CatStyle.text)
                Group {
                    Text("· install 3 background agents")
                    Text("· build menu bar app")
                    Text("· run a one-time check to verify it works")
                }
                .font(CatStyle.monoSmall).foregroundColor(CatStyle.dim)
            }

            if let err = wizard.installError {
                Text("⚠ \(err)").font(CatStyle.monoSmall).foregroundColor(CatStyle.red)
                    .padding(8).background(CatStyle.panelBg)
            }

            Button(wizard.installing ? "Installing…" : "Install") {
                runInstall()
            }
            .buttonStyle(PixelButtonStyle(primary: true))
            .disabled(wizard.installing)
            .frame(width: 200)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func runInstall() {
        wizard.installing = true
        wizard.installError = nil
        let bundlePath = Bundle.main.bundlePath
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let inst = Installer(bundlePath: bundlePath)
                try inst.install()
                // One-time smoke run of watch.sh; surface failure inline but don't abort.
                // Mac .apps don't inherit shell PATH, so explicitly include the
                // common Homebrew locations so watch.sh can find `gh`.
                let p = Process()
                p.launchPath = "/bin/bash"
                p.arguments = ["\(bundlePath)/Contents/Resources/scripts/watch.sh"]
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                p.environment = env
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
