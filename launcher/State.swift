// launcher/State.swift
// Reads runtime state of CatWatchPR (which agents are loaded, last check time,
// active cat, recent crash info). Pure file/launchctl reads — no UI.
import Foundation
import Combine

enum AgentStatus { case running, scheduled, stopped, crashed(String) }

struct AppStatus {
    var menubar:      AgentStatus = .stopped
    var watch:        AgentStatus = .stopped
    var sync:         AgentStatus = .stopped
    var lastChecked:  String = "never"
    var openPRs:      Int = 0
    var catName:      String = "mochi"
    var catColor:     String = "cyan"
    var repo:         String = ""
    var crashExcerpt: String? = nil  // most recent Fatal error line, if any
}

@MainActor
final class AppState: ObservableObject {
    @Published var status = AppStatus()
    private var timer: Timer?

    private let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/woo-sprinkles")
    private let agentsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents")

    func startPolling() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopPolling() { timer?.invalidate(); timer = nil }

    func refresh() {
        var s = AppStatus()
        s.catName  = readFile("cat_name")  ?? "mochi"
        s.catColor = readFile("cat_color") ?? "cyan"
        s.repo     = readFile("repo")      ?? ""
        s.openPRs  = readFile("prev_open_prs")?
            .split(separator: " ").count ?? 0
        s.lastChecked = lastCheckedLabel()

        s.menubar = agentStatus("com.annchiahui.woo-sprinkles.menubar",
                                stderrPath: "/tmp/woo-sprinkles-menubar.err")
        s.watch   = agentStatus("com.annchiahui.woo-sprinkles.watch", stderrPath: nil)
        s.sync    = agentStatus("com.annchiahui.woo-sprinkles.sync",  stderrPath: nil)
        if case .crashed(let msg) = s.menubar { s.crashExcerpt = msg }

        status = s
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath:
            agentsDir.appendingPathComponent(
                "com.annchiahui.woo-sprinkles.menubar.plist").path)
    }

    var hasRepoConfig: Bool {
        guard let r = readFile("repo") else { return false }
        return !r.isEmpty
    }

    private func readFile(_ name: String) -> String? {
        let url = configDir.appendingPathComponent(name)
        guard let s = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private func lastCheckedLabel() -> String {
        guard let raw = readFile("last_checked"),
              let ts = Double(raw) else { return "never" }
        let mins = Int(Date().timeIntervalSince1970 - ts) / 60
        if mins < 1 { return "just now" }
        if mins == 1 { return "1 min ago" }
        if mins < 60 { return "\(mins) mins ago" }
        return "\(mins / 60)h ago"
    }

    /// Determine an agent's status. `stderrPath` is checked for recent Fatal errors.
    private func agentStatus(_ label: String, stderrPath: String?) -> AgentStatus {
        let plistExists = FileManager.default.fileExists(atPath:
            agentsDir.appendingPathComponent("\(label).plist").path)
        guard plistExists else { return .stopped }

        if let err = stderrPath, let crash = recentFatalError(in: err) {
            return .crashed(crash)
        }

        let listed = launchctlList(label)
        return listed ? .running : .scheduled
    }

    private func launchctlList(_ label: String) -> Bool {
        let p = Process()
        p.launchPath = "/bin/launchctl"
        p.arguments = ["list", label]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    /// Returns the most recent Fatal error line if it appeared in the last 60s.
    private func recentFatalError(in path: String) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < 60,
              let data = try? String(contentsOfFile: path, encoding: .utf8)
        else { return nil }
        let lines = data.split(separator: "\n").map(String.init)
        return lines.last(where: { $0.contains("Fatal error") })
    }
}
