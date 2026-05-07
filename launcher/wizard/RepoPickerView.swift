// launcher/wizard/RepoPickerView.swift
import SwiftUI

struct RepoPickerView: View {
    @EnvironmentObject var wizard: WizardState
    var body: some View {
        VStack(spacing: 14) {
            Text("step 3 / 4 — pick a repo")
                .font(CatStyle.monoTiny).tracking(2).textCase(.uppercase)
                .foregroundColor(CatStyle.dim)
            Text("Which repo should I watch?")
                .font(CatStyle.mono).foregroundColor(CatStyle.text)
            TextField("org/repo", text: $wizard.repo)
                .textFieldStyle(.plain)
                .font(CatStyle.mono).foregroundColor(CatStyle.cyan)
                .padding(10)
                .background(CatStyle.panelBg)
                .overlay(Rectangle().stroke(
                    wizard.repoIsValid ? CatStyle.cyan : Color(red:0.16,green:0.16,blue:0.23),
                    lineWidth: 1))
                .frame(width: 280)
            Text("Your PRs in this repo will trigger the cat. You can\nchange this later.")
                .font(CatStyle.monoTiny).foregroundColor(CatStyle.dim)
                .multilineTextAlignment(.center)
            Button("Continue") { wizard.step = .install }
                .buttonStyle(PixelButtonStyle(primary: true))
                .frame(width: 200)
                .disabled(!wizard.repoIsValid)
                .opacity(wizard.repoIsValid ? 1.0 : 0.4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .onAppear { if wizard.repo.isEmpty { wizard.suggestRepo() } }
    }
}
