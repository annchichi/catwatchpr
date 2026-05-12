#!/usr/bin/env swift

import AppKit
import Foundation

// MARK: - Helpers

extension NSColor {
    convenience init(hex: String) {
        var h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        self.init(red: CGFloat((rgb>>16)&0xFF)/255, green: CGFloat((rgb>>8)&0xFF)/255,
                  blue: CGFloat(rgb&0xFF)/255, alpha: 1)
    }
}

/// Display "owner/repo#N" for a qualified ref, or "PR #N" for a bare number (legacy).
func displayRef(_ raw: String) -> String {
    if raw.contains("#") { return raw }
    return "PR #\(raw)"
}

/// Construct GitHub PR URL from either a qualified ref ("owner/repo#N") or a bare number (legacy).
/// Bare numbers fall back to woocommerce/woocommerce — those entries are short-lived and
/// will be overwritten on the next watch tick.
func githubURL(forRef raw: String) -> URL? {
    if let hash = raw.firstIndex(of: "#") {
        let repo = raw[..<hash]
        let num  = raw[raw.index(after: hash)...]
        return URL(string: "https://github.com/\(repo)/pull/\(num)")
    }
    return URL(string: "https://github.com/woocommerce/woocommerce/pull/\(raw)")
}

// MARK: - Sprites (0=transparent, 1=body, 2=dark, 3=eye-bright, 4=nose)

typealias Sprite = [[Int]]

