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

That's it. (To build from source you'll also need Swift via `xcode-select --install`.)

---

## Install

1. Download the latest **`CatWatchPR.app.zip`** from [Releases](https://github.com/annchichi/catwatchpr/releases).
2. Unzip it and drag `CatWatchPR.app` into `/Applications`.
3. **Tell macOS to trust the app.** Because the app isn't signed by an Apple-registered developer, macOS will refuse to open it the first time and claim it's "damaged" (it isn't). Paste this one command in Terminal:

   ```bash
   xattr -cr /Applications/CatWatchPR.app
   ```

   No output means it worked.
4. **Right-click `CatWatchPR.app` → *Open*.** macOS may ask once more whether you really want to open it — click *Open*. After that, it opens normally.

A small wizard then walks you through:

1. **Welcome**
2. **GitHub auth check** — if you're not logged into `gh`, it copies the right command to your clipboard
3. **Pick a repo to watch** — it suggests one; you can change it
4. **Install** — sets up three background agents (watch, sync, menu bar)
5. **Pick your cat** — Mochi, Boba, Matcha, or Miso

That's it. The cat is now in your menu bar, watching your PRs.

---

## Usage

Click the cat in your menu bar to see pending notifications or switch cats.

Open `CatWatchPR.app` again any time to get the **control panel** — status, *Restart all*, *Activity* logs, switch cat, change repo, or remove the app.

---

## Customise

From the control panel (open `CatWatchPR.app`):

- **Switch cat** — Mochi, Boba, Matcha, Miso
- **Change repo** — point the watcher at a different repo
- **Restart all** — restart the three background agents
- **Remove** — soft uninstall (your config is kept)
- **Reset everything** — wipe state and start over

---

## Build from source

If you'd rather build the app yourself, you'll need Swift (`xcode-select --install`).

```bash
git clone https://github.com/annchichi/catwatchpr.git ~/tools/woo-sprinkles
cd ~/tools/woo-sprinkles
bash build_app.sh
```

Then drag the resulting `CatWatchPR.app` into `/Applications` and follow the install steps above.

### Test the popup

```bash
swift ~/tools/woo-sprinkles/woo_cat.swift 0 0 0 cyan "12345:comment" 0 0 0 1
```

### Test confetti

```bash
swift ~/tools/woo-sprinkles/woo_cat.swift 0 0 0 cyan "" 0 0 0 0 "" "12345"
```

### Run the watch script manually

```bash
bash ~/tools/woo-sprinkles/watch.sh
```

---

## Built with

- Swift + AppKit — pixel cat rendering, animations, spring physics
- Bash — GitHub CLI polling, launchd scheduling
- Claude — AI pair that turned the idea into working code

---

*Made by a designer who missed her PR pings once too often.*
