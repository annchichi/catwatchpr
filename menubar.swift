#!/usr/bin/env swift

import AppKit
import Foundation

// MARK: - Helpers

extension NSColor {
    convenience init(hex: String) {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        self.init(red: CGFloat((rgb>>16)&0xFF)/255, green: CGFloat((rgb>>8)&0xFF)/255,
                  blue: CGFloat(rgb&0xFF)/255, alpha: 1)
    }
}

// MARK: - Sprite & Palette

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

struct Palette { let body, dark, eye, nose: NSColor }
let palettes: [String: Palette] = [
    "cyan":  Palette(body:.init(hex:"#00e5ff"),dark:.init(hex:"#007a99"),eye:.init(hex:"#b0f6ff"),nose:.init(hex:"#ff2d9b")),
    "lime":  Palette(body:.init(hex:"#39ff14"),dark:.init(hex:"#1f9900"),eye:.init(hex:"#c8ffb0"),nose:.init(hex:"#ffffff")),
    "pink":  Palette(body:.init(hex:"#ff2d9b"),dark:.init(hex:"#b5006b"),eye:.init(hex:"#ffb3dc"),nose:.init(hex:"#ffffff")),
    "ghost": Palette(body:.init(hex:"#d8d0f0"),dark:.init(hex:"#9988cc"),eye:.init(hex:"#ffffff"), nose:.init(hex:"#ff2d9b")),
]

let cats: [(name: String, color: String)] = [
    ("Mochi",  "cyan"),
    ("Boba",   "pink"),
    ("Matcha", "lime"),
    ("Miso",   "ghost"),
]

// MARK: - Icon

func makeCatIcon(palette: Palette, dot: Bool) -> NSImage {
    let scale: CGFloat = 1.5
    let rows = sitA.count, cols = sitA[0].count
    let w = CGFloat(cols)*scale, h = CGFloat(rows)*scale
    let colorMap: [Int: NSColor] = [1:palette.body, 2:palette.dark, 3:palette.eye, 4:palette.nose]

    return NSImage(size: NSSize(width: w, height: h), flipped: false) { _ in
        for (row, pixels) in sitA.enumerated() {
            for (col, v) in pixels.enumerated() {
                guard let c = colorMap[v] else { continue }
                c.setFill()
                NSRect(x: CGFloat(col)*scale, y: CGFloat(rows-1-row)*scale,
                       width: scale, height: scale).fill()
            }
        }
        if dot {
            NSColor(hex:"#ff2d9b").setFill()
            NSBezierPath(ovalIn: NSRect(x: w-5.5, y: 1, width: 5, height: 5)).fill()
        }
        return true
    }
}

// MARK: - Config helpers

let configDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/woo-sprinkles")

func currentCatColor() -> String {
    let file = configDir.appendingPathComponent("cat_color")
    return (try? String(contentsOf: file, encoding: .utf8))?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "cyan"
}

func currentCatName() -> String {
    let file = configDir.appendingPathComponent("cat_name")
    return (try? String(contentsOf: file, encoding: .utf8))?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "mochi"
}

func pendingCount() -> Int {
    let file = configDir.appendingPathComponent("pending_count")
    return Int((try? String(contentsOf: file, encoding: .utf8))?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "0") ?? 0
}

func lastCheckedLabel() -> String {
    let file = configDir.appendingPathComponent("last_checked")
    guard let ts = Double((try? String(contentsOf: file, encoding: .utf8))?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "") else {
        return "Not checked yet"
    }
    let mins = Int(Date().timeIntervalSince1970 - ts) / 60
    if mins < 1  { return "Checked just now" }
    if mins == 1 { return "Checked 1 min ago" }
    return "Checked \(mins) mins ago"
}

func inboxNotifs() -> [(pr: String, reason: String)] {
    let file = configDir.appendingPathComponent("inbox")
    guard let content = try? String(contentsOf: file, encoding: .utf8) else { return [] }
    return content.split(separator: "\n").compactMap { line in
        let s = String(line).trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        let parts = s.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                     .map(String.init)
        guard let pr = parts.first?.trimmingCharacters(in: .whitespaces),
              !pr.isEmpty,
              pr.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        let reason = parts.count > 1
            ? parts[1].trimmingCharacters(in: .whitespaces)
            : "subscribed"
        return (pr: pr, reason: reason.isEmpty ? "subscribed" : reason)
    }
}

