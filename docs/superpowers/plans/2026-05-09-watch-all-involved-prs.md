# Watch All Involved PRs (No Repo Filter) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drop the single-repo configuration so CatWatchPR watches every PR the user authored or was requested to review across all of GitHub.

**Architecture:** The watch script (`watch.sh`) no longer reads `~/.config/woo-sprinkles/repo`; it asks GitHub for involved PRs globally and tracks them as fully-qualified `owner/repo#number` refs. The wizard's repo-picker step and the control panel's "change repo" link are removed. State files migrate implicitly: legacy bare-number lines are skipped on read, and qualified refs are written on every successful tick.

**Tech Stack:** Bash (watch.sh), Swift (launcher + menubar agents), `gh` CLI, launchctl, GitHub REST/GraphQL APIs.

---

## File Structure

| File | Responsibility |
|---|---|
| `watch.sh` | Orchestrates the 5-min tick: fetches involved PRs globally, detects merges, watches CI, fires the cat for new notifications. Reads/writes state in `~/.config/woo-sprinkles/`. |
| `launcher/Install.swift` | Owns plist substitution + `launchctl` calls. Drops the `repo:` parameter from `install()`. |
| `launcher/State.swift` | Drops `hasRepoConfig` and `status.repo`. Control-panel mode is now gated on `isInstalled` only. |
| `launcher/wizard/RepoPickerView.swift` | **Deleted.** No longer part of the wizard flow. |
| `launcher/State.swift` (`WizardStep`) | Removes `.repoPicker` from the enum. |
| `launcher/wizard/RootView.swift` (or wherever step routing lives) | Routes auth-check → install (skipping repo-picker). |
| `launcher/LauncherApp.swift` | `refreshDeployedPlists` no longer reads the repo file; calls `Installer.install()` with no args. |
| `launcher/controlpanel/ControlPanelView.swift` | Removes "change repo" link, removes `RepoEditorSheet`, updates header text. |
| `menubar.swift` | Inbox parser tolerates both legacy (`#N:reason`) and new (`owner/repo#N:reason`) line shapes. URL construction uses qualified refs. |
| `woo_cat.swift` | Cat popup: displays `owner/repo#N` when a repo prefix is present. URL construction uses qualified refs. |
| `tests/test_install_uninstall.sh` | Drops the `install <repo>` arg and the `repo` config file assertion. |
| `tests/test_watch_sh.sh` | **New.** Tests qualified-ref handling and legacy-line tolerance in `watch.sh` helper functions. |
| `tests/test_inbox_parser.sh` | Adds qualified-ref lines to the malformed-input fixture (parser must not crash on either format). |
| `README.md` | Install section drops "pick a repo" wording. |
| `build_app.sh` | Bumps `CFBundleShortVersionString` to `0.2.0`. |

---

## Task 1: Add unit tests for watch.sh's PR-ref helpers

**Why first:** Watch.sh is the riskiest change (parsing, state files, error handling). Locking down a small parser/serializer in tests gives us confidence before refactoring the orchestration.

**Files:**
- Create: `tests/test_watch_sh.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/bin/bash
# tests/test_watch_sh.sh
# Tests pure helper functions extracted from watch.sh: state-file line
# parsers and serializers must handle both legacy bare-number lines and
# new qualified-ref lines.

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$DIR/.."
source "$ROOT/watch.sh" --source-only  # see Step 3 — watch.sh exposes helpers when sourced with this flag

fail() { echo "FAIL: $1"; exit 1; }

# 1. parse_pr_ref: accepts both formats, returns "OWNER REPO NUMBER" tuples
[ "$(parse_pr_ref 'woocommerce/woocommerce#12345')" = "woocommerce woocommerce 12345" ] \
    || fail "qualified ref parse"
[ "$(parse_pr_ref '12345')" = "" ] || fail "legacy bare-number must return empty (skipped)"
[ "$(parse_pr_ref '')" = "" ] || fail "empty line must return empty"
[ "$(parse_pr_ref 'garbage')" = "" ] || fail "garbage line must return empty"

# 2. read_qualified_refs: filters legacy lines from a state file
TMP=$(mktemp)
printf '%s\n' "woocommerce/woocommerce#1" "12345" "" "annchichi/catwatchpr#7" "garbage" > "$TMP"
out=$(read_qualified_refs "$TMP" | tr '\n' ' ')
[ "$out" = "woocommerce/woocommerce#1 annchichi/catwatchpr#7 " ] \
    || fail "read_qualified_refs filtered output, got: '$out'"
rm "$TMP"

echo "PASS: watch.sh helper tests"
```

- [ ] **Step 2: Make the script executable and run it — expect FAIL**

```bash
chmod +x tests/test_watch_sh.sh
bash tests/test_watch_sh.sh
```

Expected: failure. `--source-only` doesn't exist yet; helpers don't exist; functions undefined.

- [ ] **Step 3: Add the source-only guard and helper stubs in watch.sh**

At the very top of `watch.sh`, after the shebang and comments:

