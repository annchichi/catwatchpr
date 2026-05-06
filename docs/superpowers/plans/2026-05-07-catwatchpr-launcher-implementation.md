# CatWatchPR Launcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a self-contained `CatWatchPR.app` macOS launcher (wizard + control panel + bundled scripts), fix the existing `menubar.swift` "Index out of range" crash, and make the project repo-agnostic so a teammate's first install watches *their* PRs.

**Architecture:** SwiftUI launcher app that bundles the existing scripts and menubar binary in `Contents/Resources/`. First launch detects state and shows a wizard (welcome → auth check → repo picker → install → cat picker) or a control panel (status + restart/activity/switch-cat/change-repo/remove). Per-user repo config lives in `~/.config/woo-sprinkles/repo` so source code stays repo-agnostic.

**Tech Stack:** Swift 5 / SwiftUI, AppKit (NSWorkspace, NSStatusBar), bash scripts, launchd plists, GitHub CLI (`gh`).

**Constraint:** Every task ends with a local verification step on Ann's Mac. Nothing pushes to the `catwatchpr` GitHub repo until Ann gives explicit approval at the end of Task 8.

---

## File Structure

After this plan completes, the repo at `~/tools/woo-sprinkles/` will look like:

```
woo-sprinkles/
├── menubar.swift                       # patched (Task 1)
├── watch.sh                            # patched to read REPO from config (Task 2)
├── sync.sh                             # patched to read REPO from config (Task 2)
├── setup.sh                            # patched to write repo config file (Task 2)
├── build_app.sh                        # NEW (Task 3) — builds CatWatchPR.app
├── launcher/                           # NEW (Tasks 3-7) — SwiftUI source
│   ├── LauncherApp.swift               # @main entry, routes wizard vs control panel
│   ├── State.swift                     # AppState (status detection, file readers)
│   ├── Style.swift                     # Pixel/terminal SwiftUI styling helpers
│   ├── Install.swift                   # Install/uninstall logic
│   ├── wizard/
│   │   ├── WelcomeView.swift
│   │   ├── AuthCheckView.swift
│   │   ├── RepoPickerView.swift
│   │   ├── InstallView.swift
│   │   └── CatPickerView.swift
│   ├── controlpanel/
│   │   ├── ControlPanelView.swift
│   │   ├── StatusGrid.swift
│   │   ├── AlertBanner.swift
│   │   └── ActionButtons.swift
│   └── activity/
│       └── ActivityWindow.swift
├── tests/                              # NEW (Tasks 1, 4)
│   ├── test_inbox_parser.sh
│   └── test_install_uninstall.sh
└── CatWatchPR.app/                     # NEW build output (gitignored)
```

The launcher source is split by feature (wizard / controlpanel / activity) so each
subsystem can be reasoned about independently. State and Install are shared across
both wizard and control panel.

**Relevant files (read for context before editing):**
- `~/tools/woo-sprinkles/menubar.swift` — current menu bar agent (to be patched in Task 1)
- `~/tools/woo-sprinkles/watch.sh` — line 6 hardcodes `REPO=`
- `~/tools/woo-sprinkles/sync.sh` — line 7 hardcodes `REPO=`
- `~/tools/woo-sprinkles/setup.sh` — line 64 sed-patches REPO into watch.sh / sync.sh
- `~/tools/woo-sprinkles/com.annchiahui.woo-sprinkles.{watch,sync,menubar}.plist` — launchd templates
- `~/tools/woo-sprinkles/docs/superpowers/specs/2026-05-07-catwatchpr-launcher-design.md` — approved design

---

## Task 1: Menu bar parser bug fix (TDD)

**Files:**
- Create: `tests/test_inbox_parser.sh`
- Modify: `menubar.swift:110-129` (the `inboxNotifs()` function)

The crash is in `menubar.swift:117`: `parts[0]` indexes an empty array when a line
is just `":"` or empty after trim, because Swift's `split` defaults to
`omittingEmptySubsequences: true`. We TDD this: write a failing test that triggers
the crash with bad input, fix the parser, watch the test pass.

- [ ] **Step 1: Write the failing smoke test**

Create `~/tools/woo-sprinkles/tests/test_inbox_parser.sh`:

```bash
#!/bin/bash
# Smoke test: menubar.swift must not crash on malformed inbox lines.
# Runs the menubar binary against a known-bad inbox file for 3 seconds
# and asserts no "Fatal error" appears in its stderr.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$DIR/.."
TMPCONFIG="$(mktemp -d)"
TMPSTDERR="$(mktemp)"

cleanup() { rm -rf "$TMPCONFIG" "$TMPSTDERR"; }
trap cleanup EXIT

# Malformed lines that previously crashed the parser.
cat > "$TMPCONFIG/inbox" <<'EOF'

:
:foo
foo:
foo:bar:baz
12345:comment
EOF
echo "cyan" > "$TMPCONFIG/cat_color"
echo "mochi" > "$TMPCONFIG/cat_name"

# Run menubar with HOME pointing at our temp config so it reads our inbox.
HOME="$TMPCONFIG/.." swift "$ROOT/menubar.swift" \
  >/dev/null 2>"$TMPSTDERR" &
PID=$!
sleep 3
kill "$PID" 2>/dev/null
wait "$PID" 2>/dev/null

if grep -q "Fatal error" "$TMPSTDERR"; then
    echo "FAIL: menubar.swift crashed on malformed inbox."
    echo "----- stderr -----"
    cat "$TMPSTDERR"
    exit 1
fi
echo "PASS: menubar.swift survived malformed inbox."
```

The test launches `menubar.swift` with `HOME` redirected so it reads our planted
malformed `inbox`. We give it 3 seconds to crash; if any `Fatal error` shows up,
the test fails.

- [ ] **Step 2: Make it executable and run the failing test**

```bash
chmod +x ~/tools/woo-sprinkles/tests/test_inbox_parser.sh
bash ~/tools/woo-sprinkles/tests/test_inbox_parser.sh
```

Expected: `FAIL: menubar.swift crashed on malformed inbox.` followed by
`Fatal error: Index out of range` in the stderr dump.

- [ ] **Step 3: Apply the fix in menubar.swift**

In `~/tools/woo-sprinkles/menubar.swift`, replace the body of `inboxNotifs()`
(lines 110-120) with:

```swift
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
              pr.allSatisfy({ $0.isNumber }) else { return nil }
        let reason = parts.count > 1
            ? parts[1].trimmingCharacters(in: .whitespaces)
            : "subscribed"
        return (pr: pr, reason: reason.isEmpty ? "subscribed" : reason)
    }
}
```

What changed:
- `omittingEmptySubsequences: false` so `split` always returns at least one element.
- `parts.first` instead of `parts[0]` — never out-of-range.
- `pr.allSatisfy({ $0.isNumber })` so non-numeric junk like `:` or `foo:bar` is
  dropped instead of being treated as a PR number.
- Reason falls back to `"subscribed"` when blank or absent.

- [ ] **Step 4: Re-run the smoke test, expect PASS**

```bash
bash ~/tools/woo-sprinkles/tests/test_inbox_parser.sh
```

Expected: `PASS: menubar.swift survived malformed inbox.`

- [ ] **Step 5: Verify locally on Ann's actual machine**

