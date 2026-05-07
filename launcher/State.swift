// launcher/State.swift
// Reads runtime state of CatWatchPR (which agents are loaded, last check time,
// active cat, recent crash info). All subprocess and disk work runs on a
// background queue; only the @Published mutation runs on the main actor.
import Foundation
import Combine

enum AgentStatus { case running, scheduled, stopped, crashed(String) }

struct AppStatus: Sendable {
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

extension AgentStatus: Sendable {}

private let CONFIG_DIR_PATH = ".config/woo-sprinkles"
private let AGENTS_DIR_PATH = "Library/LaunchAgents"
private let LABELS = [
    "com.annchiahui.woo-sprinkles.menubar",
    "com.annchiahui.woo-sprinkles.watch",
    "com.annchiahui.woo-sprinkles.sync",
]

@MainActor
final class AppState: ObservableObject {
    @Published var status = AppStatus()
    private var timer: Timer?

    nonisolated private static var configDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(CONFIG_DIR_PATH)
    }
    nonisolated private static var agentsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(AGENTS_DIR_PATH)
    }

    func startPolling() {
        Task { await refresh() }
        // 5-second interval: balances responsiveness with subprocess cost.
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func stopPolling() { timer?.invalidate(); timer = nil }

    /// Public entry point for views that want to force a re-read after writing
    /// state (e.g. CatPickerView after writing cat_name). Fire-and-forget.
    func refresh() {
        Task { await refresh() }
    }

    /// Compute status on a background thread, then publish on the main actor.
    private func refresh() async {
        let newStatus = await Task.detached(priority: .userInitiated) {
            return AppState.computeStatus()
        }.value
        self.status = newStatus
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath:
            Self.agentsDir.appendingPathComponent(
                "com.annchiahui.woo-sprinkles.menubar.plist").path)
    }

    var hasRepoConfig: Bool {
        guard let r = Self.readConfigFile("repo") else { return false }
        return !r.isEmpty
    }

    /// Pure background computation. No @MainActor, no @Published access.
    nonisolated static func computeStatus() -> AppStatus {
        var s = AppStatus()
        s.catName  = readConfigFile("cat_name")  ?? "mochi"
        s.catColor = readConfigFile("cat_color") ?? "cyan"
        s.repo     = readConfigFile("repo")      ?? ""
        s.openPRs  = readConfigFile("prev_open_prs")?
            .split(separator: " ").count ?? 0
        s.lastChecked = lastCheckedLabel()

        // One launchctl list call; parse output for all our labels at once.
        let loaded = loadedAgentLabels()
        let menubarCrash = recentFatalError(
            in: "/tmp/woo-sprinkles-menubar.err")

        s.menubar = agentStatus(
            label: "com.annchiahui.woo-sprinkles.menubar",
            loaded: loaded, crash: menubarCrash)
        s.watch = agentStatus(
            label: "com.annchiahui.woo-sprinkles.watch",
            loaded: loaded, crash: nil)
        s.sync = agentStatus(
            label: "com.annchiahui.woo-sprinkles.sync",
            loaded: loaded, crash: nil)
        if case .crashed(let msg) = s.menubar { s.crashExcerpt = msg }
        return s
    }

    nonisolated private static func readConfigFile(_ name: String) -> String? {
        let url = configDir.appendingPathComponent(name)
        guard let s = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    nonisolated private static func lastCheckedLabel() -> String {
        guard let raw = readConfigFile("last_checked"),
              let ts = Double(raw) else { return "never" }
        let mins = Int(Date().timeIntervalSince1970 - ts) / 60
        if mins < 1 { return "just now" }
        if mins == 1 { return "1 min ago" }
        if mins < 60 { return "\(mins) mins ago" }
        return "\(mins / 60)h ago"
    }

    nonisolated private static func agentStatus(
        label: String, loaded: Set<String>, crash: String?
    ) -> AgentStatus {
        let plistExists = FileManager.default.fileExists(atPath:
            agentsDir.appendingPathComponent("\(label).plist").path)
        guard plistExists else { return .stopped }
        if let crash { return .crashed(crash) }
        return loaded.contains(label) ? .running : .scheduled
    }

    /// Single `launchctl list` call (no label filter), parsed for our labels.
    /// Output format is "PID\tStatus\tLabel" with a header row.
    nonisolated private static func loadedAgentLabels() -> Set<String> {
        let p = Process()
        p.launchPath = "/bin/launchctl"
        p.arguments = ["list"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        guard let data = try? pipe.fileHandleForReading.readToEnd(),
              let output = String(data: data, encoding: .utf8) else { return [] }
        var found = Set<String>()
        for raw in output.split(separator: "\n") {
            let parts = raw.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 3 else { continue }
            let label = String(parts[2])
            if LABELS.contains(label) { found.insert(label) }
        }
        return found
    }

    /// Returns the most recent Fatal error line if it appeared in the last 60s.
    nonisolated private static func recentFatalError(in path: String) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < 60,
              let data = try? String(contentsOfFile: path, encoding: .utf8)
        else { return nil }
        let lines = data.split(separator: "\n").map(String.init)
        return lines.last(where: { $0.contains("Fatal error") })
    }
}

