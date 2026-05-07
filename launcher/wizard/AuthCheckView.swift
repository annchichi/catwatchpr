// launcher/wizard/AuthCheckView.swift
import SwiftUI
import AppKit

struct AuthCheckView: View {
    @EnvironmentObject var wizard: WizardState
    @State private var copied = false

    private let command = "gh auth login --web --git-protocol https"

    var body: some View {
        VStack(spacing: 14) {
            Text("step 2 / 4 — github access")
                .font(CatStyle.monoTiny).tracking(2).textCase(.uppercase)
                .foregroundColor(CatStyle.dim)

            if wizard.ghAuthed {
                Text("● gh is authenticated")
                    .font(CatStyle.mono).foregroundColor(CatStyle.green)
                Button("Continue") { wizard.step = .repoPicker }
                    .buttonStyle(PixelButtonStyle(primary: true))
                    .frame(width: 200)
            } else {
                Text("● gh is NOT authenticated")
                    .font(CatStyle.mono).foregroundColor(CatStyle.red)
                Text("In Terminal, run this command and follow\nyour browser to sign in:")
                    .font(CatStyle.monoSmall).foregroundColor(CatStyle.text)
                    .multilineTextAlignment(.center)

                // Click-to-copy command box with inline copy icon
                Button {
                    copyCommand()
                } label: {
                    HStack(spacing: 8) {
                        Text(command)
                            .font(CatStyle.mono).foregroundColor(CatStyle.cyan)
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundColor(copied ? CatStyle.green : CatStyle.dim)
                    }
                    .padding(8)
                    .background(CatStyle.panelBg)
                    .overlay(Rectangle().stroke(
                        Color(red:0.16,green:0.16,blue:0.23), lineWidth: 1))
                }.buttonStyle(.plain)

                Text("When your browser says \"authentication complete\",\ncome back here and click Re-check.")
                    .font(CatStyle.monoTiny).foregroundColor(CatStyle.dim)
                    .multilineTextAlignment(.center)

                Button("Re-check") {
                    wizard.checkAuth()
                }
                .buttonStyle(PixelButtonStyle(primary: true))
                .frame(width: 200)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .onAppear { wizard.checkAuth() }
    }

    private func copyCommand() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(command, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copied = false
        }
    }
}
