# CatWatchPR Launcher — Design

**Date:** 2026-05-07
**Author:** Ann (via Claude collaboration)
**Status:** Approved for implementation planning

## Summary

A self-contained `CatWatchPR.app` macOS launcher that wraps the existing Woo
Sprinkles project. First launch walks a teammate through onboarding (auth check,
repo picker, install). Later launches show a control panel for status, restart,
logs, switching cats, changing repo, and uninstall. Visual style matches the
popup cat (pixel / terminal aesthetic). Includes a fix for the current
`menubar.swift` "Index out of range" crash and a per-user repo config refactor.

## Goals

- A teammate can install CatWatchPR by double-clicking one `.app` file. No
  cloning, no shell setup, no `launchctl` knowledge required.
- A teammate's first install watches *their* PRs, not the bundle's defaults.
- When the menu bar agent fails, the user can recover from the launcher window
  (no terminal commands required).
- Ann can iterate on the scripts inside the app bundle without rebuilding the
  whole app every time.
- The currently-broken menubar agent (relaunch loop on `Index out of range`) is
  fixed as part of this work.

## Non-goals

- Code signing or notarization. Distribution is unsigned with right-click → Open
  for the first launch (Gatekeeper bypass). Revisited if the audience grows.
- Cross-platform support (macOS only).
- Replacing or rewriting the existing menubar agent. We patch the parser bug,
  nothing more.
- Switching the inbox file format (stays plain `pr:reason` per line).

## Architecture

Three pieces ship inside `CatWatchPR.app`:

1. **Launcher UI** — new SwiftUI app. First launch = wizard. Subsequent
   launches = control panel. Detects state on entry and routes accordingly.
2. **Bundled scripts and binaries** — `watch.sh`, `sync.sh`, `cat_popup.swift`,
   `woo_cat.swift`, `switch-cat.sh`, the compiled menubar binary, and plist
   templates. All under `Contents/Resources/`.
3. **Menu bar fix** — patched `menubar.swift`, recompiled into the bundle.

One refactor outside the `.app`:

- `REPO=...` moves from a sed-patched line in `watch.sh` / `sync.sh` to a runtime
  read of `~/.config/woo-sprinkles/repo`. The wizard writes that file during
  install. Source code becomes repo-agnostic.

### Filesystem after install

- `/Applications/CatWatchPR.app` — the only thing the user manages.
- `~/Library/LaunchAgents/com.annchiahui.woo-sprinkles.{watch,sync,menubar}.plist`
  — installed by the wizard, paths point inside the bundle.
- `~/.config/woo-sprinkles/{repo,cat_name,cat_color,inbox,last_checked,...}` —
  runtime state.

## Wizard flow

Five screens in style B (pixel / terminal). Wizard installs *only* on Screen 4
click; closing earlier installs nothing.

1. **Welcome** — pixel cat icon, one-line description, *Get started* button.
2. **GitHub auth check** — runs `gh auth status` on entry.
   - Logged in → green confirmation, *Continue*.
   - Not logged in → instructions, *Copy command* (puts `gh auth login` on
     clipboard), *Re-check* button polls.
3. **Repo picker** — text input pre-filled with a sensible default
   (`gh repo list --limit 1 --json nameWithOwner` if it returns an
   own-org repo, else blank with placeholder). *Continue* disabled until input
   matches `^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$`. This screen guarantees per-user
   repo config (the "their PRs not yours" requirement).
