// launcher/Install.swift
// Install / uninstall logic for CatWatchPR. Writes plists into
// ~/Library/LaunchAgents/ with __BUNDLE_PATH__ substituted, runs launchctl
// load/unload, and (for "Reset everything") wipes ~/.config/woo-sprinkles.
//
// CLI mode: `CatWatchPR install` / `uninstall` / `reset` so
// integration tests can exercise this path without a UI.
import Foundation

enum InstallError: Error, LocalizedError {
    case missingTemplate(String)
    case launchctlFailed(String)
    var errorDescription: String? {
        switch self {
        case .missingTemplate(let s): return "Missing plist template: \(s)"
        case .launchctlFailed(let s): return "launchctl failed: \(s)"
        }
    }
}

struct Installer {
    static let labels = [
        "com.annchiahui.woo-sprinkles.menubar",
        "com.annchiahui.woo-sprinkles.watch",
        "com.annchiahui.woo-sprinkles.sync",
    ]

    let bundlePath: String
    // Read HOME from the environment so CLI tests can override it with a temp dir.
    let homeDir: URL = {
        if let h = ProcessInfo.processInfo.environment["HOME"] {
            return URL(fileURLWithPath: h)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }()

    var configDir: URL { homeDir.appendingPathComponent(".config/woo-sprinkles") }
    var agentsDir: URL { homeDir.appendingPathComponent("Library/LaunchAgents") }
    var templatesDir: String { "\(bundlePath)/Contents/Resources/launchd" }

    /// Copies plists with substitution and loads agents. v0.2.0 watches all
    /// involved PRs globally, so no per-user repo configuration is written.
    func install() throws {
        try FileManager.default.createDirectory(at: configDir,
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: agentsDir,
                                                withIntermediateDirectories: true)
        for label in Self.labels {
            let template = "\(templatesDir)/\(label).plist"
            guard let raw = try? String(contentsOfFile: template, encoding: .utf8) else {
                throw InstallError.missingTemplate(template)
            }
            let substituted = raw
                .replacingOccurrences(of: "__BUNDLE_PATH__", with: bundlePath)
                .replacingOccurrences(of: "__HOME__", with: homeDir.path)
            let dest = agentsDir.appendingPathComponent("\(label).plist")
            try substituted.write(to: dest, atomically: true, encoding: .utf8)
            // Reload (unload first to be safe; ignore errors)
            _ = run("/bin/launchctl", ["unload", dest.path])
            let exit = run("/bin/launchctl", ["load", dest.path])
            if exit != 0 {
                throw InstallError.launchctlFailed("loading \(label)")
            }
        }
    }

    /// Soft uninstall: unload agents, remove plists. Keep ~/.config.
    func uninstall() {
        for label in Self.labels {
            let plist = agentsDir.appendingPathComponent("\(label).plist")
            _ = run("/bin/launchctl", ["unload", plist.path])
            try? FileManager.default.removeItem(at: plist)
        }
    }

    /// Hard reset: uninstall + wipe ~/.config/woo-sprinkles.
    func reset() {
        uninstall()
        try? FileManager.default.removeItem(at: configDir)
    }

    @discardableResult
    private func run(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.launchPath = path
        p.arguments = args
        p.standardOutput = Pipe()
        p.standardError  = Pipe()
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }
}

// CLI hook — only fires if the binary is invoked with subcommands.
// Keeps the GUI launch path untouched. Used by tests/test_install_uninstall.sh.
@MainActor
func handleCLIIfNeeded() -> Bool {
    let args = CommandLine.arguments
    guard args.count >= 2 else { return false }
    let bundle = Bundle.main.bundlePath
    let inst = Installer(bundlePath: bundle)
    switch args[1] {
    case "install":
        do { try inst.install(); print("installed") }
        catch { print("error: \(error)"); exit(1) }
        exit(0)
    case "uninstall":
        inst.uninstall(); print("uninstalled"); exit(0)
    case "reset":
        inst.reset(); print("reset"); exit(0)
    default:
        return false
    }
}