let sitA: Sprite = [
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
let groomA: Sprite = sitA
let groomB: Sprite = [
    [0,0,0,1,0,0,0,0,1,0,0,0],
    [0,0,1,1,1,0,0,1,1,1,0,0],
    [0,1,1,1,1,1,1,1,1,1,1,0],
    [1,1,1,1,1,1,1,1,1,1,1,1],
    [1,1,3,1,1,1,1,1,1,3,1,1],
    [1,1,2,1,1,4,1,1,1,2,1,1],
    [1,1,1,1,1,1,1,1,1,1,1,1],
    [1,1,1,1,1,0,1,1,1,1,1,1],  // paw raised
    [0,1,1,1,0,1,1,1,1,1,2,0],
    [0,0,1,1,0,0,0,1,1,0,2,0],
    [0,0,0,0,0,0,0,0,0,1,0,0],
    [0,0,0,0,0,0,0,0,0,0,0,0],
]
let walkA: Sprite = [
    [0,0,0,1,0,0,0,0,1,0,0,0],
    [0,0,1,1,1,0,0,1,1,1,0,0],
    [0,1,1,1,1,1,1,1,1,1,1,0],
    [1,1,1,1,1,1,1,1,1,1,1,1],
    [1,1,3,1,1,1,1,1,1,3,1,1],
    [1,1,2,1,1,4,1,1,1,2,1,1],
    [1,1,1,1,1,1,1,1,1,1,1,1],
    [0,1,1,1,1,1,1,1,1,1,1,0],
    [0,1,1,1,1,1,1,1,1,1,2,0],
    [0,1,1,0,0,0,0,0,0,1,2,0],
    [0,1,0,0,0,0,0,0,0,0,2,0],
    [0,0,0,0,0,0,0,0,0,1,0,0],
]
let walkB: Sprite = [
    [0,0,0,1,0,0,0,0,1,0,0,0],
    [0,0,1,1,1,0,0,1,1,1,0,0],
    [0,1,1,1,1,1,1,1,1,1,1,0],
    [1,1,1,1,1,1,1,1,1,1,1,1],
    [1,1,3,1,1,1,1,1,1,3,1,1],
    [1,1,2,1,1,4,1,1,1,2,1,1],
    [1,1,1,1,1,1,1,1,1,1,1,1],
    [0,1,1,1,1,1,1,1,1,1,1,0],
    [0,1,1,1,1,1,1,1,1,1,2,0],
    [0,0,1,1,0,0,0,1,1,0,2,0],
    [0,1,0,0,0,0,0,0,1,0,2,0],
    [0,0,0,0,0,0,0,0,0,1,0,0],
]

// MARK: - Per-cat card style

struct CardStyle {
    let bg: NSColor
    let radius: CGFloat
}

func catCardStyle(_ colorKey: String) -> CardStyle {
    switch colorKey {
    case "pink":  return CardStyle(bg: NSColor(red:0.11,green:0.06,blue:0.08,alpha:1), radius: 12)
    case "lime":  return CardStyle(bg: NSColor(red:0.06,green:0.09,blue:0.04,alpha:1), radius: 6)
    case "ghost": return CardStyle(bg: NSColor(red:0.09,green:0.07,blue:0.14,alpha:1), radius: 10)
    default:      return CardStyle(bg: NSColor(red:0.06,green:0.08,blue:0.11,alpha:1), radius: 8)
    }
}

// MARK: - Paw cursor

func makePawCursor(palette: Palette) -> NSCursor {
    let paw: [[Int]] = [
        [0,0,1,0,1,0,1,0,0],  // 4 toe tips
        [0,1,1,1,1,1,1,1,0],  // toes connected
        [0,1,1,1,1,1,1,1,0],
        [0,0,1,1,1,1,1,0,0],  // pad narrows
        [0,0,1,1,1,1,1,0,0],  // main pad
        [0,0,0,1,1,1,0,0,0],
        [0,0,0,0,0,0,0,0,0],
    ]
    let s: CGFloat = 3
    let rows = paw.count, cols = paw[0].count
    let img = NSImage(size: NSSize(width: CGFloat(cols)*s, height: CGFloat(rows)*s), flipped: false) { _ in
        palette.body.setFill()
        for (row, pixels) in paw.enumerated() {
            for (col, v) in pixels.enumerated() where v == 1 {
                NSRect(x: CGFloat(col)*s, y: CGFloat(rows-1-row)*s, width: s, height: s).fill()
            }
        }
        return true
    }
    // Hotspot: bottom-center of the pad (where the paw "touches")
    return NSCursor(image: img, hotSpot: NSPoint(x: CGFloat(cols)*s/2, y: 0))
}

// MARK: - Confetti

struct ConfettiParticle {
    var x, y, vx, vy, rot, rotSpd: CGFloat
    let color: NSColor
    let w, h: CGFloat
}

func spawnConfetti(palette: Palette, windowWidth: CGFloat, windowHeight: CGFloat) -> [ConfettiParticle] {
    let colors: [NSColor] = [palette.body, palette.eye, palette.nose,
                              .init(hex:"#ffd700"), .init(hex:"#ff6b6b"),
                              .init(hex:"#4ecdc4"), .white]
    return (0..<70).map { _ in
        ConfettiParticle(
            x: .random(in: 0...windowWidth),
            y: .random(in: windowHeight * 0.25 ... windowHeight),
            vx: .random(in: -1.2...1.2),
            vy: .random(in: -3.5 ... -0.4),
            rot: .random(in: 0...360),
            rotSpd: .random(in: -9...9),
            color: colors.randomElement()!,
            w: .random(in: 5...10),
            h: .random(in: 3...6)
        )
    }
}

// MARK: - PR Card

struct PRCard {
    let pr: String
    let msg: String
    let url: String
}

func reasonToMsg(_ reason: String, cat: String) -> String {
    switch cat {
    case "pink": // Boba — warm, excited
        switch reason {
        case "review_requested": return "👀 you got a review request!"
        case "mention":          return "💬 someone mentioned you!"
        case "comment":          return "💬 someone commented!"
        case "assign":           return "📋 you've been assigned!"
        default:                 return "💬 new activity!"
        }
    case "lime": // Matcha — minimal, no fluff
        switch reason {
        case "review_requested": return "👀 review needed"
        case "mention":          return "💬 mention"
        case "comment":          return "💬 comment"
        case "assign":           return "📋 assigned"
        default:                 return "💬 activity"
        }
    case "ghost": // Miso — soft, trailing off
        switch reason {
        case "review_requested": return "👀 review requested…"
        case "mention":          return "💬 you were mentioned…"
        case "comment":          return "💬 a new comment…"
        case "assign":           return "📋 assigned to you…"
        default:                 return "💬 new activity…"
        }
    default: // Mochi — neutral, friendly
        switch reason {
        case "review_requested": return "👀 review requested"
        case "mention":          return "💬 mentioned you"
        case "comment":          return "💬 new comment"
        case "assign":           return "📋 assigned to you"
        default:                 return "💬 new activity"
        }
    }
}

func tapHint(_ cat: String) -> String {
    switch cat {
    case "pink":  return "open it! →"
    case "lime":  return "→ open"
    case "ghost": return "open…"
    default:      return "tap to open →"
    }
}

func catEntryDuration(_ cat: String) -> Double {
    switch cat {
    case "pink":  return 0.40  // Boba: snappy
    case "lime":  return 0.32  // Matcha: crisp
    case "ghost": return 0.72  // Miso: slow float
    default:      return 0.50  // Mochi: standard
    }
}

func catEase(_ t: Double, _ cat: String) -> CGFloat {
    switch cat {
    case "pink": // Boba — extra bouncy overshoot
        let c1 = 2.8, c3 = c1 + 1
        return CGFloat(1 + c3*pow(t-1,3) + c1*pow(t-1,2))
    case "lime": // Matcha — snap in, no overshoot
        return CGFloat(1 - pow(1-t, 3))
    case "ghost": // Miso — gentle sine float
        return CGFloat(sin(t * .pi / 2))
    default: // Mochi — standard back ease
        let c1 = 1.70158, c3 = c1 + 1
        return CGFloat(1 + c3*pow(t-1,3) + c1*pow(t-1,2))
    }
}

// MARK: - State

enum CatState {
    case appearing(t: Double)
    case waiting(ticks: Int)
    case departing
}

// MARK: - Palette

struct Palette { let body, dark, eye, nose: NSColor }
let palettes: [String: Palette] = [
    "cyan":  Palette(body:.init(hex:"#00e5ff"),dark:.init(hex:"#007a99"),eye:.init(hex:"#b0f6ff"),nose:.init(hex:"#ff2d9b")),
    "lime":  Palette(body:.init(hex:"#39ff14"),dark:.init(hex:"#1f9900"),eye:.init(hex:"#c8ffb0"),nose:.init(hex:"#ffffff")),
    "pink":  Palette(body:.init(hex:"#ff2d9b"),dark:.init(hex:"#b5006b"),eye:.init(hex:"#ffb3dc"),nose:.init(hex:"#ffffff")),
    "ghost": Palette(body:.init(hex:"#d8d0f0"),dark:.init(hex:"#9988cc"),eye:.init(hex:"#ffffff"), nose:.init(hex:"#ff2d9b")),
]

// MARK: - Cat view

class CatView: NSView {
    var sprite: Sprite = sitA
    var px             = 7
    var bubbleAlpha: CGFloat = 0
    var summaryLine    = ""
    var actionLine     = ""
    var prCards: [PRCard] = []
    var cardRects: [NSRect] = []
    var greetLine: String = ""
    var celebrationMsg: String = ""
    var confettiParticles: [ConfettiParticle] = []
    var onTap: (() -> Void)?
    let palette: Palette
    private var dragStartScreen: NSPoint?
    private var didDrag = false
    private lazy var pawCursor: NSCursor = makePawCursor(palette: palette)
    var bubbleRect: NSRect?

    // Spring physics for card elastic drag feel
    var springOffsetX: CGFloat = 0
    var springOffsetY: CGFloat = 0
    var springVelX:    CGFloat = 0
    var springVelY:    CGFloat = 0

    init(frame: NSRect, palette: Palette) {
        self.palette = palette
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for rect in cardRects {
            addCursorRect(rect, cursor: pawCursor)
        }
        if let br = bubbleRect {
            addCursorRect(br, cursor: pawCursor)
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragStartScreen = NSEvent.mouseLocation
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStartScreen else { return }
        didDrag = true
        let current = NSEvent.mouseLocation
        let dx = current.x - start.x
        let dy = current.y - start.y
        if let window = self.window {
            let o = window.frame.origin
            window.setFrameOrigin(NSPoint(x: o.x + dx, y: o.y + dy))
        }
        // Cards resist the drag — pull them opposite to motion
        springOffsetX -= dx * 0.45
        springOffsetY -= dy * 0.35
        dragStartScreen = NSEvent.mouseLocation
    }

    override func mouseUp(with event: NSEvent) {
        guard !didDrag else { return }
        let pt = convert(event.locationInWindow, from: nil)
        for (i, rect) in cardRects.enumerated() {
            if i < prCards.count && rect.contains(pt) {
                if let url = URL(string: prCards[i].url) {
                    NSWorkspace.shared.open(url)
                }
                return
            }
        }
        onTap?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let colorMap: [Int: NSColor] = [1:palette.body,2:palette.dark,3:palette.eye,4:palette.nose]
        let rows = sprite.count, cols = sprite[0].count
        let catW = cols*px, catH = rows*px
        let catOX = (Int(bounds.width) - catW) / 2
        let catOY = 10

        // Shadow
        let sw = CGFloat(catW)*0.65
        NSColor.black.withAlphaComponent(0.2).setFill()
        NSBezierPath(ovalIn: NSRect(
            x: CGFloat(catOX)+(CGFloat(catW)-sw)/2, y: CGFloat(catOY)-3,
            width: sw, height: 5
        )).fill()

        // Cat pixels
        for (row, pixels) in sprite.enumerated() {
            for (col, v) in pixels.enumerated() {
                guard let c = colorMap[v] else { continue }
                c.setFill()
                NSRect(x:catOX+col*px, y:catOY+(rows-1-row)*px, width:px, height:px).fill()
            }
        }

        // Confetti
        for p in confettiParticles {
            let fadeAlpha = min(1, max(0, (p.y - 5) / 40)) * bubbleAlpha
            guard fadeAlpha > 0.01 else { continue }
            NSGraphicsContext.saveGraphicsState()
            let xf = NSAffineTransform()
            xf.translateX(by: p.x, yBy: p.y)
            xf.rotate(byDegrees: p.rot)
            xf.concat()
            p.color.withAlphaComponent(fadeAlpha).setFill()
            NSRect(x: -p.w/2, y: -p.h/2, width: p.w, height: p.h).fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        guard bubbleAlpha > 0 else { return }

        let bw: CGFloat = bounds.width - 16
        let bx: CGFloat = 8
        let contentY = CGFloat(catOY + catH) + 10

        if !prCards.isEmpty {
            // PR notification cards — each tappable directly to its PR
            let cardH: CGFloat = 52
            let cardGap: CGFloat = 6
            cardRects = []

            let displayCards = Array(prCards.prefix(3))
            for (idx, card) in displayCards.enumerated() {
                // Cards further from the cat lag more and tilt more
                let stagger: CGFloat = 1.0 + CGFloat(idx) * 0.18
                let ox  = springOffsetX * stagger
                let oy  = springOffsetY * stagger
                let rot = springOffsetX * 0.022 * stagger  // degrees

                let cy   = contentY + CGFloat(idx) * (cardH + cardGap) + oy
                let rect = NSRect(x: bx + ox, y: cy, width: bw, height: cardH)
                cardRects.append(rect)

                NSGraphicsContext.saveGraphicsState()
                let xform = NSAffineTransform()
                xform.translateX(by: rect.midX, yBy: rect.midY)
                xform.rotate(byDegrees: rot)
                xform.translateX(by: -rect.midX, yBy: -rect.midY)
                xform.concat()

                // Card background
                let style = catCardStyle(catName)
                style.bg.withAlphaComponent(bubbleAlpha*0.96).setFill()
                let bg = NSBezierPath(roundedRect: rect, xRadius: style.radius, yRadius: style.radius)
                bg.fill()
                palette.body.withAlphaComponent(bubbleAlpha*0.30).setStroke()
                bg.lineWidth = 1; bg.stroke()

                // Notification dot
                palette.body.withAlphaComponent(bubbleAlpha).setFill()
                NSBezierPath(ovalIn: NSRect(x: rect.maxX-15, y: rect.maxY-13, width: 6, height: 6)).fill()

                // PR number
                let prAttr: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 10, weight: .bold),
                    .foregroundColor: palette.body.withAlphaComponent(bubbleAlpha)
                ]
                NSAttributedString(string: displayRef(card.pr), attributes: prAttr)
                    .draw(at: NSPoint(x: rect.minX+10, y: cy+cardH-17))

                // Activity message
                let msgAttr: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor(hex:"#e0d8f0").withAlphaComponent(bubbleAlpha)
                ]
                NSAttributedString(string: card.msg, attributes: msgAttr)
                    .draw(at: NSPoint(x: rect.minX+10, y: cy+cardH-31))

                // Tap hint — white for consistent readability across all palettes
                let tapAttr: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 10),
                    .foregroundColor: NSColor(white: 1, alpha: bubbleAlpha * 0.45)
                ]
                NSAttributedString(string: tapHint(catName), attributes: tapAttr)
                    .draw(at: NSPoint(x: rect.minX+10, y: cy+8))

                NSGraphicsContext.restoreGraphicsState()
            }

            // Overflow label
            if prCards.count > 3 {
                let moreY = contentY + 3*(cardH+cardGap) + 4
                let moreAttr: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 10),
                    .foregroundColor: palette.body.withAlphaComponent(bubbleAlpha*0.6)
                ]
                NSAttributedString(string: "+\(prCards.count-3) more — check GitHub →", attributes: moreAttr)
                    .draw(at: NSPoint(x: bx+10, y: moreY))
            }
            window?.invalidateCursorRects(for: self)

        } else {
            // Speech bubble (sync mode: conflicts, reviews, etc.)
            let hasAction   = !actionLine.isEmpty
            let actionLines = actionLine.components(separatedBy:"\n").count
            let greetFont   = NSFont.systemFont(ofSize: 12, weight: .medium)
            // Reserve 10px padding on each side of the bubble for text.
            let textWidth   = bw - 20
            let bh: CGFloat
            if !greetLine.isEmpty {
                // Measure with the actual text width so multi-line wrapping
                // (long owner/repo#N messages) sets the bubble height correctly.
                let measured = NSAttributedString(string: greetLine, attributes: [.font: greetFont])
                    .boundingRect(with: NSSize(width: textWidth, height: 200), options: .usesLineFragmentOrigin)
                bh = ceil(measured.height) + 24
            } else if !celebrationMsg.isEmpty {
                let measured = NSAttributedString(string: celebrationMsg, attributes: [.font: greetFont])
                    .boundingRect(with: NSSize(width: textWidth, height: 200), options: .usesLineFragmentOrigin)
                bh = ceil(measured.height) + 24
            } else {
                bh = hasAction ? CGFloat(38 + actionLines * 18) : 38
            }
            let by          = contentY - 2

            bubbleRect = NSRect(x:bx, y:by, width:bw, height:bh)
            window?.invalidateCursorRects(for: self)
            let style = catCardStyle(catName)
            style.bg.withAlphaComponent(bubbleAlpha*0.96).setFill()
            let bg = NSBezierPath(roundedRect: NSRect(x:bx,y:by,width:bw,height:bh), xRadius:10, yRadius:10)
            bg.fill()
            palette.body.withAlphaComponent(bubbleAlpha*0.2).setStroke()
            bg.lineWidth = 1; bg.stroke()

            let tri = NSBezierPath()
            let mx = bx + bw/2
            tri.move(to:NSPoint(x:mx-5,y:by)); tri.line(to:NSPoint(x:mx+5,y:by))
            tri.line(to:NSPoint(x:mx,y:by-5)); tri.close()
            style.bg.withAlphaComponent(bubbleAlpha*0.96).setFill()
            tri.fill()

            if !celebrationMsg.isEmpty {
                let a: [NSAttributedString.Key:Any] = [
                    .font: greetFont,
                    .foregroundColor: NSColor(hex:"#ffd700").withAlphaComponent(bubbleAlpha)
                ]
                // draw(with:options:) wraps within the rect — multi-line text fits
                // inside the bubble instead of overflowing horizontally.
                NSAttributedString(string:celebrationMsg,attributes:a)
                    .draw(with: NSRect(x: bx+10, y: by+10, width: textWidth, height: bh-20),
                          options: .usesLineFragmentOrigin)
            } else if !greetLine.isEmpty {
                let a: [NSAttributedString.Key:Any] = [
                    .font: greetFont,
                    .foregroundColor: palette.body.withAlphaComponent(bubbleAlpha)
                ]
                NSAttributedString(string:greetLine,attributes:a)
                    .draw(with: NSRect(x: bx+10, y: by+10, width: textWidth, height: bh-20),
                          options: .usesLineFragmentOrigin)
            } else {
                if !summaryLine.isEmpty {
                    let a: [NSAttributedString.Key:Any] = [
                        .font: NSFont.systemFont(ofSize:11),
                        .foregroundColor: NSColor(hex:"#34d399").withAlphaComponent(bubbleAlpha)
                    ]
                    NSAttributedString(string:summaryLine,attributes:a).draw(at:NSPoint(x:bx+10,y:by+bh-18))
                }
                if hasAction {
                    let a: [NSAttributedString.Key:Any] = [
                        .font: NSFont.systemFont(ofSize:11),
                        .foregroundColor: NSColor(hex:"#fb923c").withAlphaComponent(bubbleAlpha)
                    ]
                    let lines = actionLine.components(separatedBy:"\n")
                    for (i, line) in lines.enumerated() {
                        NSAttributedString(string:line,attributes:a)
                            .draw(at:NSPoint(x:bx+10, y:by+bh-36-CGFloat(i)*16))
                    }
                }
            }
        }
    }
}

