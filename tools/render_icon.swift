// tools/render_icon.swift
// Renders the 12x12 pixel cat sprite (cyan = Mochi) at any pixel size, with
// a dark background, into a PNG. Used by build_app.sh to assemble the .icns
// asset for CatWatchPR.app's dock icon.
//
// Usage: swift tools/render_icon.swift <size_in_pixels> <output_path>
import AppKit
import Foundation

let sitA: [[Int]] = [
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

// Mochi (cyan) palette — same values as launcher/PixelCat.swift and menubar.swift.
let body = NSColor(red: 0,    green: 0.898, blue: 1,     alpha: 1)
let dark = NSColor(red: 0,    green: 0.478, blue: 0.6,   alpha: 1)
let eye  = NSColor(red: 0.69, green: 0.965, blue: 1,     alpha: 1)
let nose = NSColor(red: 1,    green: 0.176, blue: 0.608, alpha: 1)
let bg   = NSColor(red: 0.04, green: 0.04,  blue: 0.06,  alpha: 1)

let args = CommandLine.arguments
guard args.count == 3, let canvas = Int(args[1]) else {
    FileHandle.standardError.write(
        "usage: swift render_icon.swift <size> <output.png>\n".data(using: .utf8)!)
    exit(1)
}
let outPath = args[2]

let rows = sitA.count, cols = sitA[0].count

// Cell size = floor(canvas / (cols + padding)). Padding of ~3 sprite-cells
// gives the cat enough breathing room without looking lost on large icons.
let cellSize = max(1, canvas / (cols + 3))
let spriteWidth  = cols * cellSize
let spriteHeight = rows * cellSize
let originX = (canvas - spriteWidth)  / 2
let originY = (canvas - spriteHeight) / 2

let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

// Background fill.
bg.setFill()
NSRect(x: 0, y: 0, width: canvas, height: canvas).fill()

// Sprite.
let colorMap: [Int: NSColor] = [1: body, 2: dark, 3: eye, 4: nose]
for (r, row) in sitA.enumerated() {
    for (c, v) in row.enumerated() {
        guard let color = colorMap[v] else { continue }
        color.setFill()
        // NSImage origin is bottom-left; flip y so row 0 of the sprite is at top.
        NSRect(
            x: originX + c * cellSize,
            y: originY + (rows - 1 - r) * cellSize,
            width: cellSize, height: cellSize
        ).fill()
    }
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep  = NSBitmapImageRep(data: tiff),
      let png  = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("PNG encoding failed\n".data(using: .utf8)!)
    exit(1)
}
try? png.write(to: URL(fileURLWithPath: outPath))
