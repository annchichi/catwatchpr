// launcher/PixelCat.swift
// Renders the same 12x12 pixel cat sprite that menubar.swift draws into the
// menu bar icon — kept here as a SwiftUI view so the launcher UI matches the
// menu bar visually. Sprite + palettes are duplicated from menubar.swift to
// keep the launcher self-contained (the menubar binary is compiled separately).
import SwiftUI

private let sitA: [[Int]] = [
    [0,0,0,1,0,0,0,0,1,0,0,0],
    [0,0,1,1,1,0,0,1,1,1,0,0],
    [0,1,1,1,1,1,1,1,1,1,1,0],
    [1,1,1,1,1,1,1,1,1,1,1,1],
    [1,1,3,1,1,1,1,1,1,3,1,1],
    [1,1,2,1,1,4,1,1,1,2,1,1],
    [1,1,1,1,1,1,1,1,1,1,1,1],
    [1,1,1,1,1,1,1,1,1,1,1,1],
    [0,1,1,1,1,1,1,1,1,1,2,0],
    [0,0,1,1,0,0,0,1,1,0,2,0],
    [0,0,0,0,0,0,0,0,0,1,0,0],
    [0,0,0,0,0,0,0,0,0,0,0,0],
]

private struct CatPalette {
    let body: Color
    let dark: Color
    let eye: Color
    let nose: Color
}

private let palettes: [String: CatPalette] = [
    "cyan":  .init(body: Color(red: 0,     green: 0.898, blue: 1),
                   dark: Color(red: 0,     green: 0.478, blue: 0.6),
                   eye:  Color(red: 0.69,  green: 0.965, blue: 1),
                   nose: Color(red: 1,     green: 0.176, blue: 0.608)),
    "lime":  .init(body: Color(red: 0.224, green: 1,     blue: 0.078),
                   dark: Color(red: 0.122, green: 0.6,   blue: 0),
                   eye:  Color(red: 0.784, green: 1,     blue: 0.69),
                   nose: .white),
    "pink":  .init(body: Color(red: 1,     green: 0.176, blue: 0.608),
                   dark: Color(red: 0.71,  green: 0,     blue: 0.42),
                   eye:  Color(red: 1,     green: 0.702, blue: 0.863),
                   nose: .white),
    "ghost": .init(body: Color(red: 0.847, green: 0.816, blue: 0.941),
                   dark: Color(red: 0.6,   green: 0.533, blue: 0.8),
                   eye:  .white,
                   nose: Color(red: 1,     green: 0.176, blue: 0.608)),
]

struct PixelCatView: View {
    var color: String = "cyan"
    var scale: CGFloat = 4
    var body: some View {
        let p = palettes[color.lowercased()] ?? palettes["cyan"]!
        let cols = sitA[0].count, rows = sitA.count
        Canvas { ctx, _ in
            for (r, row) in sitA.enumerated() {
                for (c, v) in row.enumerated() {
                    let col: Color? = {
                        switch v {
                        case 1: return p.body
                        case 2: return p.dark
                        case 3: return p.eye
                        case 4: return p.nose
                        default: return nil
                        }
                    }()
                    guard let col else { continue }
                    let rect = CGRect(x: CGFloat(c) * scale,
                                      y: CGFloat(r) * scale,
                                      width: scale, height: scale)
                    ctx.fill(Path(rect), with: .color(col))
                }
            }
        }
        .frame(width: CGFloat(cols) * scale, height: CGFloat(rows) * scale)
    }
}