```bash
# Clean any malformed lines from the real inbox (one-time recovery)
mv ~/.config/woo-sprinkles/inbox ~/.config/woo-sprinkles/inbox.bak 2>/dev/null
touch ~/.config/woo-sprinkles/inbox

# Rebuild the menubar app and reload
bash ~/tools/woo-sprinkles/build_menubar.sh
launchctl kickstart -k gui/$(id -u)/com.annchiahui.woo-sprinkles.menubar

# Wait 5 seconds, check that menubar is actually running
sleep 5
launchctl list | grep menubar
```

Expected: `launchctl list | grep menubar` shows a real PID (not `-`), and you
should see the cat icon in your menu bar.

- [ ] **Step 6: Commit (local only — no push)**

```bash
cd ~/tools/woo-sprinkles
git add menubar.swift tests/test_inbox_parser.sh
git commit -m "fix(menubar): guard against empty/malformed inbox lines

Swift's split defaults to omittingEmptySubsequences:true, so a line
like ':' produced an empty array and parts[0] crashed the menu bar
agent in a relaunch loop. Use parts.first, validate PR is numeric,
and add a smoke test against malformed inputs.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Per-user REPO config refactor

**Files:**
- Modify: `watch.sh:6`
- Modify: `sync.sh:7`
- Modify: `setup.sh:64-65`

The wizard (Task 4) writes the repo to `~/.config/woo-sprinkles/repo`.
`watch.sh` and `sync.sh` need to read it from there. We keep a fallback to
the legacy hardcoded value so existing installs keep working until Task 5
fully replaces `setup.sh`.

- [ ] **Step 1: Replace REPO line in `watch.sh`**

In `~/tools/woo-sprinkles/watch.sh`, replace line 6:

```bash
REPO="woocommerce/woocommerce"
```

with:

```bash
REPO=$(cat "$HOME/.config/woo-sprinkles/repo" 2>/dev/null | tr -d '[:space:]')
if [ -z "$REPO" ]; then
    echo "watch.sh: ~/.config/woo-sprinkles/repo not set — run setup or the launcher" >&2
    exit 1
fi
```

- [ ] **Step 2: Replace REPO line in `sync.sh`**

In `~/tools/woo-sprinkles/sync.sh`, replace line 7:

```bash
REPO="woocommerce/woocommerce"
```

with:

```bash
REPO=$(cat "$HOME/.config/woo-sprinkles/repo" 2>/dev/null | tr -d '[:space:]')
if [ -z "$REPO" ]; then
    echo "sync.sh: ~/.config/woo-sprinkles/repo not set — run setup or the launcher" >&2
    exit 1
fi
```

- [ ] **Step 3: Update `setup.sh` to write the config file instead of sed-patching**

In `~/tools/woo-sprinkles/setup.sh`, replace lines 64-65:

```bash
sed -i '' "s|^REPO=.*|REPO=\"$CHOSEN_REPO\"|" "$DIR/watch.sh"
sed -i '' "s|^REPO=.*|REPO=\"$CHOSEN_REPO\"|" "$DIR/sync.sh"
```

with:

```bash
mkdir -p "$HOME/.config/woo-sprinkles"
echo "$CHOSEN_REPO" > "$HOME/.config/woo-sprinkles/repo"
```

- [ ] **Step 4: Smoke-test watch.sh against your real repo**

```bash
# Make sure the config file has your current repo value
cat ~/.config/woo-sprinkles/repo
# If empty, write it now (use whatever you currently watch):
echo "woocommerce/woocommerce" > ~/.config/woo-sprinkles/repo

bash ~/tools/woo-sprinkles/watch.sh
echo "exit: $?"
```

Expected: exit 0, no "REPO not set" error. The file
`~/.config/woo-sprinkles/last_checked` should have a fresh timestamp.

- [ ] **Step 5: Smoke-test the missing-config path**

```bash
mv ~/.config/woo-sprinkles/repo ~/.config/woo-sprinkles/repo.bak
bash ~/tools/woo-sprinkles/watch.sh
echo "exit: $?"
mv ~/.config/woo-sprinkles/repo.bak ~/.config/woo-sprinkles/repo
```

Expected: exit 1, message `watch.sh: ~/.config/woo-sprinkles/repo not set — run
setup or the launcher`. Confirms the guard works.

- [ ] **Step 6: Commit**

```bash
cd ~/tools/woo-sprinkles
git add watch.sh sync.sh setup.sh
git commit -m "refactor: read REPO from per-user config file

watch.sh and sync.sh now read REPO from ~/.config/woo-sprinkles/repo
instead of a hardcoded line that setup.sh sed-patched. setup.sh writes
the file directly. Source code is repo-agnostic, so a teammate's
install reads their own repo, not whatever the bundle was built with.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Launcher project skeleton + build_app.sh

**Files:**
- Create: `launcher/LauncherApp.swift`
- Create: `launcher/Style.swift`
- Create: `build_app.sh`
- Modify: `.gitignore` (add `CatWatchPR.app/`)

Goal: a "Hello, CatWatchPR" SwiftUI window that launches from a real `.app`
bundle. No wizard yet, no control panel — just a working scaffold so we can
iterate.

- [ ] **Step 1: Create `launcher/Style.swift`**

```swift
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
```

- [ ] **Step 2: Create `launcher/LauncherApp.swift`**

```swift
// launcher/LauncherApp.swift
// @main entry. For now: shows a placeholder window so we can validate the
// .app bundle compiles, launches, and shows up correctly. The wizard and
// control panel are wired in later tasks.
import SwiftUI

@main
struct LauncherApp: App {
    var body: some Scene {
        WindowGroup("CatWatchPR") {
            PlaceholderView()
                .frame(minWidth: 460, minHeight: 360)
                .background(CatStyle.bg)
        }
        .windowResizability(.contentSize)
    }
}

struct PlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("🐱")
                .font(.system(size: 48))
            Text("CatWatchPR")
                .font(CatStyle.mono)
                .tracking(2)
                .foregroundColor(CatStyle.cyan)
            Text("scaffold OK · wizard wired in Task 4")
                .font(CatStyle.monoSmall)
                .foregroundColor(CatStyle.dim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 3: Create `build_app.sh`**

```bash
#!/bin/bash
# build_app.sh — assemble CatWatchPR.app from the launcher/ source.
# Output: ./CatWatchPR.app next to this script.
# Usage:  bash build_app.sh

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$DIR/CatWatchPR.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"

echo "→ Cleaning previous build..."
rm -rf "$APP"
mkdir -p "$MACOS" "$RES/scripts" "$RES/launchd"

echo "→ Compiling launcher Swift sources..."
SOURCES=$(find "$DIR/launcher" -name "*.swift" | tr '\n' ' ')
swiftc $SOURCES -o "$MACOS/CatWatchPR" \
       -framework SwiftUI -framework AppKit \
       -target arm64-apple-macos13.0

echo "→ Writing Info.plist..."
cat > "$CONTENTS/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>      <string>com.annchiahui.catwatchpr</string>
    <key>CFBundleName</key>            <string>CatWatchPR</string>
    <key>CFBundleDisplayName</key>     <string>CatWatchPR</string>
    <key>CFBundleExecutable</key>      <string>CatWatchPR</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
EOF

