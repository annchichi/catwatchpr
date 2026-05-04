# Setup Onboarding Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Modify `setup.sh` so a new user can clone the repo and run `bash setup.sh` with no prior setup — the script installs prerequisites, authenticates GitHub, prompts for their repo, and patches the config files automatically.

**Architecture:** All new logic is added at the top of `setup.sh` as a sequential preflight block. Each check either auto-resolves or exits with a clear message. After preflight, the existing install steps run unchanged. `watch.sh` and `sync.sh` are patched in-place with `sed`.

**Tech Stack:** Bash, Homebrew, GitHub CLI (`gh`), macOS `sed`, `launchctl`

---

### Task 1: Add Homebrew check and install

**Files:**
- Modify: `setup.sh` (add before line 1's existing content, after the shebang)

- [ ] **Step 1: Open `setup.sh` and add the Homebrew check block**

After the `#!/bin/bash` line and before the `# Install Woo Sprinkles launchd agents` comment, insert:

```bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Preflight ────────────────────────────────────────────────────────────────

# 1. Homebrew
if ! command -v brew &>/dev/null; then
    echo "→ Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    echo ""
    echo "✓ Homebrew installed."
    echo "  Please close this terminal, open a new one, then run setup.sh again."
    exit 0
fi
```

- [ ] **Step 2: Remove the original `DIR` line from the existing code**

The original `setup.sh` has `DIR=...` on line 5. Delete that line — it's now defined at the top of the preflight block. Use your editor or:
```bash
grep -n "^DIR=" setup.sh
```
Find and delete that duplicate line.

- [ ] **Step 3: Verify the block is syntactically valid**

Run:
```bash
bash -n setup.sh
```
Expected: no output (no errors)

- [ ] **Step 4: Commit**

```bash
git add setup.sh
git commit -m "feat: check and install Homebrew in setup.sh"
```

---

### Task 2: Add `gh` CLI check and install

**Files:**
- Modify: `setup.sh` (add after the Homebrew block from Task 1)

- [ ] **Step 1: Add the `gh` install block**

After the Homebrew block, insert:

```bash
# 2. GitHub CLI
if ! command -v gh &>/dev/null; then
    echo "→ Installing GitHub CLI..."
    brew install gh
fi
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n setup.sh
```
Expected: no output

- [ ] **Step 3: Commit**

```bash
git add setup.sh
git commit -m "feat: auto-install gh CLI if missing"
```

---

### Task 3: Add GitHub authentication check

**Files:**
- Modify: `setup.sh` (add after the `gh` install block from Task 2)

- [ ] **Step 1: Add the auth check block**

After the `gh` install block, insert:

```bash
# 3. GitHub auth
if ! gh auth status &>/dev/null; then
    echo "→ Let's log you into GitHub..."
    gh auth login
fi
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n setup.sh
```
Expected: no output

- [ ] **Step 3: Commit**

```bash
git add setup.sh
git commit -m "feat: run gh auth login if not authenticated"
```

---

### Task 4: Add repo detection and prompt

**Files:**
- Modify: `setup.sh` (add after the auth block from Task 3)

- [ ] **Step 1: Add repo detection block**

After the auth block, insert:

```bash
# 4. Repo selection
gh_user=$(gh api /user --jq .login 2>/dev/null)
DEFAULT_REPO="woocommerce/woocommerce"

if gh api "/orgs/woocommerce/members/$gh_user" --silent 2>/dev/null; then
    # User is in the woocommerce org — suggest the default
    read -rp "Watch $DEFAULT_REPO? [Y/n] " repo_confirm
    repo_confirm="${repo_confirm:-Y}"
    if [[ "$repo_confirm" =~ ^[Yy]$ ]]; then
        CHOSEN_REPO="$DEFAULT_REPO"
    else
        read -rp "Which repo? (format: org/repo) " CHOSEN_REPO
    fi
else
    read -rp "Which GitHub repo do you want to watch? (format: org/repo) " CHOSEN_REPO
fi

# Validate format
if [[ ! "$CHOSEN_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    echo "✗ Invalid repo format. Expected: org/repo (e.g. mycompany/myrepo)"
    exit 1
fi
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n setup.sh
```
Expected: no output

- [ ] **Step 3: Commit**

```bash
git add setup.sh
git commit -m "feat: detect woocommerce org membership and prompt for repo"
```

---

### Task 5: Patch watch.sh and sync.sh with chosen repo

**Files:**
- Modify: `setup.sh` (add after repo detection block from Task 4)

- [ ] **Step 1: Add the sed patch block**

After the repo detection block, insert:

```bash
# 5. Patch repo into config files
sed -i '' "s|^REPO=.*|REPO=\"$CHOSEN_REPO\"|" "$DIR/watch.sh"
sed -i '' "s|^REPO=.*|REPO=\"$CHOSEN_REPO\"|" "$DIR/sync.sh"
echo "✓ Watching: $CHOSEN_REPO"
echo ""
```

- [ ] **Step 2: Manually test the patch**

Run these commands to simulate what setup.sh will do, then check the result:
```bash
# From the woo-sprinkles directory:
CHOSEN_REPO="test-org/test-repo"
sed -i '' "s|^REPO=.*|REPO=\"$CHOSEN_REPO\"|" watch.sh
grep "^REPO=" watch.sh
```
Expected output: `REPO="test-org/test-repo"`

Reset it back:
```bash
sed -i '' "s|^REPO=.*|REPO=\"woocommerce/woocommerce\"|" watch.sh
sed -i '' "s|^REPO=.*|REPO=\"woocommerce/woocommerce\"|" sync.sh
```

- [ ] **Step 3: Verify full setup.sh syntax**

```bash
bash -n setup.sh
```
Expected: no output

- [ ] **Step 4: Commit**

```bash
git add setup.sh
git commit -m "feat: auto-patch REPO in watch.sh and sync.sh during setup"
```

---

### Task 6: End-to-end manual test

- [ ] **Step 1: Do a dry-run read-through**

Read through `setup.sh` top to bottom and confirm the order is:
1. Homebrew check
2. `gh` check
3. auth check
4. repo detection + prompt
5. `sed` patch
6. existing install steps (chmod, plist copy, launchctl, greeting)

- [ ] **Step 2: Run with bash dry-run flag**

```bash
bash -n setup.sh
```
Expected: no output

- [ ] **Step 3: Commit the plan doc**

```bash
git add docs/superpowers/plans/2026-05-04-setup-onboarding.md
git commit -m "docs: add setup onboarding implementation plan"
```
