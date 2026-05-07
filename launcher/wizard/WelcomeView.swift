// launcher/wizard/WelcomeView.swift
import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var wizard: WizardState
    var body: some View {
        VStack(spacing: 18) {
            Text("🐱").font(.system(size: 56))
            Text("CATWATCHPR")
                .font(CatStyle.mono).tracking(3).foregroundColor(CatStyle.cyan)
            Text("I watch your GitHub PRs and pop up\nwhen something needs you.")
                .font(CatStyle.monoSmall).foregroundColor(CatStyle.text)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 8)
            Button("Get started") {
                wizard.step = .authCheck
            }
            .buttonStyle(PixelButtonStyle(primary: true))
            .frame(width: 200)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