echo "✓ Built: $APP"
echo "  Run with: open '$APP'"
```

- [ ] **Step 4: Make it executable and run the build**

```bash
chmod +x ~/tools/woo-sprinkles/build_app.sh
bash ~/tools/woo-sprinkles/build_app.sh
```

Expected: lines ending in `✓ Built: /Users/anntai/tools/woo-sprinkles/CatWatchPR.app`.

- [ ] **Step 5: Launch the app and verify the window appears**

```bash
open ~/tools/woo-sprinkles/CatWatchPR.app
```

Expected: a window appears with the cat emoji, "CATWATCHPR" in cyan monospace,
and the "scaffold OK" caption. Close the window when done.

- [ ] **Step 6: Update `.gitignore`**

Add to `~/tools/woo-sprinkles/.gitignore`:

```
CatWatchPR.app/
```

- [ ] **Step 7: Commit**

```bash
cd ~/tools/woo-sprinkles
git add launcher/ build_app.sh .gitignore
git commit -m "feat(launcher): add SwiftUI launcher scaffold + build_app.sh

LauncherApp.swift is a placeholder window that proves the bundle
compiles, launches, and renders style B. build_app.sh produces
CatWatchPR.app from launcher/ sources with no Xcode required.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Shared State + Install logic + integration test

**Files:**
- Create: `launcher/State.swift`
- Create: `launcher/Install.swift`
- Create: `tests/test_install_uninstall.sh`

Pull the non-UI logic out into testable Swift files: `AppState` reads
files/launchctl to determine status, `Installer` writes plists and runs
`launchctl`. We integration-test the install/uninstall path with a bash
script that exercises the binary directly (this works because `Installer`
exposes a CLI mode triggered by an env var).

- [ ] **Step 1: Create `launcher/State.swift`**

```swift
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
```

- [ ] **Step 2: Create `launcher/Install.swift`**

```swift
// launcher/Install.swift
// Install / uninstall logic for CatWatchPR. Writes plists into
// ~/Library/LaunchAgents/ with __BUNDLE_PATH__ substituted, runs launchctl
// load/unload, and (for "Reset everything") wipes ~/.config/woo-sprinkles.
//
// CLI mode: `CatWatchPR install <repo>` / `uninstall` / `reset` so
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
    let homeDir: URL = FileManager.default.homeDirectoryForCurrentUser

    var configDir: URL { homeDir.appendingPathComponent(".config/woo-sprinkles") }
    var agentsDir: URL { homeDir.appendingPathComponent("Library/LaunchAgents") }
    var templatesDir: String { "\(bundlePath)/Contents/Resources/launchd" }

    /// Writes repo file, copies plists with substitution, loads agents.
    func install(repo: String) throws {
        try FileManager.default.createDirectory(at: configDir,
                                                withIntermediateDirectories: true)
        try repo.write(to: configDir.appendingPathComponent("repo"),
                       atomically: true, encoding: .utf8)

        try FileManager.default.createDirectory(at: agentsDir,
                                                withIntermediateDirectories: true)
        for label in Self.labels {
            let template = "\(templatesDir)/\(label).plist"
            guard let raw = try? String(contentsOfFile: template, encoding: .utf8) else {
                throw InstallError.missingTemplate(template)
            }
            let substituted = raw.replacingOccurrences(of: "__BUNDLE_PATH__",
                                                       with: bundlePath)
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
        guard args.count >= 3 else { print("usage: install <repo>"); exit(2) }
        do { try inst.install(repo: args[2]); print("installed") }
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
```

- [ ] **Step 3: Wire CLI mode into `LauncherApp.swift`**

In `~/tools/woo-sprinkles/launcher/LauncherApp.swift`, replace the `@main`
struct with this version that intercepts CLI args before SwiftUI starts:

```swift
import SwiftUI

@main
struct LauncherApp: App {
    init() {
        // CLI mode short-circuits SwiftUI — used by tests and recovery shell.
        Task { @MainActor in
            if handleCLIIfNeeded() { /* exits inside */ }
        }
    }

    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup("CatWatchPR") {
            PlaceholderView()
                .environmentObject(state)
                .frame(minWidth: 460, minHeight: 360)
                .background(CatStyle.bg)
                .onAppear { state.startPolling() }
                .onDisappear { state.stopPolling() }
        }
        .windowResizability(.contentSize)
    }
}

struct PlaceholderView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        VStack(spacing: 16) {
            Text("🐱").font(.system(size: 48))
            Text("CatWatchPR").font(CatStyle.mono).tracking(2)
                .foregroundColor(CatStyle.cyan)
            Text("installed: \(state.isInstalled ? "yes" : "no") · repo: \(state.status.repo.isEmpty ? "—" : state.status.repo)")
                .font(CatStyle.monoSmall).foregroundColor(CatStyle.dim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 4: Stage three plist templates inside the bundle**

In `~/tools/woo-sprinkles/build_app.sh`, replace the line
`mkdir -p "$MACOS" "$RES/scripts" "$RES/launchd"` and add the template-staging
block right after the `mkdir`:

```bash
mkdir -p "$MACOS" "$RES/scripts" "$RES/launchd"

echo "→ Staging launchd plist templates..."
for label in com.annchiahui.woo-sprinkles.menubar \
             com.annchiahui.woo-sprinkles.watch \
             com.annchiahui.woo-sprinkles.sync; do
    src="$DIR/$label.plist"
    dest="$RES/launchd/$label.plist"
    # Replace any existing absolute path with the placeholder; the launcher
    # substitutes __BUNDLE_PATH__ at install time.
    sed -E "s|/Users/[^/]+/tools/woo-sprinkles|__BUNDLE_PATH__/Contents/Resources/scripts|g" \
        "$src" > "$dest"
done
```

- [ ] **Step 5: Create the integration test**

`~/tools/woo-sprinkles/tests/test_install_uninstall.sh`:

```bash
#!/bin/bash
# Integration test: build the launcher, run install/uninstall via the CLI,
# and assert the right artifacts appear and disappear.
#
# Uses a temp HOME so it doesn't touch the user's real ~/.config or
# ~/Library/LaunchAgents.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$DIR/.."
TMP="$(mktemp -d)"

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

echo "→ Building launcher..."
bash "$ROOT/build_app.sh" > "$TMP/build.log" 2>&1 || {
    echo "FAIL: build_app.sh"; cat "$TMP/build.log"; exit 1; }

APP="$ROOT/CatWatchPR.app"
BIN="$APP/Contents/MacOS/CatWatchPR"

# Run installer with HOME pointing at temp dir.
echo "→ Install with fake HOME..."
HOME="$TMP" "$BIN" install "annchichi/test-repo" || {
    echo "FAIL: install command"; exit 1; }

# Assertions
test -f "$TMP/.config/woo-sprinkles/repo" || { echo "FAIL: repo file missing"; exit 1; }
[ "$(cat "$TMP/.config/woo-sprinkles/repo")" = "annchichi/test-repo" ] \
    || { echo "FAIL: repo file wrong content"; exit 1; }
for label in menubar watch sync; do
    test -f "$TMP/Library/LaunchAgents/com.annchiahui.woo-sprinkles.$label.plist" \
        || { echo "FAIL: $label plist missing"; exit 1; }
    grep -q "__BUNDLE_PATH__" \
        "$TMP/Library/LaunchAgents/com.annchiahui.woo-sprinkles.$label.plist" \
        && { echo "FAIL: $label plist still has __BUNDLE_PATH__ placeholder"; exit 1; }