// MARK: - Args

let cmdArgs       = CommandLine.arguments
let updated       = Int(cmdArgs.count > 1 ? cmdArgs[1] : "0") ?? 0
let skipped       = Int(cmdArgs.count > 2 ? cmdArgs[2] : "0") ?? 0
let conflicts     = Int(cmdArgs.count > 3 ? cmdArgs[3] : "0") ?? 0
let catName       = cmdArgs.count > 4 ? cmdArgs[4] : "cyan"
let activePRsRaw  = cmdArgs.count > 5
    ? cmdArgs[5].split(separator:",").map(String.init).filter{!$0.isEmpty}
    : [String]()
let notifReviews  = Int(cmdArgs.count > 6 ? cmdArgs[6] : "0") ?? 0
let notifMentions = Int(cmdArgs.count > 7 ? cmdArgs[7] : "0") ?? 0
let notifAssigns  = Int(cmdArgs.count > 8 ? cmdArgs[8] : "0") ?? 0
let prActivity    = Int(cmdArgs.count > 9 ? cmdArgs[9] : "0") ?? 0
let greetMsg      = cmdArgs.count > 10
    ? cmdArgs[10].components(separatedBy:.whitespacesAndNewlines).filter{!$0.isEmpty}.joined(separator:" ")
    : ""