func removePRFromInbox(_ pr: String) {
    let file = configDir.appendingPathComponent("inbox")
    guard let content = try? String(contentsOf: file, encoding: .utf8) else { return }
    let updated = content.split(separator: "\n")
        .filter { !String($0).hasPrefix("\(pr):") }
        .joined(separator: "\n")
    try? updated.write(to: file, atomically: true, encoding: .utf8)
}

func reasonLabel(_ reason: String) -> String {
    switch reason {
    case "review_requested": return "👀 review requested"
    case "mention":          return "💬 mentioned you"
    case "comment":          return "💬 new comment"
    case "assign":           return "📋 assigned to you"
    case "ci_pass":          return "✅ clear to merge"
    case "ci_fail":          return "❌ checks failing"
    default:                 return "🔔 new activity"
    }
}

// MARK: - Actions

class Actions: NSObject {
    @objc func openGitHub(_ sender: Any) {
        NSWorkspace.shared.open(URL(string: "https://github.com/notifications")!)
    }
    @objc func openPR(_ sender: NSMenuItem) {
        guard let urlStr = sender.representedObject as? String,
              let url = URL(string: urlStr) else { return }
        let pr = url.lastPathComponent
        removePRFromInbox(pr)
        NSWorkspace.shared.open(url)
        updateIcon()
    }
    @objc func switchCat(_ sender: NSMenuItem) {
        guard let color = sender.representedObject as? String else { return }
        let name = cats.first { $0.color == color }?.name.lowercased() ?? color
        try? color.write(to: configDir.appendingPathComponent("cat_color"),
                         atomically: true, encoding: .utf8)
        try? name.write(to: configDir.appendingPathComponent("cat_name"),
                        atomically: true, encoding: .utf8)
        updateIcon()
    }
}
let actions = Actions()

// MARK: - App

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let statusItem = NSStatusBar.system.statusItem(withLength: 22)
statusItem.isVisible = true

func buildMenu() -> NSMenu {
    let menu = NSMenu()

    // Status line
    let checkedItem = NSMenuItem(title: lastCheckedLabel(), action: nil, keyEquivalent: "")
    checkedItem.isEnabled = false
    menu.addItem(checkedItem)
    menu.addItem(.separator())

    // Persistent inbox — stays until user clicks through
    let notifs = inboxNotifs()
    if notifs.isEmpty {
        let noneItem = NSMenuItem(title: "No pending notifications", action: nil, keyEquivalent: "")
        noneItem.isEnabled = false
        menu.addItem(noneItem)
    } else {
        for (pr, reason) in notifs {
            let item = NSMenuItem(
                title: "PR #\(pr)  \(reasonLabel(reason))",
                action: #selector(Actions.openPR(_:)),
                keyEquivalent: ""
            )
            item.target = actions
            item.representedObject = "https://github.com/woocommerce/woocommerce/pull/\(pr)"
            menu.addItem(item)
        }
    }

    menu.addItem(.separator())

    // Switch cat submenu
    let switchItem = NSMenuItem(title: "Switch cat", action: nil, keyEquivalent: "")
    let switchMenu = NSMenu()
    let activeCatColor = currentCatColor()
    for cat in cats {
        let item = NSMenuItem(
            title: cat.name,
            action: #selector(Actions.switchCat(_:)),
            keyEquivalent: ""
        )
        item.target = actions
        item.representedObject = cat.color
        if cat.color == activeCatColor { item.state = .on }
        switchMenu.addItem(item)
    }
    switchItem.submenu = switchMenu
    menu.addItem(switchItem)

    menu.addItem(.separator())
    let openItem = NSMenuItem(title: "Open all notifications",
                               action: #selector(Actions.openGitHub(_:)),
                               keyEquivalent: "")
    openItem.target = actions
    menu.addItem(openItem)
    menu.addItem(.separator())
    menu.addItem(NSMenuItem(title: "Quit CatWatchPR",
                             action: #selector(NSApplication.terminate(_:)),
                             keyEquivalent: "q"))
    return menu
}

func updateIcon() {
    let count   = inboxNotifs().count
    let palette = palettes[currentCatColor()] ?? palettes["cyan"]!
    statusItem.menu = buildMenu()
    if let btn = statusItem.button {
        btn.image = makeCatIcon(palette: palette, dot: count > 0)
        btn.toolTip = count > 0
            ? "\(count) PR notification\(count > 1 ? "s" : "") — click to see"
            : "CatWatchPR — watching your PRs"
    }
}

DispatchQueue.main.async { updateIcon() }
Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in updateIcon() }

app.run()