```bash
# Allow tests to source us without running the orchestration body.
# Pass --source-only as the first argument to define helpers and return.
SOURCE_ONLY=0
if [ "${1:-}" = "--source-only" ]; then
    SOURCE_ONLY=1
fi

# Parse a state-file line. Echoes "OWNER REPO NUMBER" for qualified refs
# (owner/repo#N), or empty for legacy or invalid input.
parse_pr_ref() {
    local line="$1"
    if [[ "$line" =~ ^([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)#([0-9]+)$ ]]; then
        echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"
    fi
}

# Read a state file and emit only lines that parse as qualified refs.
read_qualified_refs() {
    local file="$1"
    [ -f "$file" ] || return 0
    while IFS= read -r line; do
        if [ -n "$(parse_pr_ref "$line")" ]; then
            echo "$line"
        fi
    done < "$file"
}

# When sourced by tests, exit here without running the orchestration body.
if [ "$SOURCE_ONLY" -eq 1 ]; then
    return 0 2>/dev/null || exit 0
fi
```

- [ ] **Step 4: Run the test — expect PASS**

```bash
bash tests/test_watch_sh.sh
```

Expected output ends with `PASS: watch.sh helper tests`.

- [ ] **Step 5: Commit**

```bash
git add tests/test_watch_sh.sh watch.sh
git commit -m "test(watch): add helpers and unit tests for qualified PR refs

Introduce parse_pr_ref and read_qualified_refs as small, testable units
that handle both legacy bare-number state-file lines (skipped) and new
qualified owner/repo#N refs (parsed). Wire up a --source-only mode so
tests can source watch.sh without triggering the full tick.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Refactor watch.sh PR fetching to use qualified refs

**Files:**
- Modify: `watch.sh`

- [ ] **Step 1: Replace the `$REPO` lookup and PR fetch block**

Find this block near the top of `watch.sh` (after the source-only guard from Task 1, before any state-file reads):

```bash
REPO=$(cat "$HOME/.config/woo-sprinkles/repo" 2>/dev/null | tr -d '[:space:]')
if [ -z "$REPO" ]; then
    echo "watch.sh: ~/.config/woo-sprinkles/repo not set — run setup or the launcher" >&2
    exit 1
fi
```

Delete it entirely. Then find the PR fetch block (added in v0.1.3):

```bash
# Open PRs you authored OR are requested to review
authored=$(gh pr list --author "@me" --repo "$REPO" --state open \
    --json number --jq '.[].number' 2>/dev/null)
review_requested=$(gh pr list --search "review-requested:@me" --repo "$REPO" --state open \
    --json number --jq '.[].number' 2>/dev/null)
my_prs=$(printf '%s\n%s\n' "$authored" "$review_requested" | sort -u | grep -v '^$' | tr '\n' ' ')
```

Replace it with:

```bash
# Open PRs you authored OR are requested to review (anywhere on GitHub).
# Each line of output is "owner/repo#number". Uses `gh search prs` because
# `gh pr list` is repo-scoped — there is no global mode without --repo.
authored=$(gh search prs --author "@me" --state open \
    --json number,repository \
    --jq '.[] | "\(.repository.nameWithOwner)#\(.number)"' \
    2>/dev/null)
review_requested=$(gh search prs --review-requested "@me" --state open \
    --json number,repository \
    --jq '.[] | "\(.repository.nameWithOwner)#\(.number)"' \
    2>/dev/null)
my_prs=$(printf '%s\n%s\n' "$authored" "$review_requested" | sort -u | grep -v '^$' | tr '\n' ' ')
```

- [ ] **Step 2: Update merge detection to handle qualified refs**

Find the merge-detection block:

```bash
prev_prs=$(cat "$PREV_PRS_FILE" 2>/dev/null || echo "")
merged_prs=()
for pr in $prev_prs; do
    if ! echo " $my_prs " | grep -qw "$pr"; then
        state=$(gh pr view "$pr" --repo "$REPO" --json state --jq '.state' 2>/dev/null)
        if [ "$state" = "MERGED" ]; then
            merged_prs+=("$pr")
            inbox_remove "$pr"
        fi
    fi
done
echo "$my_prs" > "$PREV_PRS_FILE"
```

Replace with:

```bash
prev_prs=$(read_qualified_refs "$PREV_PRS_FILE" | tr '\n' ' ')
merged_prs=()
for ref in $prev_prs; do
    # Skip if ref is still in the current involved set
    if echo " $my_prs " | grep -qw "$ref"; then continue; fi
    # Parse owner/repo#N → "owner repo N" (3 tokens)
    read -r owner name number <<< "$(parse_pr_ref "$ref")"
    [ -z "$number" ] && continue
    state=$(gh pr view "$number" --repo "$owner/$name" --json state --jq '.state' 2>/dev/null)
    if [ "$state" = "MERGED" ]; then
        merged_prs+=("$ref")
        inbox_remove "$ref"
    fi
done
echo "$my_prs" > "$PREV_PRS_FILE"
```

- [ ] **Step 3: Update CI watching to use qualified refs**

Find the CI watching block:

```bash
for pr in $my_prs; do
    checks=$(gh pr checks "$pr" --repo "$REPO" 2>/dev/null)
    [ -z "$checks" ] && continue
    ...
