# Watch All Involved PRs (No Repo Filter) — Design

**Date:** 2026-05-09
**Author:** Ann (via Claude collaboration)
**Status:** Approved for implementation planning
**Target version:** v0.2.0

## Summary

CatWatchPR currently watches a single user-selected repo. Real users — Ann included — work across multiple repos (woocommerce, catwatchpr, others) and were silently missing notifications on PRs in repos other than the configured one. v0.2.0 removes the repo filter entirely. The watch script asks GitHub for "any PR you authored or are reviewer on, anywhere," plus all unread PR notifications, and fires the cat the same way it does today. The wizard's repo-picker step is removed; the control panel's "change repo" link is removed; the deployed launch agents and stored config no longer carry a repo value.

Net effect: open the app, the cat watches every PR you're involved in across all of GitHub. Designer or engineer, single project or many, behavior is identical.

## Goals

- **Match the user's mental model.** A user opens CatWatchPR expecting "watch my PRs." Today it watches PRs in *one* repo, which is a footgun.
- **Drop unnecessary configuration.** The repo picker, the change-repo flow, and the wizard step that asks for a repo all go away.
- **Preserve all existing fire conditions.** Author/reviewer activity, merges, CI changes, comments, mentions — all still trigger the cat.
- **Defensive failure handling.** If GitHub returns errors (rate limit, outage, auth issue), the watch must not corrupt its state files. Next tick retries cleanly.

## Non-goals

- **No focus mode.** No toggle to limit the watch to one repo. (Deferred — can be added in v0.2.x if real users ask for it.)
- **No per-repo mute or exclusion lists.** Users who want to silence a noisy repo go to GitHub's notification settings.
- **No multi-account / org-scoped support.** One authed `gh` user, all their involved PRs.
- **No user-facing rate-limit indicator (yet).** State preservation on API failure is in scope; surfacing "we're rate-limited until X" in the menu bar is deferred.

## Behavior

The watch script, run every 5 minutes by `com.annchiahui.woo-sprinkles.watch`, performs:

1. **Fetch involved PRs** — union of:
   - `gh pr list --author "@me" --state open` (no `--repo`)
   - `gh pr list --search "review-requested:@me" --state open` (no `--repo`)
   - Both queries return enough JSON to construct fully-qualified PR refs (`owner/repo#number`).

2. **Detect merges** — PRs in the previous tick's `prev_open_prs` cache that are no longer in the current involved-PR set get checked via `gh pr view #N --repo OWNER/REPO`. Those that come back `MERGED` trigger the celebration cat and are removed from the inbox.

3. **CI watching** — for each currently-open involved PR, `gh pr checks #N --repo OWNER/REPO`. Same logic as today (transition from pending to pass/fail fires the cat).

4. **Fetch unread PR notifications** — `gh api notifications --jq '[.[] | select(.unread == true and .subject.type == "PullRequest")] | ...'`. The `repository.full_name == "$REPO"` filter from today is removed. Each notification's `subject.url` is parsed to extract the PR's repo and number.

5. **Filter notifications to involved PRs** — keep only notifications whose `(repo, number)` matches the current involved-PR set. (This is the same membership check the script does today, just keyed on tuples instead of bare numbers.)

6. **Fire the cat** for new notification IDs not in `seen_notif_ids`.

The cat popup itself (`woo_cat.swift`) is unchanged in logic; it just receives a different shape of PR list. Display format is `owner/repo#N` rather than bare `#N` so users can tell which repo the notification came from.

## Code changes

### `watch.sh`

- Remove the `$REPO` variable and the early-exit if the config file is missing.
- Remove `--repo "$REPO"` from all `gh pr list` and `gh pr view` calls. Keep `--repo` on per-PR calls (`gh pr checks`, `gh pr view #N`) because gh requires a repo for those, but pass it from the PR's own `headRepository` field instead of a global config.
- Remove the `.repository.full_name == "$REPO"` jq filter on the notifications query.
- Switch internal data structures from bare PR numbers to `owner/repo#number` strings everywhere (`my_prs`, `prev_open_prs`, `inbox`, `ci_watching`).
- Wrap critical `gh` calls (involved-PRs fetch, notifications fetch) in exit-code checks. On non-zero exit, the script exits without overwriting any state file. Next tick (5 min later) tries again from a clean state.

### Launcher (Swift)

