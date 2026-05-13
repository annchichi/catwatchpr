// launcher/activity/ActivityWindow.swift
import SwiftUI
import AppKit

struct ActivityView: View {
    @State private var lines: [String] = []
    @State private var timer: Timer?
    var body: some View {
        ZStack {
            // Background fills the whole frame regardless of content height.
            CatStyle.bg.ignoresSafeArea()

            if lines.isEmpty {
                VStack(spacing: 6) {
                    Text("no activity yet")
                        .font(CatStyle.monoSmall)
                        .foregroundColor(CatStyle.dim)
                    Text("your watch is running. check back after the next tick.")
                        .font(CatStyle.monoTiny)
                        .foregroundColor(CatStyle.dim)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(CatStyle.monoSmall)
                                .foregroundColor(color(for: line))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(minWidth: 540, minHeight: 360)
        .onAppear {
            refresh()
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                refresh()
            }
        }
        .onDisappear { timer?.invalidate() }
    }

    private func color(for line: String) -> Color {
        if line.contains("[menubar]") { return CatStyle.cyan }
        if line.contains("[watch]")   { return CatStyle.green }
        if line.contains("[sync]")    { return Color(red:1.0, green:0.7, blue:0.3) }
        return CatStyle.text
    }

    private func refresh() {
        var collected: [(line: String, source: String)] = []
        let files = [
            ("watch",   "/tmp/woo-sprinkles-watch.log"),
            ("watch",   "/tmp/woo-sprinkles-watch.err"),
            ("sync",    "/tmp/woo-sprinkles-sync.log"),
            ("sync",    "/tmp/woo-sprinkles-sync.err"),
            ("menubar", "/tmp/woo-sprinkles-menubar.log"),
            ("menubar", "/tmp/woo-sprinkles-menubar.err"),
        ]
        for (src, path) in files {
            guard let s = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            for raw in s.split(separator: "\n").map(String.init) {
                guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                collected.append((line: "[\(src)] \(raw)", source: src))
            }
        }
        // Last 200 lines.
        let tail = Array(collected.suffix(200))
        lines = tail.map(\.line)
    }
}

@MainActor
final class ActivityWindowController {
    static let shared = ActivityWindowController()
    private var window: NSWindow?

    func show() {
        if let w = window { w.makeKeyAndOrderFront(nil); return }
        let host = NSHostingController(rootView: ActivityView())
        let w = NSWindow(contentViewController: host)
        w.title = "CatWatchPR — Activity"
        w.styleMask = [.titled, .closable, .resizable]
        w.setContentSize(NSSize(width: 600, height: 400))
        w.isReleasedWhenClosed = false
        w.center()
        w.makeKeyAndOrderFront(nil)
        window = w
    }
}
