// launcher/wizard/CatPickerView.swift
// Used both as wizard step 5 and as the "Switch cat" sheet in the control
// panel — caller passes an `onDone` closure so each context can decide what
// "Done" means (advance to control panel vs. close the sheet).
import SwiftUI

struct CatPickerView: View {
    @EnvironmentObject var state: AppState
    var onDone: () -> Void = {}

    let cats: [(name: String, color: String, emoji: String, blurb: String)] = [
        ("Mochi",  "cyan",  "🐱", "friendly · default"),
        ("Boba",   "pink",  "🐈", "warm · excited"),
        ("Matcha", "lime",  "😼", "minimal · no-nonsense"),
        ("Miso",   "ghost", "👻", "soft · dreamy"),
    ]
    var body: some View {
        VStack(spacing: 14) {
            Text("pick your cat")
                .font(CatStyle.monoTiny).tracking(2).textCase(.uppercase)
                .foregroundColor(CatStyle.dim)
            Text("you can switch any time")
                .font(CatStyle.monoSmall).foregroundColor(CatStyle.text)
            HStack(spacing: 12) {
                ForEach(cats, id: \.name) { cat in
                    Button(action: { pick(cat.name, cat.color) }) {
                        VStack(spacing: 6) {
                            Text(cat.emoji).font(.system(size: 28))
                            Text(cat.name).font(CatStyle.mono).foregroundColor(CatStyle.cyan)
                            Text(cat.blurb).font(CatStyle.monoTiny).foregroundColor(CatStyle.dim)
                        }
                        .frame(width: 90, height: 90)
                        .background(CatStyle.panelBg)
                        .overlay(Rectangle().stroke(
                            state.status.catName.lowercased() == cat.name.lowercased()
                                ? CatStyle.cyan : Color(red:0.16,green:0.16,blue:0.23),
                            lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            Button("Done") { onDone() }
                .buttonStyle(PixelButtonStyle(primary: true))
                .frame(width: 200)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func pick(_ name: String, _ color: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/woo-sprinkles")
        try? name.lowercased().write(to: dir.appendingPathComponent("cat_name"),
                                      atomically: true, encoding: .utf8)
        try? color.write(to: dir.appendingPathComponent("cat_color"),
                          atomically: true, encoding: .utf8)
        state.refresh()
        // Kick the menubar so the icon updates immediately.
        let p = Process()
        p.launchPath = "/bin/launchctl"
        p.arguments = ["kickstart", "-k",
                       "gui/\(getuid())/com.annchiahui.woo-sprinkles.menubar"]
        try? p.run()
    }
}
