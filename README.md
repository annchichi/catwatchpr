# CatWatchPR / Woo Sprinkles

A pixel cat that lives on your macOS desktop and watches your GitHub PRs.

Built for WooCommerce contributors who miss notifications, lose track of review requests, and never get to celebrate a merge properly.

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
- [GitHub CLI](https://cli.github.com/) (`gh`) — logged in
- Swift (comes with Xcode or `xcode-select --install`)

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

The repo is currently set up for the `woocommerce/woocommerce` repo. To use it for a different repo, change the `REPO` variable in `watch.sh` and `sync.sh`.

---

## Built with

- Swift + AppKit — pixel cat rendering, animations, spring physics
- Bash — GitHub CLI polling, launchd scheduling
- Claude — AI pair that turned the idea into working code

---

*Made by a designer who missed her PR pings once too often.*
