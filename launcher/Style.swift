// launcher/Style.swift
// Pixel/terminal styling helpers used across the launcher UI.
import SwiftUI

enum CatStyle {
    static let bg          = Color(red: 0.04, green: 0.04, blue: 0.06)
    static let panelBg     = Color(red: 0.075, green: 0.075, blue: 0.10)
    static let cyan        = Color(red: 0.0,  green: 0.85, blue: 1.0)
    static let red         = Color(red: 1.0,  green: 0.33, blue: 0.46)
    static let green       = Color(red: 0.5,  green: 1.0,  blue: 0.5)
    static let dim         = Color(red: 0.48, green: 0.48, blue: 0.56)
    static let text        = Color(red: 0.91, green: 0.91, blue: 0.94)
    static let mono        = Font.system(.body, design: .monospaced)
    static let monoSmall   = Font.system(size: 11, design: .monospaced)
    static let monoTiny    = Font.system(size: 9, design: .monospaced)
}

struct PixelButtonStyle: ButtonStyle {
    var primary: Bool = false
    var danger:  Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(1.2)
            .textCase(.uppercase)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(primary ? CatStyle.cyan : Color.clear)
            .foregroundColor(
                primary ? CatStyle.bg :
                danger  ? CatStyle.red :
                CatStyle.text
            )
            .overlay(
                Rectangle()
                    .stroke(
                        primary ? Color.clear :
                        danger  ? CatStyle.red :
                        Color(red: 0.16, green: 0.16, blue: 0.23),
                        lineWidth: 1
                    )
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}