4. **Install** — list of what's about to happen, single *Install* button.
   Behind the scenes:
   - Write `~/.config/woo-sprinkles/repo` from Screen 3 input.
   - Copy plist templates → `~/Library/LaunchAgents/`, substituting the
     `__BUNDLE_PATH__` placeholder with the absolute path to the running
     `CatWatchPR.app` (read at runtime via `Bundle.main.bundlePath`).
   - `launchctl load` each plist.
   - Run `bash watch.sh` once to verify it works against the chosen repo. If
     it fails (network error, repo doesn't exist, etc.), surface the error
     inline with a *Retry* button; the install itself is still considered
     complete since the agents are loaded.
5. **Pick your cat** (post-install delight) — four cards (Mochi / Boba /
   Matcha / Miso) with sample previews. Selecting one writes
   `~/.config/woo-sprinkles/{cat_name,cat_color}` and kicks the menubar agent.
   Drops into the control panel.

If the wizard is closed mid-flow, re-launching resumes at the appropriate step
based on detected state (auth ok? repo file exists? agents loaded?).

## Control panel

Single window. State refresh ~every 2 seconds while window is open.

### State detection

| Signal | Source |
|---|---|
| `menubar` running | `launchctl list` PID + recent-restart heuristic |
| `watch` last ran | `~/.config/woo-sprinkles/last_checked` |
| `sync` scheduled | plist exists in `~/Library/LaunchAgents/` and is loaded |
| `open prs` count | `~/.config/woo-sprinkles/prev_open_prs` |
| Active cat | `~/.config/woo-sprinkles/cat_name` |

**Crash detection:** read `/tmp/woo-sprinkles-menubar.err` and check whether
its tail (last ~5 lines) contains a Swift `Fatal error:` line written within
the last 60 seconds. If yes, treat menubar as crashed regardless of what
`launchctl list` reports — `launchctl` alone can't reliably distinguish
"started cleanly and exited" from "crashing in a relaunch loop". Show alert
banner with the actual error excerpt.

### Layout

Approved in `.superpowers/brainstorm/.../control-panel.html`:

- Title bar with traffic-light dots and "CATWATCHPR" label.
- Header row: cat icon + name + "watching <repo>" tagline.
- Status grid (monospace, single-line rows).
- Alert banner above the grid in crash state.
- Primary action row: **Restart all**, **Activity**.
- Quiet footer row: *switch cat*, *change repo*, *remove* (red, with a small
  *reset everything* link below it).

### Action behaviors

- **Restart all** — unload + load all 3 agents in sequence. In crash state, the
  same button highlights cyan and is the recovery action.
- **Activity** — opens a second window showing the most recent activity from
  all three log files (`/tmp/woo-sprinkles-{watch,sync,menubar}.{log,err}`)
  merged into a single timeline, prefixed with source (`[watch]`, `[sync]`,
  `[menubar]`). Last ~200 lines, refreshed every 2 seconds. Same pixel style.
- **Switch cat** — opens the cat picker (same UI as Wizard Screen 5).
- **Change repo** — small prompt dialog, validates, writes
  `~/.config/woo-sprinkles/repo`, restarts the watch agent.
- **Remove** — soft uninstall: `launchctl unload`, delete plists, leave config
  alone. Below it, a small red **Reset everything** link wipes
  `~/.config/woo-sprinkles/` too.

Closing the window does not quit anything; agents keep running.

## Menu bar bug fix

`menubar.swift:117` crashes on `parts[0]` when `s.split(separator: ":")` returns
empty (Swift defaults `omittingEmptySubsequences: true`, so a line that's just
`":"` produces `[]`).

**Fix:**
- Use `parts.first` and guard for empty.
- Skip lines that don't yield a non-empty `pr` token.

**Cleanup of existing state:**
- The launcher's *Reset everything* covers new installs.
- For Ann's existing install, the launcher's first run rewrites
  `~/.config/woo-sprinkles/inbox` to drop malformed lines.

**Test:** small shell script under `tests/` feeds `menubar.swift` an inbox file
containing malformed lines (`""`, `":"`, `":foo"`, `"foo:"`, `"foo:bar:baz"`)
and confirms it doesn't crash and parses sensibly.

## Build, distribution, testing

### Build

`build_app.sh` (new, ~30 lines bash):
1. Compile `launcher/Launcher.swift` → main executable.
2. Compile `menubar.swift` → `Contents/Resources/MenuBarAgent`.
3. Copy `watch.sh`, `sync.sh`, `cat_popup.swift`, `woo_cat.swift`,
   `switch-cat.sh` → `Contents/Resources/scripts/`.
4. Copy plist templates with `__BUNDLE_PATH__` placeholders →
   `Contents/Resources/launchd/`.
5. Generate `Info.plist`. App icon (`AppIcon.icns`) is built from the existing
   pixel cat sprite in `menubar.swift` using `iconutil` — the build script
   renders the sprite to PNG at the standard `.iconset` sizes, then runs
   `iconutil -c icns`. No designer-supplied icon file required.

Output: `CatWatchPR.app` next to the script. No Xcode required.

### Distribution

Unsigned `.app`, shared via internal channels. Teammates right-click → *Open*
on first launch to bypass Gatekeeper. No notarization for this iteration.

### Testing

Local test loop, fully manual, gates every push:

1. `bash build_app.sh`.
2. Copy `CatWatchPR.app` to `~/Applications/`.
3. Walk through:
   - First run: wizard → install → cat picker → control panel.
   - Healthy state: status grid all green; *Restart all* and *Activity* both
     work.
   - Crash state: artificially break menubar (write garbage to
     `~/.config/woo-sprinkles/inbox`), confirm alert banner appears,
     *Restart all* recovers.
   - Switch cat → menu bar icon updates.
   - Change repo → watch picks up the new repo on its next run.
   - Remove → soft uninstall, plists gone, config kept.
   - *Reset everything* → config wiped too.
4. Only after the above passes → commit and push to the `catwatchpr` GitHub
   repo.

A small `tests/` directory holds the menubar parser smoke test (Section above).

## Delivery sequence

Each step independently testable before moving on.

1. **Menu bar bug fix.** Smallest, highest immediate value (Ann's cat returns).
2. **REPO config refactor.** `REPO=...` moves to `~/.config/woo-sprinkles/repo`.
3. **Launcher app.** Wizard + control panel + `build_app.sh` + bundling.
4. **Smoke tests.** Parser fix regression test under `tests/`.

## Open questions / future work

- **Multi-repo watching.** Currently one repo at a time. If teammates want to
  watch multiple repos, that's a separate project.
- **Code signing / notarization.** Deferred. Re-evaluate if the audience grows
  beyond a small group.
- **Auto-update.** No mechanism to push new versions; teammates download a new
  `.app` manually. Acceptable for current scope.