done
```

Replace `$pr` iteration to parse the qualified ref:

```bash
for ref in $my_prs; do
    read -r owner name number <<< "$(parse_pr_ref "$ref")"
    [ -z "$number" ] && continue
    checks=$(gh pr checks "$number" --repo "$owner/$name" 2>/dev/null)
    [ -z "$checks" ] && continue

    has_pending=$(echo "$checks" | awk -F'\t' '$2=="pending"{c++} END{print c+0}')
    has_fail=$(echo "$checks"    | awk -F'\t' '$2=="fail"{c++} END{print c+0}')

    if [ "$has_pending" -gt 0 ]; then
        now_watching="$now_watching$ref "
    elif echo " $prev_watching " | grep -qw "$ref"; then
        if [ "$has_fail" -gt 0 ]; then
            inbox_upsert "$ref" "ci_fail"
            swift "$DIR/woo_cat.swift" 0 0 0 "$CAT" "" 0 0 0 0 "❌ PR $ref has failing checks" &
        else
            inbox_upsert "$ref" "ci_pass"
            swift "$DIR/woo_cat.swift" 0 0 0 "$CAT" "" 0 0 0 0 "✅ PR $ref is clear to merge!" &
        fi
    fi
done
```

- [ ] **Step 4: Update notifications path to drop the repo filter**

Find the notification fetch:

```bash
notif_tsv=$(gh api notifications --jq '
  [.[] | select(
    .unread == true and
    .repository.full_name == "'"$REPO"'" and
    .subject.type == "PullRequest"
  ) | {
    id:     .id,
    reason: .reason,
    pr:     (.subject.url | split("/") | last)
  }] | .[] | "\(.id)\t\(.reason)\t\(.pr)"
' 2>/dev/null || true)
```

Replace with:

```bash
# Fetch ALL unread PR notifications, regardless of repo. Each row carries
# a fully-qualified ref so downstream membership checks match my_prs.
notif_tsv=$(gh api notifications --jq '
  [.[] | select(
    .unread == true and
    .subject.type == "PullRequest"
  ) | {
    id:     .id,
    reason: .reason,
    ref:    "\(.repository.full_name)#\(.subject.url | split("/") | last)"
  }] | .[] | "\(.id)\t\(.reason)\t\(.ref)"
' 2>/dev/null || true)
```

Then find the `my_notif_tsv` filter block. Update the inner condition from `pr` to `ref`:

```bash
my_notif_tsv=""
while IFS=$'\t' read -r id reason ref; do
    if echo " $my_prs " | grep -qw "$ref"; then
        my_notif_tsv+="$id"$'\t'"$reason"$'\t'"$ref"$'\n'
    fi
done <<< "$notif_tsv"
```

And update the active-PRs collection:

```bash
active_prs=()
active_pr_ids=()
while IFS=$'\t' read -r id reason ref; do
    if echo "$new_ids" | grep -qF "$id"; then
        if ! printf '%s\n' "${active_pr_ids[@]}" | grep -qx "$ref"; then
            active_pr_ids+=("$ref")
            active_prs+=("${ref}:${reason}")
            inbox_upsert "$ref" "$reason"
        fi
    fi
done <<< "$my_notif_tsv"
```

- [ ] **Step 5: Run the test suite — expect existing helper tests still pass**

```bash
bash tests/test_watch_sh.sh
```

Expected: `PASS: watch.sh helper tests`. (The test only exercises helpers, not the orchestration; both should still work.)

- [ ] **Step 6: Manual smoke check**

```bash
# Trigger one watch tick on Ann's machine and check it doesn't error
truncate -s 0 /tmp/woo-sprinkles-watch.err
launchctl kickstart -k "gui/$UID/com.annchiahui.woo-sprinkles.watch"
sleep 5
cat /tmp/woo-sprinkles-watch.err  # expect empty
launchctl print "gui/$UID/com.annchiahui.woo-sprinkles.watch" | grep "last exit code"
# expect: last exit code = 0
```

- [ ] **Step 7: Commit**

```bash
git add watch.sh
git commit -m "feat(watch): drop repo filter, use qualified PR refs

The watch now fetches involved PRs (authored + review-requested)
across all of GitHub instead of a single configured repo. Internal
state structures switch from bare PR numbers to fully-qualified
owner/repo#number refs so downstream merge detection, CI watching,
and notification filtering can resolve the right repo per PR.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Add API-failure resilience to watch.sh

**Files:**
- Modify: `watch.sh`

- [ ] **Step 1: Add a fetch-and-validate helper**

Insert near the top of `watch.sh` (after `parse_pr_ref` / `read_qualified_refs`):

```bash
# Run a gh command. If the command exits non-zero, log to stderr and
# signal the caller to abort the tick (preserving state files).
# Echoes stdout on success.
gh_safe() {
    local label="$1"; shift
    local out
    out=$("$@" 2>&1)
    local rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "watch.sh: $label failed (exit $rc): $out" >&2
        return $rc
    fi
    echo "$out"
}
```

- [ ] **Step 2: Wrap the involved-PR fetches**

Update Task 2's fetch block:

```bash
authored=$(gh_safe "search authored" \
    gh search prs --author "@me" --state open \
    --json number,repository \
    --jq '.[] | "\(.repository.nameWithOwner)#\(.number)"') \
    || exit 0
review_requested=$(gh_safe "search review-requested" \
    gh search prs --review-requested "@me" --state open \
    --json number,repository \
    --jq '.[] | "\(.repository.nameWithOwner)#\(.number)"') \
    || exit 0
```

The `|| exit 0` causes the tick to abort gracefully on failure. Crucially, this happens **before** `echo "$my_prs" > "$PREV_PRS_FILE"`, so the previous-tick cache is preserved.

- [ ] **Step 3: Wrap the notifications fetch**

Update the notification fetch block:

```bash
notif_tsv=$(gh_safe "api notifications" \
    gh api notifications --jq '
      [.[] | select(.unread == true and .subject.type == "PullRequest")
       | { id: .id, reason: .reason,
           ref: "\(.repository.full_name)#\(.subject.url | split("/") | last)" }]
      | .[] | "\(.id)\t\(.reason)\t\(.ref)"') \
    || exit 0
```

- [ ] **Step 4: Run the test suite + smoke check**

```bash
bash tests/test_watch_sh.sh
```

Expected: PASS.

- [ ] **Step 5: Manual failure simulation (optional)**

```bash
# Temporarily rename gh to simulate "command not found"
mv "$(which gh)" "$(which gh).disabled"
launchctl kickstart -k "gui/$UID/com.annchiahui.woo-sprinkles.watch"
sleep 5
# Expect: state files unchanged (timestamp older than now)
ls -la ~/.config/woo-sprinkles/prev_open_prs ~/.config/woo-sprinkles/seen_notif_ids
mv "$(which gh).disabled" "$(which gh)"
```

- [ ] **Step 6: Commit**

```bash
git add watch.sh
git commit -m "feat(watch): preserve state on GitHub API failure

Wrap critical gh calls in gh_safe so a non-zero exit aborts the tick
without overwriting state files. Next tick (5 min later) retries from
a clean state — no false-positive notifications, no lost cache.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Drop the `repo:` parameter from Installer.install

**Files:**
- Modify: `launcher/Install.swift`

- [ ] **Step 1: Update the function signature**

In `launcher/Install.swift`, find:

```swift
/// Writes repo file, copies plists with substitution, loads agents.
func install(repo: String) throws {
    try FileManager.default.createDirectory(at: configDir,
                                            withIntermediateDirectories: true)
    try repo.write(to: configDir.appendingPathComponent("repo"),
                   atomically: true, encoding: .utf8)

    try FileManager.default.createDirectory(at: agentsDir,
                                            withIntermediateDirectories: true)
    for label in Self.labels {
        ...
    }
}
```

Replace with:

```swift
/// Copies plists with substitution and loads agents. The repo config
/// file is no longer written here — v0.2.0 watches all involved PRs
/// without per-user repo configuration.
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
        _ = run("/bin/launchctl", ["unload", dest.path])
        let exit = run("/bin/launchctl", ["load", dest.path])
        if exit != 0 {
            throw InstallError.launchctlFailed("loading \(label)")
        }
    }
}
```

- [ ] **Step 2: Update the CLI subcommand**

Find:

```swift
case "install":
    guard args.count >= 3 else { print("usage: install <repo>"); exit(2) }
    do { try inst.install(repo: args[2]); print("installed") }
    catch { print("error: \(error)"); exit(1) }
    exit(0)
