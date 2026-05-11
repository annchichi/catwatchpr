# CatWatchPR / Woo Sprinkles

A pixel cat lives in your Mac menu bar and quietly watches your GitHub pull requests for you.

- It pops up when someone comments, requests a review, or mentions you — so you're never the person who missed a notification
- When your PR gets merged, it throws confetti
- The cat only shows up when something needs your attention, then disappears — no noise, no constant pinging. Your notifications wait quietly in the menu bar whenever you're ready

| | | |
|---|---|---|
| ![notification](docs/notification.png) | ![synced](docs/synced.png) | ![confetti](docs/confetti.png) |

---

## What it does

- **Pops up** when someone comments on your PR, requests a review, or mentions you
- **Celebrates** with confetti when a PR gets merged
- **Lives in your menu bar** as a pixel cat face — click to see pending notifications
- **Lets you switch cats** depending on your mood

## The cats

| Name | Color | Personality |
|------|-------|-------------|
| Mochi | cyan | friendly, default |
| Boba | pink | warm and excited |
| Matcha | lime | minimal, no-nonsense |
| Miso | ghost / pale purple | soft and dreamy |

---

## Requirements

- macOS

That's it.

---

## Install

1. Download the latest **`CatWatchPR.dmg`** from [Releases](https://github.com/annchichi/catwatchpr/releases).
2. Double-click the DMG to open it. A window opens with `CatWatchPR.app` and a shortcut to `Applications` — drag the app onto the shortcut.
3. Eject the DMG (right-click the disk icon on your desktop → *Eject*, or drag it to the Trash).
4. **Tell macOS to trust the app.** Because the app isn't signed by an Apple-registered developer, macOS will refuse to open it the first time and claim it's "damaged" (it isn't). Paste this one command in Terminal:

   ```bash
   xattr -cr /Applications/CatWatchPR.app
   ```

   No output means it worked. Double-click `CatWatchPR.app` to launch it.

A small wizard then walks you through:

1. **Welcome**
2. **GitHub auth check** — if you're not logged into `gh`, it copies the right command to your clipboard
3. **Install** — sets up three background agents (watch, sync, menu bar)
4. **Pick your cat** — Mochi, Boba, Matcha, or Miso

That's it. The cat is now in your menu bar, watching your PRs.

---

## Usage

Click the cat in your menu bar to see pending notifications or switch cats.

Open `CatWatchPR.app` again any time to get the **control panel** — status, *Restart all*, *Activity* logs, switch cat, or remove the app.

---

## Customise

From the control panel (open `CatWatchPR.app`):

- **Switch cat** — Mochi, Boba, Matcha, Miso
- **Restart all** — restart the three background agents
- **Remove** — soft uninstall (your config is kept)
- **Reset everything** — wipe state and start over

---

## Built with

- Swift + AppKit — pixel cat rendering, animations, spring physics
- Bash — GitHub CLI polling, launchd scheduling
- Claude — AI pair that turned the idea into working code

---

*Made by a designer who missed her PR pings once too often.*