done
echo "  ✓ install wrote 3 plists + repo config"

# Uninstall
HOME="$TMP" "$BIN" uninstall || { echo "FAIL: uninstall command"; exit 1; }
for label in menubar watch sync; do
    if [ -f "$TMP/Library/LaunchAgents/com.annchiahui.woo-sprinkles.$label.plist" ]; then
        echo "FAIL: $label plist still present after uninstall"; exit 1
    fi
done
test -f "$TMP/.config/woo-sprinkles/repo" \
    || { echo "FAIL: uninstall wiped repo file (should be soft)"; exit 1; }
echo "  ✓ uninstall removed plists, kept config"

# Reset
HOME="$TMP" "$BIN" reset || { echo "FAIL: reset command"; exit 1; }
if [ -d "$TMP/.config/woo-sprinkles" ]; then
    echo "FAIL: reset did not wipe ~/.config/woo-sprinkles"; exit 1
fi
echo "  ✓ reset wiped config"

echo "PASS: install / uninstall / reset all work."
```

- [ ] **Step 6: Run the integration test**

```bash
chmod +x ~/tools/woo-sprinkles/tests/test_install_uninstall.sh
bash ~/tools/woo-sprinkles/tests/test_install_uninstall.sh
```

Expected: ends with `PASS: install / uninstall / reset all work.` and three `✓`
lines. If it fails, the failure message tells you which assertion broke.

- [ ] **Step 7: Commit**

```bash
cd ~/tools/woo-sprinkles
git add launcher/State.swift launcher/Install.swift launcher/LauncherApp.swift \
        build_app.sh tests/test_install_uninstall.sh
git commit -m "feat(launcher): add State + Install logic and integration test

State.swift polls launchctl + config files for live status.
Install.swift handles plist substitution and launchctl load/unload,
exposed as a CLI for tests. test_install_uninstall.sh exercises
install/uninstall/reset against a temp HOME.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Wizard screens (Welcome → Auth → Repo → Install → Cat picker)

**Files:**
- Create: `launcher/wizard/WelcomeView.swift`
- Create: `launcher/wizard/AuthCheckView.swift`
- Create: `launcher/wizard/RepoPickerView.swift`
- Create: `launcher/wizard/InstallView.swift`
- Create: `launcher/wizard/CatPickerView.swift`
- Modify: `launcher/LauncherApp.swift` (route to wizard when `!isInstalled`)

The wizard is a single-window navigation through 5 SwiftUI views, keyed off
an enum `WizardStep`. Cat picker (Step 5) also serves as the "Switch cat"
sheet from the control panel later.

- [ ] **Step 1: Add a `WizardStep` enum and shared wizard state**

Append to `~/tools/woo-sprinkles/launcher/State.swift`:

```swift
enum WizardStep: Int, CaseIterable {
    case welcome, authCheck, repoPicker, install, catPicker
}

@MainActor
final class WizardState: ObservableObject {
    @Published var step: WizardStep = .welcome
    @Published var ghAuthed: Bool = false
    @Published var repo: String = ""
    @Published var installError: String? = nil
    @Published var installing: Bool = false
    @Published var isFinished: Bool = false  // true after cat picker

    func checkAuth() {
        let p = Process()
        p.launchPath = "/usr/bin/env"
        p.arguments = ["gh", "auth", "status"]
        p.standardOutput = Pipe()
        p.standardError  = Pipe()
        try? p.run()
        p.waitUntilExit()
        ghAuthed = (p.terminationStatus == 0)
    }

    /// Try to suggest a sensible default repo: first repo in the user's gh list.
    func suggestRepo() {
        let p = Process()
        p.launchPath = "/usr/bin/env"
        p.arguments = ["gh", "repo", "list", "--limit", "1",
                       "--json", "nameWithOwner", "--jq", ".[0].nameWithOwner"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError  = Pipe()
        try? p.run()
        p.waitUntilExit()
        if p.terminationStatus == 0,
           let data = try? pipe.fileHandleForReading.readToEnd(),
           let s = String(data: data, encoding: .utf8) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { repo = t }
        }
    }

    static let repoRegex = #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"#

    var repoIsValid: Bool {
        repo.range(of: Self.repoRegex, options: .regularExpression) != nil
    }
}
```

- [ ] **Step 2: Create `WelcomeView.swift`**

```swift
// launcher/wizard/WelcomeView.swift
import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var wizard: WizardState
    var body: some View {
        VStack(spacing: 18) {
            Text("🐱").font(.system(size: 56))
            Text("CATWATCHPR")
                .font(CatStyle.mono).tracking(3).foregroundColor(CatStyle.cyan)
            Text("I watch your GitHub PRs and pop up\nwhen something needs you.")
                .font(CatStyle.monoSmall).foregroundColor(CatStyle.text)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 8)
            Button("Get started") {
                wizard.step = .authCheck
            }
            .buttonStyle(PixelButtonStyle(primary: true))
            .frame(width: 200)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
```

- [ ] **Step 3: Create `AuthCheckView.swift`**

```swift
// launcher/wizard/AuthCheckView.swift
import SwiftUI
import AppKit

struct AuthCheckView: View {
    @EnvironmentObject var wizard: WizardState
    var body: some View {
        VStack(spacing: 14) {
            Text("step 2 / 4 — github access")
                .font(CatStyle.monoTiny).tracking(2).textCase(.uppercase)
                .foregroundColor(CatStyle.dim)
            if wizard.ghAuthed {
                Text("● gh is authenticated")
                    .font(CatStyle.mono).foregroundColor(CatStyle.green)
                Button("Continue") { wizard.step = .repoPicker }
                    .buttonStyle(PixelButtonStyle(primary: true))
                    .frame(width: 200)
            } else {
                Text("● gh is NOT authenticated")
                    .font(CatStyle.mono).foregroundColor(CatStyle.red)
                Text("Open Terminal and run:")
                    .font(CatStyle.monoSmall).foregroundColor(CatStyle.dim)
                Text("gh auth login")
                    .font(CatStyle.mono).foregroundColor(CatStyle.cyan)
                    .padding(8).background(CatStyle.panelBg)
                HStack(spacing: 8) {
                    Button("Copy command") {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString("gh auth login", forType: .string)
                    }.buttonStyle(PixelButtonStyle())
                    Button("Re-check") {
                        wizard.checkAuth()
                    }.buttonStyle(PixelButtonStyle(primary: true))
                }.frame(width: 280)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .onAppear { wizard.checkAuth() }
    }
}
```

- [ ] **Step 4: Create `RepoPickerView.swift`**