let mergedPRsRaw  = cmdArgs.count > 11
    ? cmdArgs[11].split(separator:",").map(String.init).filter{!$0.isEmpty}
    : [String]()
let isCelebrating = !mergedPRsRaw.isEmpty
let palette       = palettes[catName] ?? palettes["cyan"]!

// Parse "ref:reason" pairs — only when watch.sh signals activity (prActivity > 0)
// ref is either a qualified "owner/repo#N" (v0.2.0) or a bare number (v0.1.x legacy)
let prCards: [PRCard] = prActivity > 0 ? activePRsRaw.compactMap { item in
    let parts = item.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
    guard !parts.isEmpty else { return nil }
    let ref   = parts[0]
    guard !ref.isEmpty else { return nil }
    let reason = parts.count > 1 ? parts[1] : "subscribed"
    return PRCard(
        pr:  ref,
        msg: reasonToMsg(reason, cat: catName),
        url: githubURL(forRef: ref)?.absoluteString ?? ""
    )
} : []

// MARK: - Layout

let screen = NSScreen.main!
let sw = screen.frame.width, sh = screen.frame.height
let visY = screen.visibleFrame.origin.y

let WW: CGFloat = 380
let cardCount = min(prCards.count, 3)
let WH: CGFloat = isCelebrating
    ? sh - visY - 60 - 30
    : (prCards.isEmpty ? 165 : CGFloat(114 + cardCount * 58 + (prCards.count > 3 ? 20 : 0)))