```

Replace with:

```swift
case "install":
    do { try inst.install(); print("installed") }
    catch { print("error: \(error)"); exit(1) }
    exit(0)
```

- [ ] **Step 3: Build to verify it compiles**

```bash
bash build_app.sh 2>&1 | tail -5
```

Expected: `✓ Built: ...`. Compilation errors mean a caller of `install(repo:)` wasn't updated yet — those are addressed in Tasks 5 and 8.

- [ ] **Step 4: Commit**

```bash
git add launcher/Install.swift
git commit -m "refactor(install): drop repo parameter from install()

v0.2.0 watches all involved PRs across GitHub, so the per-user repo
config file is no longer written or required. install() now just
copies plists and loads launch agents.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Remove the wizard's repo-picker step

**Files:**
- Delete: `launcher/wizard/RepoPickerView.swift`
- Modify: `launcher/State.swift` (`WizardStep` enum)
- Modify: `launcher/wizard/InstallView.swift` (caller of `install(repo:)`)
- Modify: `launcher/LauncherApp.swift` (`RootView` step routing)

- [ ] **Step 1: Locate all references to `.repoPicker` and `RepoPickerView`**

```bash
grep -rn "\.repoPicker\|RepoPickerView" launcher/
```

This produces the exact set of files to edit. Expect to find:
- `launcher/State.swift` — enum case
- `launcher/wizard/RepoPickerView.swift` — definition
- `launcher/wizard/RepoPickerView.swift` — also references `.install` to advance
- `launcher/wizard/AuthCheckView.swift` — advances to `.repoPicker`
- `launcher/wizard/InstallView.swift` — calls `Installer.install(repo: ...)` and reads from wizard state
- `launcher/LauncherApp.swift` — `RootView` switch statement

