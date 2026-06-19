# Startup Update Notification Design

## Goal

CatWatchPR should gently notify installed users when a newer GitHub Release is available, without requiring them to manually choose **Check for Updates...**.

## Behavior

- The menu-bar agent checks for updates once when it starts.
- It uses the existing GitHub Releases endpoint: `https://api.github.com/repos/annchichi/catwatchpr/releases/latest`.
- If the latest release version is newer than the installed `CFBundleShortVersionString`, show the existing update alert with:
  - `Open release page`
  - `Later`
- If the user has already been auto-prompted for that exact remote version, do not show the automatic alert again.
- Manual **Check for Updates...** always checks and can show alerts/errors regardless of prior auto prompts.
- Failed automatic checks are silent. No alert for offline/GitHub/API failures.

## State

Store the last auto-prompted remote version in:

`~/.config/woo-sprinkles/last_update_prompt_version`

Write the version when the automatic prompt is shown, not when the user clicks a button. This prevents repeated nags for the same version.

## Scope

This is an update notification, not an auto-updater. Users still download/install the `.dmg` themselves from the release page.

## Testing

- Add a pure helper for deciding whether to auto-prompt.
- Test that a newer version prompts.
- Test that the same previously prompted version does not prompt again.
- Test that older/equal versions do not prompt.
- Compile `menubar.swift`.
