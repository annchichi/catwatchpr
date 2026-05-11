// launcher/controlpanel/ControlPanelView.swift
import SwiftUI

struct ControlPanelView: View {
    @EnvironmentObject var state: AppState
    @State private var showActivity      = false
    @State private var showCatPicker     = false
    @State private var showRemoveConfirm = false

    var crashedExcerpt: String? {
        if case .crashed(let msg) = state.status.menubar { return msg } else { return nil }
    }

    var closeHint: String {
        switch state.status.catName.lowercased() {
        case "mochi":  return "mochi's got it from here~ close this whenever"
        case "boba":   return "boba's on it from the menu bar ✨ close this whenever!"
        case "matcha": return "matcha. menu bar. close this."
        case "miso":   return "miso… watches from the menu bar… close whenever…"
        default:       return "you can close this window — the cat watches from your menu bar"
        }
    }

    var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String).map { "v\($0)" } ?? ""
    }

    var body: some View {
        VStack(spacing: 14) {
            // Header
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
                Text(appVersion)
                    .font(CatStyle.monoTiny)
                    .foregroundColor(CatStyle.dim)
            }
            if let excerpt = crashedExcerpt {
                AlertBanner(excerpt: excerpt)
            }
            StatusGrid()
            ActionButtons(
                showActivity: $showActivity,
                showCatPicker: $showCatPicker,
                showRemoveConfirm: $showRemoveConfirm
            )
            if crashedExcerpt == nil {
                Text(closeHint)
                    .font(CatStyle.monoTiny)
                    .foregroundColor(CatStyle.dim)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: showActivity) { newValue in
            if newValue {
                ActivityWindowController.shared.show()
                showActivity = false  // it's a separate window, not a sheet
            }
        }
        .sheet(isPresented: $showCatPicker) {
            CatPickerSheet(close: { showCatPicker = false })
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
            Text("Soft uninstall keeps your cat preferences. Reset everything wipes them too.")
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
