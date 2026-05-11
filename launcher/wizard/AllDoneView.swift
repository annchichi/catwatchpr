// launcher/wizard/AllDoneView.swift
// Shown immediately after the cat picker, before the operational control
// panel. Reuses the control panel's header and status grid so the user can
// see everything is running, but hides action buttons to keep this moment
// purely about "you're done — go check your menu bar". On subsequent
// launches the regular ControlPanelView appears instead.
import SwiftUI
import AppKit

struct AllDoneView: View {
    @EnvironmentObject var wizard: WizardState
    @EnvironmentObject var state:  AppState
    var body: some View {
        VStack(spacing: 14) {
            // Header — same as control panel
            HStack(spacing: 12) {
                PixelCatView(color: state.status.catColor, scale: 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.status.catName.uppercased())
                        .font(CatStyle.monoSmall).tracking(1.5)
                        .foregroundColor(CatStyle.cyan)
                    Text("~ watching wherever you're involved ~")
                        .font(CatStyle.monoTiny).foregroundColor(CatStyle.dim)
                }
                Spacer()
            }

            StatusGrid()

            // Close message — replaces the action buttons in this state.
            VStack(spacing: 6) {
                Text("✓ All set!")
                    .font(CatStyle.mono).foregroundColor(CatStyle.green)
                Text("Look at your menu bar (top right) —\nyour cat icon is up there now.\n\nYou can close this window. The cat will pop up\nwhen something on your PRs needs you.")
                    .font(CatStyle.monoTiny).foregroundColor(CatStyle.dim)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 4)

            Button("Close") {
                wizard.isFinished = true
                NSApplication.shared.keyWindow?.close()
            }
            .buttonStyle(PixelButtonStyle(primary: true))
            .frame(width: 200)

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