```swift
// launcher/wizard/RepoPickerView.swift
import SwiftUI

struct RepoPickerView: View {
    @EnvironmentObject var wizard: WizardState
    var body: some View {
        VStack(spacing: 14) {
            Text("step 3 / 4 — pick a repo")
                .font(CatStyle.monoTiny).tracking(2).textCase(.uppercase)
                .foregroundColor(CatStyle.dim)
            Text("Which repo should I watch?")
                .font(CatStyle.mono).foregroundColor(CatStyle.text)
            TextField("org/repo", text: $wizard.repo)
                .textFieldStyle(.plain)
                .font(CatStyle.mono).foregroundColor(CatStyle.cyan)
                .padding(10)
                .background(CatStyle.panelBg)
                .overlay(Rectangle().stroke(
                    wizard.repoIsValid ? CatStyle.cyan : Color(red:0.16,green:0.16,blue:0.23),
                    lineWidth: 1))
                .frame(width: 280)
            Text("Your PRs in this repo will trigger the cat. You can\nchange this later.")
                .font(CatStyle.monoTiny).foregroundColor(CatStyle.dim)
                .multilineTextAlignment(.center)
            Button("Continue") { wizard.step = .install }
                .buttonStyle(PixelButtonStyle(primary: true))
                .frame(width: 200)
                .disabled(!wizard.repoIsValid)
                .opacity(wizard.repoIsValid ? 1.0 : 0.4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .onAppear { if wizard.repo.isEmpty { wizard.suggestRepo() } }
    }
}
```

- [ ] **Step 5: Create `InstallView.swift`**

```swift
// launcher/wizard/InstallView.swift
import SwiftUI

struct InstallView: View {
    @EnvironmentObject var wizard: WizardState
    @EnvironmentObject var state:  AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("step 4 / 4 — install")
                .font(CatStyle.monoTiny).tracking(2).textCase(.uppercase)
                .foregroundColor(CatStyle.dim)
            Text("about to do:")
                .font(CatStyle.mono).foregroundColor(CatStyle.text)
            Group {
                Text("· save repo: \(wizard.repo)")
                Text("· install 3 background agents")
                Text("· build menu bar app")
                Text("· run a one-time check to verify it works")
            }
            .font(CatStyle.monoSmall).foregroundColor(CatStyle.dim)

            if let err = wizard.installError {
                Text("⚠ \(err)").font(CatStyle.monoSmall).foregroundColor(CatStyle.red)
                    .padding(8).background(CatStyle.panelBg)
            }

            HStack(spacing: 8) {
                Button("Back") { wizard.step = .repoPicker }
                    .buttonStyle(PixelButtonStyle())
                Button(wizard.installing ? "Installing…" : "Install") {
                    runInstall()
                }
                .buttonStyle(PixelButtonStyle(primary: true))
                .disabled(wizard.installing)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(32)
    }

    private func runInstall() {
        wizard.installing = true
        wizard.installError = nil
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let inst = Installer(bundlePath: Bundle.main.bundlePath)
                try inst.install(repo: wizard.repo)
                // One-time smoke run of watch.sh; surface failure inline but don't abort.
                let p = Process()
                p.launchPath = "/bin/bash"
                p.arguments = ["\(Bundle.main.bundlePath)/Contents/Resources/scripts/watch.sh"]
                p.standardOutput = Pipe(); p.standardError = Pipe()
                try? p.run(); p.waitUntilExit()
                DispatchQueue.main.async {
                    wizard.installing = false
                    state.refresh()
                    wizard.step = .catPicker
                }
            } catch {
                DispatchQueue.main.async {
                    wizard.installing = false
                    wizard.installError = error.localizedDescription
                }
            }
        }
    }
}
```

- [ ] **Step 6: Create `CatPickerView.swift`**

```swift
// launcher/wizard/CatPickerView.swift
// Used both as wizard step 5 and as the "Switch cat" sheet in the control
// panel — caller passes an `onDone` closure so each context can decide what
// "Done" means (advance to control panel vs. close the sheet).
import SwiftUI

struct CatPickerView: View {
    @EnvironmentObject var state: AppState
    var onDone: () -> Void = {}

    let cats: [(name: String, color: String, emoji: String, blurb: String)] = [
        ("Mochi",  "cyan",  "🐱", "friendly · default"),
        ("Boba",   "pink",  "🐈", "warm · excited"),
        ("Matcha", "lime",  "😼", "minimal · no-nonsense"),
        ("Miso",   "ghost", "👻", "soft · dreamy"),
    ]
    var body: some View {
        VStack(spacing: 14) {
            Text("pick your cat")
                .font(CatStyle.monoTiny).tracking(2).textCase(.uppercase)
                .foregroundColor(CatStyle.dim)
            Text("you can switch any time")
                .font(CatStyle.monoSmall).foregroundColor(CatStyle.text)
            HStack(spacing: 12) {
                ForEach(cats, id: \.name) { cat in
                    Button(action: { pick(cat.name, cat.color) }) {
                        VStack(spacing: 6) {
                            Text(cat.emoji).font(.system(size: 28))
                            Text(cat.name).font(CatStyle.mono).foregroundColor(CatStyle.cyan)
                            Text(cat.blurb).font(CatStyle.monoTiny).foregroundColor(CatStyle.dim)
                        }
                        .frame(width: 90, height: 90)
                        .background(CatStyle.panelBg)
                        .overlay(Rectangle().stroke(
                            state.status.catName.lowercased() == cat.name.lowercased()
                                ? CatStyle.cyan : Color(red:0.16,green:0.16,blue:0.23),
                            lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            Button("Done") { onDone() }
                .buttonStyle(PixelButtonStyle(primary: true))
                .frame(width: 200)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func pick(_ name: String, _ color: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/woo-sprinkles")
        try? name.lowercased().write(to: dir.appendingPathComponent("cat_name"),
                                      atomically: true, encoding: .utf8)
        try? color.write(to: dir.appendingPathComponent("cat_color"),
                          atomically: true, encoding: .utf8)
        state.refresh()
        // Kick the menubar so the icon updates immediately.
        let p = Process()
        p.launchPath = "/bin/launchctl"
        p.arguments = ["kickstart", "-k",
                       "gui/\(getuid())/com.annchiahui.woo-sprinkles.menubar"]
        try? p.run()
    }
}
```

- [ ] **Step 7: Wire the wizard router into `LauncherApp.swift`**

Replace `~/tools/woo-sprinkles/launcher/LauncherApp.swift` body with:

