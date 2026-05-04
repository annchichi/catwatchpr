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
- Swift (comes with Xcode or `xcode-select --install`)

Everything else (Homebrew, GitHub CLI, GitHub login) is handled automatically by `setup.sh`.

---

## Install

```bash
git clone https://github.com/annchichi/catwatchpr.git ~/tools/woo-sprinkles
cd ~/tools/woo-sprinkles
bash setup.sh
```

This installs three background agents:
- **watch** — checks GitHub notifications every 5 minutes
- **sync** — syncs your open PR branches at 9am daily
- **menubar** — keeps the cat face in your menu bar

---

## Usage

**Switch cats:**
```bash
bash ~/tools/woo-sprinkles/switch-cat.sh mochi
bash ~/tools/woo-sprinkles/switch-cat.sh boba
bash ~/tools/woo-sprinkles/switch-cat.sh matcha
bash ~/tools/woo-sprinkles/switch-cat.sh miso
```
Or use the menu bar dropdown — hover over "Switch cat".

**Test the popup:**
```bash
swift ~/tools/woo-sprinkles/woo_cat.swift 0 0 0 cyan "12345:comment" 0 0 0 1
```

**Test confetti:**
```bash
swift ~/tools/woo-sprinkles/woo_cat.swift 0 0 0 cyan "" 0 0 0 0 "" "12345"
```

**Run the watch script manually:**
```bash
bash ~/tools/woo-sprinkles/watch.sh
```

---

## Customise

`setup.sh` will ask which repo you want to watch during install. If you want to change it later, update the `REPO` variable at the top of `watch.sh` and `sync.sh`:

```bash
REPO="your-org/your-repo"
```

---

## Built with

- Swift + AppKit — pixel cat rendering, animations, spring physics
- Bash — GitHub CLI polling, launchd scheduling
- Claude — AI pair that turned the idea into working code

---

*Made by a designer who missed her PR pings once too often.*