- [ ] **Step 2: Update WizardStep enum**

In `launcher/State.swift`, find:

```swift
enum WizardStep: Int, CaseIterable {
    case welcome, authCheck, repoPicker, install, catPicker, allDone
}
```

Replace with:

```swift
enum WizardStep: Int, CaseIterable {
    case welcome, authCheck, install, catPicker, allDone
}
```

- [ ] **Step 3: Update AuthCheckView's "next" target**

In `launcher/wizard/AuthCheckView.swift`, find any line that sets `wizard.step = .repoPicker` and change it to `wizard.step = .install`. (There should be exactly one — the "Continue" button action when auth succeeds.)

- [ ] **Step 4: Update InstallView to call install() with no args**

In `launcher/wizard/InstallView.swift`, find the call site:

```swift
try Installer(bundlePath: Bundle.main.bundlePath).install(repo: wizard.repo)
```

Replace with:

```swift
try Installer(bundlePath: Bundle.main.bundlePath).install()
```

If `wizard.repo` is referenced anywhere else in the file (display, validation), remove those references too — they're dead code now.

- [ ] **Step 5: Update RootView's switch statement**

In `launcher/LauncherApp.swift`, find:

```swift
switch wizard.step {
case .welcome:    WelcomeView()
case .authCheck:  AuthCheckView()
case .repoPicker: RepoPickerView()
case .install:    InstallView()
case .catPicker:  CatPickerView(onDone: { wizard.step = .allDone })
case .allDone:    AllDoneView()
}
```

Remove the `.repoPicker` line entirely:

```swift
switch wizard.step {
case .welcome:    WelcomeView()
case .authCheck:  AuthCheckView()
case .install:    InstallView()
case .catPicker:  CatPickerView(onDone: { wizard.step = .allDone })
case .allDone:    AllDoneView()
}
```

- [ ] **Step 6: Delete RepoPickerView.swift**

```bash
git rm launcher/wizard/RepoPickerView.swift
```

- [ ] **Step 7: Remove `repo` and `suggestRepo` from WizardState**

In `launcher/State.swift`, the `WizardState` class has:

```swift
@Published var repo: String = ""
...
func suggestRepo() { ... }
static let repoRegex = #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"#
var repoIsValid: Bool { ... }
```

Remove all four. They're now unused.

- [ ] **Step 8: Build to verify clean compile**

```bash
bash build_app.sh 2>&1 | tail -5
```

Expected: `✓ Built: ...`. No errors, no warnings about unused variables.

- [ ] **Step 9: Commit**

```bash
git add launcher/
git commit -m "feat(wizard): drop the repo-picker step

v0.2.0 watches all involved PRs without per-user repo configuration,
so the wizard goes straight from auth check to install (4 steps,
was 5). Removes RepoPickerView, the .repoPicker enum case, and
the wizard's repo state.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Update LauncherApp.refreshDeployedPlists to drop the repo lookup

**Files:**
- Modify: `launcher/LauncherApp.swift`

- [ ] **Step 1: Replace the helper**

Find the `refreshDeployedPlists` function added in v0.1.5:

```swift
private static func refreshDeployedPlists() {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let menubarPlist = home.appendingPathComponent(
        "Library/LaunchAgents/com.annchiahui.woo-sprinkles.menubar.plist")
    guard FileManager.default.fileExists(atPath: menubarPlist.path) else { return }

    let repoFile = home.appendingPathComponent(".config/woo-sprinkles/repo")
    guard let raw = try? String(contentsOf: repoFile, encoding: .utf8) else { return }
    let repo = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !repo.isEmpty else { return }

    try? Installer(bundlePath: Bundle.main.bundlePath).install(repo: repo)
}
```

Replace with:

```swift
private static func refreshDeployedPlists() {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let menubarPlist = home.appendingPathComponent(
        "Library/LaunchAgents/com.annchiahui.woo-sprinkles.menubar.plist")
    guard FileManager.default.fileExists(atPath: menubarPlist.path) else { return }

    try? Installer(bundlePath: Bundle.main.bundlePath).install()
}
```

- [ ] **Step 2: Build to verify it compiles**

```bash
bash build_app.sh 2>&1 | tail -5
```

Expected: `✓ Built: ...`.

- [ ] **Step 3: Commit**

```bash
git add launcher/LauncherApp.swift
git commit -m "refactor(launcher): drop repo lookup from refreshDeployedPlists

The plist-refresh-on-launch helper no longer needs to read the user's
repo config (there is no per-user repo in v0.2.0). It just guards on
the presence of the menubar plist and re-runs install().

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Remove "change repo" link and update header in ControlPanelView

**Files:**
- Modify: `launcher/controlpanel/ControlPanelView.swift`
- Modify: `launcher/controlpanel/ActionButtons.swift` (if it owns the change-repo link)
- Modify: `launcher/State.swift` (drop `status.repo` and `hasRepoConfig`)

- [ ] **Step 1: Locate the change-repo link**