```swift
import SwiftUI

@main
struct LauncherApp: App {
    init() {
        Task { @MainActor in if handleCLIIfNeeded() { /* exits */ } }
    }
    @StateObject private var state  = AppState()
    @StateObject private var wizard = WizardState()
    var body: some Scene {
        WindowGroup("CatWatchPR") {
            RootView()
                .environmentObject(state)
                .environmentObject(wizard)
                .frame(minWidth: 460, minHeight: 360)
                .background(CatStyle.bg)
                .onAppear { state.startPolling() }
                .onDisappear { state.stopPolling() }
        }
        .windowResizability(.contentSize)
    }
}

struct RootView: View {
    @EnvironmentObject var state:  AppState
    @EnvironmentObject var wizard: WizardState
    var body: some View {
        Group {
            if state.isInstalled && state.hasRepoConfig && wizard.isFinished {
                // Control panel comes online in Task 6.
                PlaceholderControlPanelView()
            } else {
                switch wizard.step {
                case .welcome:    WelcomeView()
                case .authCheck:  AuthCheckView()
                case .repoPicker: RepoPickerView()
                case .install:    InstallView()
                case .catPicker:  CatPickerView(onDone: { wizard.isFinished = true })
                }
            }
        }
        .onAppear {
            // Returning user (already installed): skip the wizard entirely.
            if state.isInstalled && state.hasRepoConfig {
                wizard.isFinished = true
            }
        }
    }
}

struct PlaceholderControlPanelView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        VStack(spacing: 12) {
            Text("✓ installed").font(CatStyle.mono).foregroundColor(CatStyle.green)
            Text("repo: \(state.status.repo)")
                .font(CatStyle.monoSmall).foregroundColor(CatStyle.dim)
            Text("control panel arrives in Task 6")
                .font(CatStyle.monoTiny).foregroundColor(CatStyle.dim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 8: Rebuild and walk the wizard manually**

```bash
# Make sure we start clean — wipe any prior install for testing
~/tools/woo-sprinkles/CatWatchPR.app/Contents/MacOS/CatWatchPR reset 2>/dev/null
bash ~/tools/woo-sprinkles/build_app.sh
open ~/tools/woo-sprinkles/CatWatchPR.app
```

Walk through all 5 screens:
1. Welcome → click *Get started*.
2. Auth check should show "● gh is authenticated" green (since you already are).
   Click *Continue*.
3. Repo picker pre-fills with one of your repos. Edit to `annchichi/test-repo`
   for the dry run, then *Continue*. Try clearing it — *Continue* should grey out.
4. Install screen lists the actions. Click *Install*. After ~1-2 seconds,
   you should advance to the cat picker.
5. Cat picker — click each cat, watch the highlight follow your selection.
   Click *Done*. The placeholder control panel should now appear.

Verify on disk:
```bash
cat ~/.config/woo-sprinkles/repo
ls ~/Library/LaunchAgents/com.annchiahui.woo-sprinkles.*
```

Both should contain expected content. Then clean up the test install:

```bash
~/tools/woo-sprinkles/CatWatchPR.app/Contents/MacOS/CatWatchPR uninstall
echo "woocommerce/woocommerce" > ~/.config/woo-sprinkles/repo  # restore yours
```

- [ ] **Step 9: Commit**

```bash
cd ~/tools/woo-sprinkles
git add launcher/
git commit -m "feat(launcher): add wizard (welcome → auth → repo → install → cat)

5-screen onboarding flow that runs on first launch when no install
is detected. Auth check uses 'gh auth status', repo picker pre-fills
from 'gh repo list', install runs Installer.install() and triggers a
smoke run of watch.sh before advancing to the cat picker.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Control panel (status grid + alert banner + actions)

**Files:**
- Create: `launcher/controlpanel/ControlPanelView.swift`
- Create: `launcher/controlpanel/StatusGrid.swift`
- Create: `launcher/controlpanel/AlertBanner.swift`
- Create: `launcher/controlpanel/ActionButtons.swift`
- Modify: `launcher/LauncherApp.swift` (replace `PlaceholderControlPanelView` with the real one)

Layout matches the approved mockup at
`.superpowers/brainstorm/.../control-panel.html`. When `state.status.menubar`
is `.crashed`, the alert banner appears and *Restart all* turns primary cyan.

- [ ] **Step 1: Create `StatusGrid.swift`**

```swift
// launcher/controlpanel/StatusGrid.swift
import SwiftUI

struct StatusGrid: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            row("menubar", status: state.status.menubar)
            row("watch",   status: state.status.watch)
            row("sync",    status: state.status.sync)
            row("last check", text: state.status.lastChecked)
            row("open prs",   text: "\(state.status.openPRs)")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CatStyle.bg)
    }

    @ViewBuilder
    private func row(_ label: String, status: AgentStatus) -> some View {
        HStack {
            Text(label).foregroundColor(CatStyle.dim)
            Spacer()
            switch status {
            case .running:    Text("● running").foregroundColor(CatStyle.green)
            case .scheduled:  Text("● scheduled").foregroundColor(CatStyle.green)
            case .stopped:    Text("● stopped").foregroundColor(CatStyle.dim)
            case .crashed:    Text("● crashed").foregroundColor(CatStyle.red)
            }
        }
        .font(CatStyle.monoSmall)
    }

    @ViewBuilder
    private func row(_ label: String, text: String) -> some View {
        HStack {
            Text(label).foregroundColor(CatStyle.dim)
            Spacer()
            Text(text).foregroundColor(CatStyle.dim)
        }.font(CatStyle.monoSmall)
    }
}
```

- [ ] **Step 2: Create `AlertBanner.swift`**

```swift
// launcher/controlpanel/AlertBanner.swift
import SwiftUI

struct AlertBanner: View {
    let excerpt: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("⚠ MENUBAR AGENT CRASHED")
                .font(CatStyle.monoTiny).tracking(1.5)
                .foregroundColor(CatStyle.red)
            Text(excerpt).font(CatStyle.monoSmall)
                .foregroundColor(Color(red:1.0,green:0.69,blue:0.75))
                .lineLimit(2).multilineTextAlignment(.leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red:1.0,green:0.33,blue:0.46).opacity(0.08))
        .overlay(Rectangle().frame(width:3).foregroundColor(CatStyle.red),
                 alignment: .leading)
    }
}
```

- [ ] **Step 3: Create `ActionButtons.swift`**

```swift
// launcher/controlpanel/ActionButtons.swift
import SwiftUI
import AppKit

struct ActionButtons: View {
    @EnvironmentObject var state: AppState
    @Binding var showActivity: Bool
    @Binding var showCatPicker: Bool
    @Binding var showRepoEditor: Bool
    @Binding var showRemoveConfirm: Bool

    var crashed: Bool {
        if case .crashed = state.status.menubar { return true } else { return false }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Button("Restart all", action: restartAll)
                    .buttonStyle(PixelButtonStyle(primary: crashed))
                Button("Activity") { showActivity = true }
                    .buttonStyle(PixelButtonStyle())
            }
            HStack(spacing: 18) {
                Button("switch cat ▸") { showCatPicker = true }
                    .buttonStyle(.plain).foregroundColor(CatStyle.dim)
                    .font(CatStyle.monoTiny)
                Button("change repo ▸") { showRepoEditor = true }
                    .buttonStyle(.plain).foregroundColor(CatStyle.dim)
                    .font(CatStyle.monoTiny)
                Button("remove ▸") { showRemoveConfirm = true }
                    .buttonStyle(.plain).foregroundColor(CatStyle.red)
                    .font(CatStyle.monoTiny)
            }
            .padding(.top, 6)
            .overlay(Rectangle().frame(height:1)
                .foregroundColor(Color(red:0.16,green:0.16,blue:0.23)),
                     alignment: .top)
        }
    }

    private func restartAll() {
        for label in Installer.labels {
            let plist = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/LaunchAgents/\(label).plist")
            let p = Process()
            p.launchPath = "/bin/launchctl"
            p.arguments = ["kickstart", "-k", "gui/\(getuid())/\(label)"]
            p.standardOutput = Pipe(); p.standardError = Pipe()
            try? p.run(); p.waitUntilExit()
            if !FileManager.default.fileExists(atPath: plist.path) {
                // Plist missing — load from bundle template again.
                let inst = Installer(bundlePath: Bundle.main.bundlePath)
                _ = try? inst.install(repo: state.status.repo)
            }
        }
        state.refresh()
    }
}
```

- [ ] **Step 4: Create `ControlPanelView.swift`**

