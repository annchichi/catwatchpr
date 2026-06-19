# Startup Update Notification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Notify users at menu-bar startup when a newer CatWatchPR GitHub Release is available.

**Architecture:** Reuse the existing `fetchLatestRelease`, `currentAppVersion`, and update alert code in `menubar.swift`. Add a small pure helper for prompt gating, store the last auto-prompted version in `~/.config/woo-sprinkles/last_update_prompt_version`, and call an automatic check once during app startup.

**Tech Stack:** Swift, AppKit, Foundation, Bash test harness.

## Global Constraints

- Automatic update failures must be silent.
- Manual **Check for Updates...** must keep showing errors and up-to-date messages.
- Users still install updates manually from the release page.

---

### Task 1: Add Auto-Prompt Gating And Startup Check

**Files:**
- Modify: `menubar.swift`
- Create: `tests/test_update_prompt_gate.sh`

**Interfaces:**
- Produces: `shouldAutoPromptUpdate(remote:local:lastPrompted:) -> Bool`
- Produces: `checkForUpdatesAutomatically()`

- [ ] **Step 1: Write the failing test**

Create `tests/test_update_prompt_gate.sh` with a Swift harness that extracts `isNewerVersion` and `shouldAutoPromptUpdate` from `menubar.swift`, then checks:

```bash
shouldAutoPromptUpdate(remote: "0.2.9", local: "0.2.8", lastPrompted: nil) == true
shouldAutoPromptUpdate(remote: "0.2.9", local: "0.2.8", lastPrompted: "0.2.9") == false
shouldAutoPromptUpdate(remote: "0.2.8", local: "0.2.8", lastPrompted: nil) == false
shouldAutoPromptUpdate(remote: "0.2.7", local: "0.2.8", lastPrompted: nil) == false
```

- [ ] **Step 2: Verify the test fails**

Run:

```bash
bash tests/test_update_prompt_gate.sh
```

Expected failure: `shouldAutoPromptUpdate` is missing from extracted `menubar.swift`.

- [ ] **Step 3: Implement the helper and startup path**

In `menubar.swift`:

1. Add `updatePromptFile`.
2. Add `shouldAutoPromptUpdate(remote:local:lastPrompted:)`.
3. Add `showUpdateAvailableAlert(info:local:)` to share the alert body.
4. Update manual `checkForUpdates` to use `showUpdateAvailableAlert`.
5. Add `checkForUpdatesAutomatically()` that fetches latest release silently, gates through `shouldAutoPromptUpdate`, writes `last_update_prompt_version`, and shows the alert.
6. Call `checkForUpdatesAutomatically()` once after the app starts and the menu-bar icon is initialized.

- [ ] **Step 4: Verify**

Run:

```bash
bash tests/test_update_prompt_gate.sh
bash tests/test_inbox_parser.sh
swiftc menubar.swift -o /private/tmp/MenuBarAgent-test -framework AppKit -target arm64-apple-macos13.0
```

Expected: all commands exit 0.

- [ ] **Step 5: Commit**

```bash
git add menubar.swift tests/test_update_prompt_gate.sh docs/superpowers/specs/2026-06-19-startup-update-notification-design.md docs/superpowers/plans/2026-06-19-startup-update-notification.md
git commit -m "feat: notify users about updates on startup"
```