- Remove `WizardStep.repoPicker` and `RepoPickerView`. The wizard becomes Welcome → AuthCheck → Install → CatPicker → AllDone (4 steps, was 5).
- `Installer.install()` no longer takes a `repo:` parameter. Plist substitution and `launchctl` calls are unchanged.
- `Installer.install` CLI subcommand becomes `CatWatchPR install` (no repo arg). Update `tests/test_install_uninstall.sh` accordingly.
- `ControlPanelView`: remove the "change repo" link and the entire `RepoEditorSheet`. Header text changes from `~ watching <repo> ~` to `~ watching wherever you're involved ~`.
- `AppState`: remove `hasRepoConfig`, `status.repo`. Control-panel mode is gated on `isInstalled` alone.
- `LauncherApp.refreshDeployedPlists()`: drops the repo-file existence check; just guards on `menubarPlist` existing. Calls `Installer.install()` with no args.

### State files (`~/.config/woo-sprinkles/`)

- `prev_open_prs`: each line is `owner/repo#number`.
- `inbox`: each line is `owner/repo#number:reason`.
- `ci_watching`: each line is `owner/repo#number`.
- `repo` file: deprecated. Deleted on first v0.2.0 launch (one-time cleanup in `LauncherApp.refreshDeployedPlists`).

### Cat popup (`woo_cat.swift`)

- Accepts the same comma-separated PR list it does today, but each entry can now be either bare `#N` (legacy) or `owner/repo#N` (new). Display logic shows the `owner/repo` prefix when present.
- "Open in browser" actions construct full URLs from the qualified ref instead of relying on a global `$REPO`.

### Menubar (`menubar.swift`)

- Inbox parser: handles both legacy (`number:reason`) and new (`owner/repo#number:reason`) line formats during the migration window. After the v0.2.0 first-launch cleanup, all entries are in the new format.
- "Open all notifications" menu item: constructs the GitHub URL list from qualified refs.

## Migration

Migration is handled implicitly by `watch.sh` itself rather than by a one-time cleanup step in the launcher. This is more robust because the watch ticker always runs every 5 minutes regardless of whether the user opens the .app, whereas a launcher-side migration would only fire when the GUI is opened.

When `watch.sh` reads its state files (`prev_open_prs`, `inbox`, `ci_watching`, `seen_notif_ids`), it tolerates both legacy (bare-number) and new (`owner/repo#number`) line formats. Lines in legacy format are silently skipped during reads — they convey no usable info to the new logic. When `watch.sh` writes back, it always writes the new format. Within one tick after upgrade, all state files are fully migrated.

The legacy `~/.config/woo-sprinkles/repo` file is no longer read by anything. It's left in place after upgrade rather than proactively deleted (harmless on disk, simpler code path). If the user ever clicks "remove" in the control panel, the existing reset logic wipes the entire `~/.config/woo-sprinkles` directory and the file goes with it.

Trade-off accepted: the user loses ~5 minutes of cached state on first new tick (because legacy `prev_open_prs` lines are skipped, so merge detection can't celebrate any PR that merged in the last interval). Acceptable; merge detection is a small slice of the value and 5 min of cached state is short-lived.

## Edge cases & failure modes

- **GitHub API failure on critical calls:** script exits without touching state files. Next tick retries.
- **GitHub API rate limiting:** worst-case math at 20 open involved PRs is ~240 calls/hour, well under the 5000/hour authed limit. If a user somehow hits it, the state-preservation guard above kicks in and the watch silently retries until the limit resets. No false-positive notifications, no lost state.
- **User has zero involved PRs:** script exits cleanly after the first fetch. No errors, no popups.
- **`gh` not authed or missing:** same graceful failure as today (early exit).
- **High-volume edge case (100+ involved PRs):** still under rate limit, but the per-tick wall time grows. Acceptable — script runs in background, user doesn't see it.
- **Old state file format leftover:** if for any reason migration didn't fire (e.g., user manually copied state from another machine), the menubar parser tolerates both formats during reads, and the watch script overwrites with the new format on its next successful tick.

## Release notes (draft)

> **v0.2.0 — Watch all your PRs everywhere**
>
> CatWatchPR no longer needs you to pick a single repo. It now watches **any PR you authored or were requested to review, across all of GitHub**, and fires the cat for the same activity types as before (comments, reviews, merges, CI). The wizard's repo-picker step is gone; the control panel's "change repo" link is gone.
>
> Existing users: open the app once after upgrading. The watch will start covering all your PRs from the next 5-minute tick.

## What we explicitly will NOT do

- No focus-mode toggle.
- No exclusion / mute lists.
- No multi-account or organization-scoped variants.
- No in-place migration of old state-file formats (we wipe and repopulate).
- No user-facing rate-limit indicator in v0.2.0 (defer to v0.2.x if needed).