```swift
// launcher/controlpanel/ControlPanelView.swift
import SwiftUI

struct ControlPanelView: View {
    @EnvironmentObject var state: AppState
    @State private var showActivity     = false
    @State private var showCatPicker    = false
    @State private var showRepoEditor   = false
    @State private var showRemoveConfirm = false

    var crashedExcerpt: String? {
        if case .crashed(let msg) = state.status.menubar { return msg } else { return nil }
    }

    var body: some View {
        VStack(spacing: 14) {
            // Header
            HStack(spacing: 12) {
                Text("🐱").font(.system(size: 28))
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.status.catName.uppercased())
                        .font(CatStyle.monoSmall).tracking(1.5)
                        .foregroundColor(CatStyle.cyan)
                    Text("~ watching \(state.status.repo) ~")
                        .font(CatStyle.monoTiny).foregroundColor(CatStyle.dim)
                }
                Spacer()
            }
            if let excerpt = crashedExcerpt {
                AlertBanner(excerpt: excerpt)
            }
            StatusGrid()
            ActionButtons(
                showActivity: $showActivity,
                showCatPicker: $showCatPicker,
                showRepoEditor: $showRepoEditor,
                showRemoveConfirm: $showRemoveConfirm
            )
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $showCatPicker) {
            CatPickerSheet(close: { showCatPicker = false })
        }
        .sheet(isPresented: $showRepoEditor) {
            RepoEditorSheet(close: { showRepoEditor = false })
        }
        .alert("Remove CatWatchPR?", isPresented: $showRemoveConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Soft uninstall", role: .destructive) {
                Installer(bundlePath: Bundle.main.bundlePath).uninstall()
                state.refresh()
            }
            Button("Reset everything (wipe config too)", role: .destructive) {
                Installer(bundlePath: Bundle.main.bundlePath).reset()
                state.refresh()
            }
        } message: {
            Text("Soft uninstall keeps your repo + cat preferences. Reset everything wipes them too.")
        }
    }
}

struct CatPickerSheet: View {
    let close: () -> Void
    var body: some View {
        CatPickerView(onDone: close)
            .padding(24)
            .frame(width: 460, height: 360)
            .background(CatStyle.bg)
    }
}

struct RepoEditorSheet: View {
    @EnvironmentObject var state: AppState
    let close: () -> Void
    @State private var repo: String = ""
    @State private var error: String? = nil
    var body: some View {
        VStack(spacing: 14) {
            Text("change watched repo")
                .font(CatStyle.monoTiny).tracking(2).textCase(.uppercase)
                .foregroundColor(CatStyle.dim)
            TextField("org/repo", text: $repo)
                .textFieldStyle(.plain)
                .font(CatStyle.mono).foregroundColor(CatStyle.cyan)
                .padding(10).background(CatStyle.panelBg)
                .frame(width: 280)
            if let e = error { Text(e).font(CatStyle.monoTiny).foregroundColor(CatStyle.red) }
            HStack(spacing: 8) {
                Button("Cancel", action: close).buttonStyle(PixelButtonStyle())
                Button("Save") { save() }.buttonStyle(PixelButtonStyle(primary: true))
                    .disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 360, height: 220)
        .background(CatStyle.bg)
        .onAppear { repo = state.status.repo }
    }
    var isValid: Bool {
        repo.range(of: WizardState.repoRegex, options: .regularExpression) != nil
    }
    func save() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/woo-sprinkles")
        do {
            try repo.write(to: dir.appendingPathComponent("repo"),
                           atomically: true, encoding: .utf8)
            // Restart watch agent so it picks up the new repo.
            let p = Process()
            p.launchPath = "/bin/launchctl"
            p.arguments = ["kickstart", "-k",
                           "gui/\(getuid())/com.annchiahui.woo-sprinkles.watch"]
            try? p.run()
            state.refresh()
            close()
        } catch {
            self.error = "Could not write: \(error.localizedDescription)"
        }
    }
}
```

- [ ] **Step 5: Replace placeholder in `LauncherApp.swift`**

In `~/tools/woo-sprinkles/launcher/LauncherApp.swift`, in the `RootView`
struct's `body`, change the `else` branch from:

```swift
PlaceholderControlPanelView()
```

to:

```swift
ControlPanelView()
```

And delete the `PlaceholderControlPanelView` struct definition entirely (it's
no longer used).

- [ ] **Step 6: Rebuild and verify the healthy state**

```bash
bash ~/tools/woo-sprinkles/build_app.sh
open ~/tools/woo-sprinkles/CatWatchPR.app
```