let winX = sw - WW - 24

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let panel = NSPanel(
    contentRect: NSRect(x:winX, y:-WH-10, width:WW, height:WH),
    styleMask: [.borderless,.nonactivatingPanel], backing:.buffered, defer:false
)
panel.backgroundColor = .clear
panel.isOpaque = false; panel.hasShadow = false
panel.level = .floating
panel.collectionBehavior = [.canJoinAllSpaces,.stationary]
panel.acceptsMouseMovedEvents = true

let catView = CatView(frame:NSRect(x:0,y:0,width:WW,height:WH), palette:palette)
catView.prCards = prCards
panel.contentView = catView
panel.orderFront(nil)

// MARK: - Bubble content (sync mode only)

if isCelebrating {
    let names = mergedPRsRaw.map{ displayRef($0) }.joined(separator:", ")
    catView.celebrationMsg = "🎉 PR \(names) merged! Congrats!"
    catView.confettiParticles = spawnConfetti(palette: palette, windowWidth: WW, windowHeight: WH)
} else if !greetMsg.isEmpty {
    catView.greetLine = greetMsg
} else {
    var goodParts: [String] = []
    if updated > 0 { goodParts.append("✓ \(updated) synced") }
    if skipped > 0 { goodParts.append("~ \(skipped) fresh") }
    catView.summaryLine = goodParts.joined(separator:"  ")

    var actionParts: [String] = []
    if conflicts > 0     { actionParts.append("⚠ \(conflicts) conflict\(conflicts>1 ? "s":"") — tap") }
    if notifReviews > 0  { actionParts.append("👀 \(notifReviews) review\(notifReviews>1 ? "s":"") requested") }
    if notifMentions > 0 { actionParts.append("💬 mentioned \(notifMentions)×") }
    if notifAssigns > 0  { actionParts.append("📋 assigned") }
    catView.actionLine = actionParts.joined(separator:"\n")
}

