#!/usr/bin/env swift

import AppKit
import Foundation

// MARK: - Helpers

extension NSColor {
    convenience init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        self.init(
            red:   CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8)  & 0xFF) / 255,
            blue:  CGFloat( rgb        & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Pixel cat (0=transparent, 1=body, 2=dark, 3=eye, 4=nose)

let pixelMap: [[Int]] = [
    [0,0,1,1,0,0,0,0,1,1,0,0],
    [0,1,1,1,1,0,0,1,1,1,1,0],
    [1,1,1,1,1,1,1,1,1,1,1,1],
    [1,1,3,1,1,1,1,1,1,3,1,1],
    [1,1,1,1,1,4,1,1,1,1,1,1],
    [1,1,2,1,1,1,1,1,1,2,1,1],
    [0,1,1,1,1,1,1,1,1,1,1,0],
    [0,1,2,1,1,1,1,1,1,2,1,0],
    [0,1,1,0,0,0,0,0,0,1,1,0],
    [0,1,0,0,0,0,0,0,0,0,1,0],
]

let PX    = 9
let COLS  = 12
let ROWS  = 10

struct Palette { let body, dark, eye, nose: NSColor }

let palettes: [String: Palette] = [
    "cyan":  Palette(body: .init(hex:"#00e5ff"), dark: .init(hex:"#007a99"), eye: .init(hex:"#b0f6ff"), nose: .init(hex:"#ff2d9b")),
    "lime":  Palette(body: .init(hex:"#39ff14"), dark: .init(hex:"#1f9900"), eye: .init(hex:"#c8ffb0"), nose: .init(hex:"#ffffff")),
    "pink":  Palette(body: .init(hex:"#ff2d9b"), dark: .init(hex:"#b5006b"), eye: .init(hex:"#ffb3dc"), nose: .init(hex:"#ffffff")),
    "ghost": Palette(body: .init(hex:"#d8d0f0"), dark: .init(hex:"#9988cc"), eye: .init(hex:"#ffffff"),  nose: .init(hex:"#ff2d9b")),
]

// MARK: - Cat view

class CatView: NSView {
    let palette: Palette
    init(frame: NSRect, palette: Palette) {
        self.palette = palette
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let map: [Int: NSColor] = [1: palette.body, 2: palette.dark, 3: palette.eye, 4: palette.nose]
        let offsetX = CGFloat((Int(bounds.width) - COLS * PX) / 2)
        for (row, pixels) in pixelMap.enumerated() {
            for (col, v) in pixels.enumerated() {
                guard let color = map[v] else { continue }
                color.setFill()
                NSRect(
                    x: offsetX + CGFloat(col * PX),
                    y: CGFloat((ROWS - 1 - row) * PX),  // flip Y
                    width: CGFloat(PX), height: CGFloat(PX)
                ).fill()
            }
        }
    }
}

// MARK: - Setup

let args        = CommandLine.arguments
let updated     = Int(args.count > 1 ? args[1] : "0") ?? 0
let skipped     = Int(args.count > 2 ? args[2] : "0") ?? 0
let conflicts   = Int(args.count > 3 ? args[3] : "0") ?? 0
let catName     = args.count > 4 ? args[4] : "cyan"
let palette     = palettes[catName] ?? palettes["cyan"]!

let screen      = NSScreen.main!
let screenW     = screen.frame.width
let dockClear   = screen.visibleFrame.origin.y  // 0 on hidden dock, ~82 on visible dock

let popupW: CGFloat = 270
let catAreaH        = CGFloat(ROWS * PX)
let textAreaH: CGFloat = 64
let popupH          = catAreaH + textAreaH
let winX            = screenW - popupW - 24
let yEnd: CGFloat   = dockClear + 12
let yStart: CGFloat = -popupH - 20

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // no dock icon

// MARK: - Window

let panel = NSPanel(
    contentRect: NSRect(x: winX, y: yStart, width: popupW, height: popupH),
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered, defer: false
)
panel.backgroundColor = NSColor(hex: "#12101a")
panel.isOpaque = true
panel.hasShadow = true
panel.level = .floating
panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
panel.alphaValue = 0.96

let content = panel.contentView!
content.wantsLayer = true
content.layer?.cornerRadius = 14
content.layer?.masksToBounds = true

// Cat
content.addSubview(CatView(
    frame: NSRect(x: 0, y: textAreaH, width: popupW, height: catAreaH),
    palette: palette
))

// Title
let titleLabel = NSTextField(labelWithString: "🌿 branches synced")
titleLabel.font        = .systemFont(ofSize: 13, weight: .semibold)
titleLabel.textColor   = palette.body
titleLabel.alignment   = .center
titleLabel.frame       = NSRect(x: 0, y: textAreaH - 28, width: popupW, height: 20)
content.addSubview(titleLabel)

// Summary line
var parts: [String] = []
if updated   > 0 { parts.append("✓ \(updated) updated") }
if skipped   > 0 { parts.append("~ \(skipped) already fresh") }
if conflicts > 0 { parts.append("⚠ \(conflicts) conflict\(conflicts > 1 ? "s" : "")") }
let summaryText = parts.isEmpty ? "nothing to do" : parts.joined(separator: "  ")

let summaryLabel = NSTextField(labelWithString: summaryText)
summaryLabel.font      = .systemFont(ofSize: 11)
summaryLabel.textColor = NSColor(hex: "#9988cc")
summaryLabel.alignment = .center
summaryLabel.frame     = NSRect(x: 0, y: textAreaH - 50, width: popupW, height: 18)
content.addSubview(summaryLabel)

panel.orderFront(nil)

// MARK: - Animation

func easeOutBack(_ t: Double) -> CGFloat {
    let c1 = 1.70158, c3 = c1 + 1
    return CGFloat(1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2))
}

var currentTimer: Timer?

func animateIn() {
    let duration = 0.55
    let t0 = Date()
    currentTimer = Timer.scheduledTimer(withTimeInterval: 1/60.0, repeats: true) { timer in
        let t = min(-t0.timeIntervalSinceNow / duration, 1.0)
        let y = yStart + (yEnd - yStart) * easeOutBack(t)
        panel.setFrameOrigin(NSPoint(x: winX, y: y))
        guard t >= 1.0 else { return }
        timer.invalidate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.8) { animateOut() }
    }
}

func animateOut() {
    let duration = 0.38
    let fromY = panel.frame.origin.y
    let t0 = Date()
    currentTimer = Timer.scheduledTimer(withTimeInterval: 1/60.0, repeats: true) { timer in
        let t  = min(-t0.timeIntervalSinceNow / duration, 1.0)
        let y  = fromY + (yStart - fromY) * CGFloat(t * t)
        panel.setFrameOrigin(NSPoint(x: winX, y: y))
        guard t >= 1.0 else { return }
        timer.invalidate()
        NSApp.terminate(nil)
    }
}

DispatchQueue.main.async { animateIn() }
app.run()