```bash
grep -rn "change repo\|showRepoEditor\|RepoEditorSheet" launcher/
```

- [ ] **Step 2: Remove the change-repo link**

In whichever file owns it (likely `ActionButtons.swift`), remove the button definition. Also remove its `@Binding var showRepoEditor: Bool` parameter from the struct's signature, and remove the corresponding `@State private var showRepoEditor` and the `.sheet(isPresented: $showRepoEditor)` modifier from `ControlPanelView.swift`.

- [ ] **Step 3: Delete the RepoEditorSheet struct**

In `launcher/controlpanel/ControlPanelView.swift`, remove the entire `struct RepoEditorSheet: View { ... }` block.

- [ ] **Step 4: Update the header text**

In `launcher/controlpanel/ControlPanelView.swift`, find:

```swift
Text("~ watching \(state.status.repo) ~")
    .font(CatStyle.monoTiny).foregroundColor(CatStyle.dim)
```

Replace with:

```swift
Text("~ watching wherever you're involved ~")
    .font(CatStyle.monoTiny).foregroundColor(CatStyle.dim)
```

- [ ] **Step 5: Drop `repo` and `hasRepoConfig` from AppState**

In `launcher/State.swift`, find the `AppStatus` struct:

```swift
struct AppStatus: Sendable {
    var menubar:      AgentStatus = .stopped
    var watch:        AgentStatus = .stopped
    var sync:         AgentStatus = .stopped
    var lastChecked:  String = "never"
    var openPRs:      Int = 0
    var catName:      String = "mochi"
    var catColor:     String = "cyan"
    var repo:         String = ""
    var crashExcerpt: String? = nil
}
```

Remove the `var repo: String = ""` line. Then in `AppState`, find `var hasRepoConfig: Bool { ... }` and delete the property.

In `computeStatus()`, remove the `s.repo = readConfigFile("repo") ?? ""` line.

- [ ] **Step 6: Update RootView's gating condition**

In `launcher/LauncherApp.swift`, find:

```swift
if state.isInstalled && state.hasRepoConfig && wizard.isFinished {
    ControlPanelView()
}
```

Replace with:

```swift
if state.isInstalled && wizard.isFinished {
    ControlPanelView()
}
```

Same for the `.onAppear` block:

```swift
if state.isInstalled && state.hasRepoConfig {
    wizard.isFinished = true
}
```

becomes:

```swift
if state.isInstalled {
    wizard.isFinished = true
}
```

- [ ] **Step 7: Build to verify clean compile**

```bash
bash build_app.sh 2>&1 | tail -5
```

Expected: `✓ Built: ...`.

- [ ] **Step 8: Commit**

```bash
git add launcher/
git commit -m "feat(controlpanel): drop change-repo link, update header

The control panel no longer manages a per-user repo. The 'change repo'
link, the RepoEditorSheet, the status.repo field, and hasRepoConfig
are all removed. The header reads 'watching wherever you're involved'.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Update menubar.swift inbox parser for qualified refs

**Files:**
- Modify: `menubar.swift`
- Modify: `tests/test_inbox_parser.sh` (extend fixture)

- [ ] **Step 1: Extend the test fixture**

In `tests/test_inbox_parser.sh`, find the heredoc that creates the malformed inbox (`cat > "$INBOX" <<'EOF'`). Append qualified-ref lines below the existing legacy ones:

```bash
cat > "$INBOX" <<'EOF'

:
:foo
foo:
foo:bar:baz
12345:comment
woocommerce/woocommerce#999:review_requested
annchichi/catwatchpr#1:mention
:owner/repo#1
owner/repo#abc:bad_number
EOF
```

- [ ] **Step 2: Run the existing test — expect possible FAIL**

```bash
bash tests/test_inbox_parser.sh
```

If the existing parser already tolerates the new format, this passes immediately. If not, the FAIL output will name the issue.

- [ ] **Step 3: Update inboxNotifs() in menubar.swift**

In `menubar.swift`, find the `inboxNotifs()` function and update its line-parser to handle both formats. The function should return entries that include both a display label and a URL-resolution hint:

```swift
struct InboxEntry { let display: String; let url: URL? }