Expected: control panel window appears (since you're already installed). Verify
each piece:
- Header shows your active cat name + repo.
- Status grid shows menubar/watch/sync as `● running` or `● scheduled`.
- *Restart all* and *Activity* buttons are visible (Activity won't open
  anything yet — wired in Task 7).
- Footer shows *switch cat / change repo / remove*.
- Click *switch cat*, pick a different cat, watch the menu bar icon update,
  close the sheet.
- Click *change repo*, type something invalid (`notvalid`), watch *Save* grey
  out. Type your real repo, *Save* enables, click it, sheet closes.

- [ ] **Step 7: Verify the crash state**

```bash
# Plant a malformed line that the new menubar parser handles fine —
# we need to crash the OLD binary on disk if you haven't deployed Task 1's
# fix. Easier: synthesize a fake fatal error in the stderr so the launcher's
# detection fires.
echo "$(date '+%Y-%m-%dT%H:%M:%SZ')" > /tmp/woo-sprinkles-menubar.err
echo "Swift/ContiguousArrayBuffer.swift:692: Fatal error: Index out of range" \
    >> /tmp/woo-sprinkles-menubar.err
```

Within 2 seconds the control panel should re-render with:
- Red alert banner reading "⚠ MENUBAR AGENT CRASHED" with the Fatal error excerpt.
- `menubar` row turns red.
- *Restart all* button background turns cyan (primary).

Click *Restart all*. The synthetic stderr file will get older than 60 seconds
naturally, and the alert will clear on the next refresh. Verify it does.

- [ ] **Step 8: Commit**

```bash
cd ~/tools/woo-sprinkles
git add launcher/
git commit -m "feat(launcher): add control panel UI

Status grid + alert banner + action buttons. Crash detection reads
recent Fatal errors from the menubar stderr file. Switch cat /
change repo are sheets; remove uses a confirmation alert with both
soft-uninstall and reset-everything options.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Activity log window

**Files:**
- Create: `launcher/activity/ActivityWindow.swift`
- Modify: `launcher/controlpanel/ControlPanelView.swift` (open the window)

A second NSWindow showing merged tail of the three log files, prefixed with
`[watch]` / `[sync]` / `[menubar]`. Refresh every 2 seconds, last 200 lines.

- [ ] **Step 1: Create `ActivityWindow.swift`**

```swift
// launcher/activity/ActivityWindow.swift
import SwiftUI
import AppKit

struct ActivityView: View {
    @State private var lines: [String] = []
    @State private var timer: Timer?
    var body: some View {
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
        }
        .background(CatStyle.bg)
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
```

- [ ] **Step 2: Wire the *Activity* button to actually open the window**

In `~/tools/woo-sprinkles/launcher/controlpanel/ControlPanelView.swift`,
add the following modifier on the outer `VStack` — chain it after
`.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)` and
before the first `.sheet(isPresented: $showCatPicker)`:

```swift
.onChange(of: showActivity) { newValue in
    if newValue {
        ActivityWindowController.shared.show()
        showActivity = false  // it's a separate window, not a sheet
    }
}
```

- [ ] **Step 3: Rebuild and test**

```bash
bash ~/tools/woo-sprinkles/build_app.sh
open ~/tools/woo-sprinkles/CatWatchPR.app
```

Click *Activity*. A second window opens with prefixed log lines from all three
agents. Trigger fresh activity:

```bash
bash ~/tools/woo-sprinkles/watch.sh
```

Within 2 seconds new lines should appear in the Activity window. Close the
window, click *Activity* again — re-opens cleanly.

- [ ] **Step 4: Commit**

```bash
cd ~/tools/woo-sprinkles
git add launcher/
git commit -m "feat(launcher): add Activity log window

Second window tails the 6 log files (.log + .err for watch/sync/menubar)
into a unified, color-prefixed view. Refreshes every 2s, shows last 200
lines. Opened from the Activity button on the control panel.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Bundle scripts + end-to-end manual verification + (optional) push

**Files:**
- Modify: `build_app.sh` (copy scripts into bundle)
- Modify: plist templates (use `__BUNDLE_PATH__` + bundled menubar binary path)

The launcher and the menubar agent need to find the scripts when run from
launchd. We finish bundling those resources, then walk an end-to-end flow on
a clean state to verify nothing is missing before Ann gives the green light
to push.

- [ ] **Step 1: Bundle the scripts and the compiled menubar binary**

In `~/tools/woo-sprinkles/build_app.sh`, after the `Staging launchd plist
templates` block (added in Task 4), add:

```bash
echo "→ Bundling scripts..."
cp "$DIR/watch.sh" "$DIR/sync.sh" "$DIR/woo_cat.swift" "$DIR/cat_popup.swift" \
   "$DIR/switch-cat.sh" "$RES/scripts/"
chmod +x "$RES/scripts/"*.sh

echo "→ Compiling menubar agent..."
swiftc "$DIR/menubar.swift" -o "$RES/scripts/MenuBarAgent" \
       -framework AppKit \
       -target arm64-apple-macos13.0
```

- [ ] **Step 2: Update plist templates so they reference the bundled paths**

In each of the three `~/tools/woo-sprinkles/com.annchiahui.woo-sprinkles.*.plist`
files, replace any path containing `/Users/anntai/tools/woo-sprinkles` with
`__BUNDLE_PATH__/Contents/Resources/scripts`. Specifically:

For `com.annchiahui.woo-sprinkles.menubar.plist`, change line 9 from:

```xml
<string>/Users/anntai/tools/woo-sprinkles/WooSprinklesMenuBar.app/Contents/MacOS/WooSprinklesMenuBar</string>
```

to:

```xml
<string>__BUNDLE_PATH__/Contents/Resources/scripts/MenuBarAgent</string>
```

For `com.annchiahui.woo-sprinkles.watch.plist` and
`com.annchiahui.woo-sprinkles.sync.plist`, replace the `bash` invocation path
similarly. Run:

```bash
grep -n "/Users/anntai/tools/woo-sprinkles" \
    ~/tools/woo-sprinkles/com.annchiahui.woo-sprinkles.*.plist
```

then edit each match to use `__BUNDLE_PATH__/Contents/Resources/scripts`.

- [ ] **Step 3: Rerun the integration test against the new bundle**

```bash
bash ~/tools/woo-sprinkles/tests/test_inbox_parser.sh
bash ~/tools/woo-sprinkles/tests/test_install_uninstall.sh
```

Both should still PASS.

- [ ] **Step 4: Full clean-state walkthrough**

```bash
# Wipe all real install state to simulate a fresh teammate install.
~/tools/woo-sprinkles/CatWatchPR.app/Contents/MacOS/CatWatchPR reset
launchctl bootout gui/$(id -u)/com.annchiahui.woo-sprinkles.menubar 2>/dev/null
launchctl bootout gui/$(id -u)/com.annchiahui.woo-sprinkles.watch   2>/dev/null
launchctl bootout gui/$(id -u)/com.annchiahui.woo-sprinkles.sync    2>/dev/null
rm -f ~/Library/LaunchAgents/com.annchiahui.woo-sprinkles.*.plist

# Rebuild and copy to /Applications so we test the real distribution path
bash ~/tools/woo-sprinkles/build_app.sh
rm -rf /Applications/CatWatchPR.app
cp -R ~/tools/woo-sprinkles/CatWatchPR.app /Applications/

# Launch like a teammate would
open /Applications/CatWatchPR.app
```

Walk the full flow:
1. Wizard appears (welcome).
2. Walk through to install completion.
3. Verify `~/Library/LaunchAgents/` has 3 plists, none containing
   `__BUNDLE_PATH__` literally.
4. Verify `~/.config/woo-sprinkles/repo` has the value you typed.
5. Pick a cat. Menu bar icon appears within 5 seconds.
6. Close the launcher, reopen it. Control panel appears (not the wizard).
7. Click *Activity* — log window opens with watch.sh activity.
8. Click *change repo*, change to a different valid value, save. Confirm
   `~/.config/woo-sprinkles/repo` updated.
9. Click *switch cat*, change cat, watch icon update.
10. Click *remove* → *Soft uninstall*. Plists gone, config retained.
11. Close launcher, reopen. Wizard reappears (since not installed) but
    repo picker pre-fills with your saved repo.
12. Install again, then *remove* → *Reset everything*. Both plists and
    config gone.

If any step fails, fix it before continuing.

- [ ] **Step 5: Commit**

```bash
cd ~/tools/woo-sprinkles
git add build_app.sh com.annchiahui.woo-sprinkles.*.plist
git commit -m "feat(launcher): bundle scripts + menubar binary into .app

build_app.sh now copies watch.sh / sync.sh / woo_cat.swift / cat_popup.swift /
switch-cat.sh into Contents/Resources/scripts and compiles menubar.swift to
Contents/Resources/scripts/MenuBarAgent. Plist templates reference
__BUNDLE_PATH__/Contents/Resources/scripts so each user's install points at
their own /Applications/CatWatchPR.app.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 6: Push gate — Ann's explicit approval required**

Before running `git push`, **stop and ask Ann**:

> All four deliverables are complete and verified locally. The clean-state
> walkthrough passed end-to-end. Ready to push to `origin` (catwatchpr GitHub
> repo)?

If she says yes:

```bash
cd ~/tools/woo-sprinkles
git push origin feat/setup-onboarding
```

If she says no, leave the commits local and address whatever she wants to
adjust first.

---

## Self-Review Checklist (run after writing this plan)

- [x] Spec coverage — every requirement in the spec maps to a task:
  - Wizard 5 screens → Task 5
  - Control panel layout + state detection → Task 6
  - Menu bar bug fix → Task 1
  - REPO config refactor → Task 2
  - build_app.sh → Tasks 3 & 8
  - Activity log → Task 7
  - Smoke tests → Tasks 1 & 4
  - Per-user config / no PR leakage → Tasks 2 & 5
- [x] No "TODO" / "TBD" / "implement later" — every step has concrete code or commands.
- [x] Type consistency — `Installer`, `AppState`, `WizardState`, `WizardStep`, `AgentStatus`, `AppStatus`, `Installer.labels` referenced consistently across tasks.
- [x] Local-test-before-push constraint encoded as Task 8 Step 6 gate.