catView.onTap = {
    let urlStr: String
    if isCelebrating {
        urlStr = mergedPRsRaw.count == 1
            ? (githubURL(forRef: mergedPRsRaw[0])?.absoluteString
                ?? "https://github.com/pulls?q=is:pr+author:%40me+is:merged")
            : "https://github.com/pulls?q=is:pr+author:%40me+is:merged"
    } else if !greetMsg.isEmpty {
        // Try to route to the specific PR mentioned in CI / activity messages
        // (e.g. "✅ PR owner/repo#N is clear to merge!"). Fall back to your
        // global open PRs page if the message has no qualified ref.
        let refPattern = try? NSRegularExpression(
            pattern: #"[A-Za-z0-9_.\-]+/[A-Za-z0-9_.\-]+#[0-9]+"#)
        if let regex = refPattern,
           let match = regex.firstMatch(in: greetMsg,
                                         range: NSRange(greetMsg.startIndex..., in: greetMsg)),
           let refRange = Range(match.range, in: greetMsg),
           let url = githubURL(forRef: String(greetMsg[refRange])) {
            urlStr = url.absoluteString
        } else {
            urlStr = "https://github.com/pulls?q=is:pr+author:%40me+is:open"
        }
    } else {
        urlStr = "https://github.com/notifications"
    }
    if let url = URL(string: urlStr) { NSWorkspace.shared.open(url) }
}

// MARK: - State & loop

var catState: CatState  = .appearing(t: 0)
var catY: CGFloat       = -WH - 10
var departX: CGFloat    = winX
var totalTicks          = 0
var frameTick           = 0
var frameOn             = false
let hasAction           = !catView.actionLine.isEmpty || !prCards.isEmpty
let waitTicks           = hasAction ? 2400 : 1200
var bubbleTick          = 0

Timer.scheduledTimer(withTimeInterval:1.0/60.0, repeats:true) { _ in
    totalTicks += 1; frameTick += 1
    if frameTick >= 18 { frameTick=0; frameOn = !frameOn }

    // Confetti physics
    for i in catView.confettiParticles.indices {
        catView.confettiParticles[i].vy -= 0.10
        catView.confettiParticles[i].x  += catView.confettiParticles[i].vx
        catView.confettiParticles[i].y  += catView.confettiParticles[i].vy
        catView.confettiParticles[i].rot += catView.confettiParticles[i].rotSpd
    }

    // Spring physics — pull cards back toward rest position each frame
    let springK: CGFloat = 0.13
    let damping: CGFloat = 0.72
    catView.springVelX += (0 - catView.springOffsetX) * springK
    catView.springVelY += (0 - catView.springOffsetY) * springK
    catView.springVelX *= damping
    catView.springVelY *= damping
    catView.springOffsetX += catView.springVelX
    catView.springOffsetY += catView.springVelY

    bubbleTick += 1
    switch bubbleTick {
    case ..<30:                        catView.bubbleAlpha = CGFloat(bubbleTick)/30
    case 30..<(waitTicks-60):          catView.bubbleAlpha = 1
    case (waitTicks-60)..<waitTicks:   catView.bubbleAlpha = CGFloat(waitTicks-bubbleTick)/60
    default:                           catView.bubbleAlpha = 0
    }

    switch catState {

    case .appearing(let t):
        let newT = min(t + (1.0/60.0)/catEntryDuration(catName), 1.0)
        catY = (-WH-10) + (visY+60 - (-WH-10)) * catEase(newT, catName)
        catView.sprite = sitA; catView.px = 7
        catState = newT >= 1.0 ? .waiting(ticks: waitTicks) : .appearing(t: newT)
        panel.setFrameOrigin(NSPoint(x:winX, y:catY))

    case .waiting(let ticks):
        catView.sprite = (frameOn && totalTicks % 180 < 90) ? groomB : sitA
        catView.px = 7
        if ticks <= 0 {
            departX = panel.frame.origin.x
            catY    = panel.frame.origin.y
            catState = .departing
        } else {
            catState = .waiting(ticks: ticks-1)
        }
        // No setFrameOrigin here — user can drag freely

    case .departing:
        departX += 2.0
        catView.sprite = frameOn ? walkB : walkA; catView.px = 7
        if departX > sw+20 { NSApp.terminate(nil) }
        panel.setFrameOrigin(NSPoint(x:departX, y:catY))
    }

    catView.needsDisplay = true
}

app.run()