func inboxNotifs() -> [InboxEntry] {
    let inboxFile = configDir.appendingPathComponent("inbox")
    guard let raw = try? String(contentsOf: inboxFile, encoding: .utf8) else { return [] }

    var entries: [InboxEntry] = []
    for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { continue }
        let ref = String(parts[0]).trimmingCharacters(in: .whitespaces)
        let reason = String(parts[1]).trimmingCharacters(in: .whitespaces)
        guard !ref.isEmpty, !reason.isEmpty else { continue }

        // Two valid shapes: "owner/repo#N" (new) or "N" (legacy).
        let qualified = ref.range(of: #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+$"#,
                                   options: .regularExpression) != nil
        let legacy = ref.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil
        guard qualified || legacy else { continue }

        let display = qualified ? "\(ref) (\(reason))" : "PR #\(ref) (\(reason))"
        let url: URL? = {
            if qualified, let hash = ref.firstIndex(of: "#") {
                let repo = ref[..<hash]
                let num  = ref[ref.index(after: hash)...]
                return URL(string: "https://github.com/\(repo)/pull/\(num)")
            }
            return nil  // legacy lines have no URL — they get cleared on the next watch tick
        }()
        entries.append(InboxEntry(display: display, url: url))
    }
    return entries
}
```

(Adapt to whatever return type `inboxNotifs()` previously had — likely `[String]`. If callers use a richer type, define `InboxEntry` and update them.)

- [ ] **Step 4: Run inbox parser test — expect PASS**

```bash
bash tests/test_inbox_parser.sh
```

Expected: `PASS: menubar.swift survived malformed inbox (parser exited 0)`.

- [ ] **Step 5: Build and verify**

```bash
bash build_app.sh 2>&1 | tail -5
```

Expected: `✓ Built: ...`.

- [ ] **Step 6: Commit**

```bash
git add menubar.swift tests/test_inbox_parser.sh
git commit -m "feat(menubar): parse both legacy and qualified PR refs in inbox

The inbox can transiently contain both bare-number lines (from a
pre-v0.2.0 watch tick) and qualified owner/repo#N lines (from
v0.2.0+). Parser tolerates both shapes; legacy lines display as
'PR #N' with no URL (they get overwritten on the next watch tick).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Update woo_cat.swift display and URL construction

**Files:**
- Modify: `woo_cat.swift`

- [ ] **Step 1: Audit how PR refs flow into the popup**

```bash
grep -n "active_pr\|merged_list\|PR #" woo_cat.swift
```

The popup receives a comma-separated list of PR identifiers via command-line args (driven by `swift "$DIR/woo_cat.swift" ...` in `watch.sh`). Each entry now arrives as either `owner/repo#N:reason` (new active list) or `owner/repo#N` (new merged list).

- [ ] **Step 2: Update display labels**

For any code that formats a PR identifier as `"#\(pr)"` or similar, switch to a helper that handles both shapes:

```swift
func displayRef(_ raw: String) -> String {
    // raw is either "owner/repo#N" or "N" (legacy)
    if raw.contains("#") { return raw }   // already qualified
    return "#\(raw)"                       // legacy bare number
}

func githubURL(forRef raw: String) -> URL? {
    guard let hash = raw.firstIndex(of: "#") else { return nil }
    let repo = raw[..<hash]
    let num  = raw[raw.index(after: hash)...]
    return URL(string: "https://github.com/\(repo)/pull/\(num)")
}
```

Replace the inline `"#\(pr)"` and inline URL constructions throughout `woo_cat.swift` with calls to these helpers.

- [ ] **Step 3: Build and verify**

```bash
bash build_app.sh 2>&1 | tail -5
```

Expected: `✓ Built: ...`.

- [ ] **Step 4: Commit**