enum WizardStep: Int, CaseIterable {
    case welcome, authCheck, repoPicker, install, catPicker, allDone
}

@MainActor
final class WizardState: ObservableObject {
    @Published var step: WizardStep = .welcome
    @Published var ghAuthed: Bool = false
    @Published var repo: String = ""
    @Published var installError: String? = nil
    @Published var installing: Bool = false
    @Published var isFinished: Bool = false  // true after cat picker

    /// Find `gh` on disk. Mac .app processes don't inherit the user's shell PATH,
    /// so `/usr/bin/env gh` can fail even when gh is installed. Try common
    /// Homebrew locations explicitly.
    nonisolated static func findGH() -> String? {
        let candidates = [
            "/usr/local/bin/gh",      // Intel Homebrew
            "/opt/homebrew/bin/gh",   // Apple Silicon Homebrew
            "/usr/bin/gh",            // (rare, but cheap to check)
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Run `gh auth status` in the background; publish result on main.
    func checkAuth() {
        Task {
            let ok = await Task.detached(priority: .userInitiated) {
                guard let ghPath = WizardState.findGH() else { return false }
                let p = Process()
                p.launchPath = ghPath
                // Scope to github.com — `gh auth status` exits 1 if ANY host
                // (including Automattic's github.a8c.com) is unreachable, even
                // when github.com is fine.
                p.arguments = ["auth", "status", "--hostname", "github.com"]
                p.standardOutput = Pipe()
                p.standardError  = Pipe()
                try? p.run()
                p.waitUntilExit()
                return p.terminationStatus == 0
            }.value
            self.ghAuthed = ok
        }
    }

    /// Try to suggest a sensible default repo: first repo in the user's gh list.
    func suggestRepo() {
        Task {
            let suggestion = await Task.detached(priority: .userInitiated) { () -> String? in
                guard let ghPath = WizardState.findGH() else { return nil }
                let p = Process()
                p.launchPath = ghPath
                p.arguments = ["repo", "list", "--limit", "1",
                               "--json", "nameWithOwner", "--jq", ".[0].nameWithOwner"]
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError  = Pipe()
                try? p.run()
                p.waitUntilExit()
                guard p.terminationStatus == 0,
                      let data = try? pipe.fileHandleForReading.readToEnd(),
                      let s = String(data: data, encoding: .utf8) else { return nil }
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : t
            }.value
            if let suggestion, repo.isEmpty {
                self.repo = suggestion
            }
        }
    }

    static let repoRegex = #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"#

    var repoIsValid: Bool {
        repo.range(of: Self.repoRegex, options: .regularExpression) != nil
    }
}
