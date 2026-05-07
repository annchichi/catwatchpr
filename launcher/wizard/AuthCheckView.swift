// launcher/wizard/AuthCheckView.swift
import SwiftUI
import AppKit

struct AuthCheckView: View {
    @EnvironmentObject var wizard: WizardState
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
                Text("Open Terminal and run:")
                    .font(CatStyle.monoSmall).foregroundColor(CatStyle.dim)
                Text("gh auth login")
                    .font(CatStyle.mono).foregroundColor(CatStyle.cyan)
                    .padding(8).background(CatStyle.panelBg)
                HStack(spacing: 8) {
                    Button("Copy command") {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString("gh auth login", forType: .string)
                    }.buttonStyle(PixelButtonStyle())
                    Button("Re-check") {
                        wizard.checkAuth()
                    }.buttonStyle(PixelButtonStyle(primary: true))
                }.frame(width: 280)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .onAppear { wizard.checkAuth() }
    }
}