```bash
git add woo_cat.swift
git commit -m "feat(woo_cat): show qualified refs and link to correct repo

The popup now displays 'owner/repo#N' for v0.2.0 entries and falls
back to 'PR #N' for any legacy bare-number entries left over from a
pre-upgrade tick. URL construction reads the repo from the ref
itself instead of relying on a global config.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: Update tests/test_install_uninstall.sh

**Files:**
- Modify: `tests/test_install_uninstall.sh`

- [ ] **Step 1: Drop the `<repo>` arg and the repo-file assertions**

Find this line:

```bash
HOME="$TMP" "$BIN" install "annchichi/test-repo" || {
```

Replace with:

```bash
HOME="$TMP" "$BIN" install || {
```

Then remove these assertions:

```bash
test -f "$TMP/.config/woo-sprinkles/repo" || { echo "FAIL: repo file missing"; exit 1; }
[ "$(cat "$TMP/.config/woo-sprinkles/repo")" = "annchichi/test-repo" ] \
    || { echo "FAIL: repo file wrong content"; exit 1; }
```

And the matching one in the uninstall section:

```bash
test -f "$TMP/.config/woo-sprinkles/repo" \
    || { echo "FAIL: uninstall wiped repo file (should be soft)"; exit 1; }
```

Update the success message:

```bash
echo "  ✓ install wrote 3 plists"   # was "wrote 3 plists + repo config"
echo "  ✓ uninstall removed plists"  # was "removed plists, kept config"
```

- [ ] **Step 2: Run the test — expect PASS**

```bash
bash tests/test_install_uninstall.sh
```

Expected: `PASS: install / uninstall / reset all work.`.

- [ ] **Step 3: Commit**

```bash
git add tests/test_install_uninstall.sh
git commit -m "test(install): drop repo arg and repo-file assertions

v0.2.0 install no longer writes a repo config, so the test no longer
passes a repo arg or asserts the file's presence/contents.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 11: Update README install section

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the wizard description**

In `README.md`, find the section that describes the wizard:

```markdown
A small wizard then walks you through:

1. **Welcome**
2. **GitHub auth check** — if you're not logged into `gh`, it copies the right command to your clipboard
3. **Pick a repo to watch** — it suggests one; you can change it
4. **Install** — sets up three background agents (watch, sync, menu bar)
5. **Pick your cat** — Mochi, Boba, Matcha, or Miso
```

Replace with:

```markdown
A small wizard then walks you through:

1. **Welcome**
2. **GitHub auth check** — if you're not logged into `gh`, it copies the right command to your clipboard
3. **Install** — sets up three background agents (watch, sync, menu bar)
4. **Pick your cat** — Mochi, Boba, Matcha, or Miso
```

- [ ] **Step 2: Update any "watching <repo>" mentions**

Search for and update any other text that implies single-repo behavior:

```bash
grep -n "watching\|repo" README.md
```

Replace mentions of "watch a repo" / "the configured repo" with "watch any PR you're involved in across GitHub" or similar.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: README install no longer mentions a repo-picker step

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 12: Bump version, build, release v0.2.0

**Files:**
- Modify: `build_app.sh`

- [ ] **Step 1: Bump version**

In `build_app.sh`, change:

```
<key>CFBundleShortVersionString</key><string>0.1.6</string>
```

to:

```
<key>CFBundleShortVersionString</key><string>0.2.0</string>
```

- [ ] **Step 2: Run all tests**

```bash
bash tests/test_watch_sh.sh
bash tests/test_inbox_parser.sh
bash tests/test_install_uninstall.sh
```

Expected: all three pass.

- [ ] **Step 3: Build .dmg and .zip**

```bash
bash build_app.sh
ditto -c -k --sequesterRsrc --keepParent CatWatchPR.app CatWatchPR.app.zip
ls -lh CatWatchPR.dmg CatWatchPR.app.zip
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" CatWatchPR.app/Contents/Info.plist
```

Expected: build succeeds, both artifacts present, version reads `0.2.0`.

- [ ] **Step 4: Deploy locally and smoke-test**

```bash
rm -rf /Applications/CatWatchPR.app
cp -R CatWatchPR.app /Applications/CatWatchPR.app
open /Applications/CatWatchPR.app
```

Manually verify in the control panel:
- Header reads `~ watching wherever you're involved ~`
- No "change repo" link in the footer
- Version label shows `v0.2.0`
- After ~5 min the watch fires (or kickstart it: `launchctl kickstart -k "gui/$UID/com.annchiahui.woo-sprinkles.watch"`)
- `/tmp/woo-sprinkles-watch.err` is empty post-tick
- `~/.config/woo-sprinkles/prev_open_prs` contains `owner/repo#N` lines

- [ ] **Step 5: Commit version bump**

```bash
git add build_app.sh
git commit -m "chore: bump to 0.2.0

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 6: Push, tag, release**

```bash
git push origin main
git tag -a v0.2.0 -m "v0.2.0 — Watch all your involved PRs everywhere"
git push origin v0.2.0
gh release create v0.2.0 \
  --repo annchichi/catwatchpr \
  --title "v0.2.0 — Watch all your involved PRs everywhere" \
  --notes-file <(cat <<'EOF'
## What's new

CatWatchPR now watches **any PR you authored or were requested to review, across all of GitHub** — not just one configured repo. The wizard's repo-picker step is gone; the control panel's "change repo" link is gone.

## Upgrading from v0.1.x

Same one-step upgrade as before:

1. Drag the new `CatWatchPR.app` into `/Applications` (replace existing).
2. Run `xattr -cr /Applications/CatWatchPR.app` in Terminal.
3. Open `CatWatchPR.app`.

The first watch tick after upgrade will repopulate cached state in the new format. (Existing inbox/cache lines from v0.1.x are silently skipped, then overwritten with the new format on the next successful tick.)

## Under the hood

- Internal PR refs switched from bare numbers to `owner/repo#N` everywhere.
- The watch script now preserves state files when GitHub API calls fail, so transient errors no longer corrupt the cache.

Two formats below — `.dmg` first, `.zip` as a fallback for clients that block disk images.
EOF
) \
  CatWatchPR.dmg CatWatchPR.app.zip
```

- [ ] **Step 7: Verify release URL works**

```bash
gh release view v0.2.0 --repo annchichi/catwatchpr --json url --jq '.url'
```

Open the URL in a browser; confirm both `CatWatchPR.dmg` and `CatWatchPR.app.zip` are listed.

---

## Self-Review Notes

- **Spec coverage:** All sections of the spec are addressed. Behavior change → Tasks 2–3. Code changes → Tasks 4–9. State migration → Tasks 2 + 8 (legacy-tolerant parsing). Edge cases → Task 3. Versioning → Task 12.
- **TDD applied:** Tasks 1, 8, 10 use real failing-test-first cycles. Other tasks rely on build-pass + manual smoke verification because the launcher GUI lacks unit-test infrastructure (and adding one is out of scope per spec's "what we will NOT do").
- **Type consistency:** `parse_pr_ref` consistently returns `"OWNER REPO NUMBER"` (space-separated, three tokens) across Tasks 1, 2, 3. `read_qualified_refs` returns one ref per line. `InboxEntry` (if introduced in Task 8) needs to match how the menu builder consumes it — agent should grep the menubar code for current consumers and adapt accordingly.
- **No placeholders:** all code blocks are complete; commit messages are spelled out.
