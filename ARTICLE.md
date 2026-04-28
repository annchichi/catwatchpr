# I Made a Pixel Cat to Watch My GitHub PRs (Because I Kept Missing Everything)

I'm a designer. I don't write Swift. I barely write bash. But I built a small macOS app that lives in my menu bar as a pixel cat face, pops up when someone comments on my pull requests, and throws confetti when a PR gets merged.

Here's why, and how.

---

## The itch

Working on a large open source codebase means a lot of pull requests. A lot of waiting. A lot of "did anyone review this yet?" And GitHub notifications — even with all the right settings — have a way of feeling identical. Every ping looks the same in your inbox. A comment on a PR you filed three weeks ago reads exactly like a review request that needs your attention today.

I kept missing things. Comments I should have replied to. Review requests that sat unread. And the merges — the actual moment a PR lands — I'd find out hours later, buried in an email thread, with none of the satisfaction that moment deserves.

It bothered me enough that I started wondering: what if I built something just for me?

---

## The idea

I wanted something that lived outside my inbox. Something that showed up on my screen only when it mattered — a comment on *my* PR, a review request directed at *me* — and then went away. Quiet by default. Present when needed.

And since I was making it for myself, I wanted it to be cute.

I had this image in my head: a tiny pixel cat that walks in from the side of the screen, shows you what's happening, and walks away. Something that made checking GitHub feel less like admin and more like a visit from a small, cheerful creature who happens to know things.

That's where the cats came from.

---

## How I actually built it

I want to be honest here: I couldn't have built this alone. I'm a designer. I know what I want things to feel like. I don't know how to make a macOS app render pixel art, manage animation timers, or hook into the GitHub API from a bash script.

I built this with Claude — an AI — as my technical collaborator. I described what I wanted. We figured it out together. When something didn't feel right, I said so. When the cursor didn't change to a paw when hovering over a notification card, we debugged it. When the confetti didn't feel celebratory enough, we tuned it.

The ideas were mine. The taste was mine. The "this needs to exist" feeling was entirely mine. Claude held the tools I didn't know how to use.

I think that's worth saying plainly, because I've seen people be weird about AI-assisted making — like it doesn't count, or it's cheating somehow. But a designer using a tool they couldn't have built themselves to make something they genuinely needed? That's just how making works. The gap between "I have this idea" and "this idea exists" used to require learning Swift. Now it requires a different kind of collaboration.

---

## What got built

The app is called **Woo Sprinkles** (a working title that stuck) and the cats are called **CatWatchPR**.

There are four cats:

- **Mochi** — cyan, the default. Friendly and neutral.
- **Boba** — pink. Warm and a little excitable. Her notifications say things like *"someone commented!"* with an exclamation mark.
- **Matcha** — lime green. No-nonsense. Her notifications just say *"comment"* and *"review needed"*. She snaps onto the screen instead of bouncing.
- **Miso** — pale purple. Soft and dreamy. Everything she says trails off with an ellipsis. She floats in slowly.

Each cat has a pixel sprite, a colour palette, a personality that shows up in the notification text, and a distinct entry animation. Mochi bounces. Boba overshoots. Matcha snaps. Miso drifts.

When a PR gets merged, the cat throws confetti.

When you hover over a notification card, the cursor changes to a pixel paw.

If you drag the cat out of the way, the notification cards have a spring physics wobble — they lag behind the cat's movement like they're attached by elastic.

These details matter to me. Not because they make the app more functional, but because they make it feel like something I actually want to use. Delight isn't decoration. It's what makes a tool feel like yours.

---

## The menu bar

The cat lives in your menu bar as a small pixel face — 12×18 pixels, rendered in whichever cat's colour palette you've chosen. A pink dot appears when there are unread notifications.

Click it and you get a dropdown with the actual notifications listed — PR number, what happened — each one tappable to open the right page on GitHub. No more digging through your inbox to find the thing the ping was about.

You can also switch cats from the menu. Each one introduces themselves differently when you switch:

- Mochi: *"Good to see you! I'm Mochi~"*
- Boba: *"Heyyy! Boba's here! ✨"*
- Matcha: *"Matcha. Ready."*
- Miso: *"hi… I'm miso"*

---

## What I learned

A few things stayed with me from this project.

**Constraints are generative.** I didn't set out to build four cats with distinct personalities. I set out to build one notification that didn't look like every other notification. The personalities emerged from trying to make each colour feel intentional — and once Mochi had a vibe, Boba needed one too.

**Delight requires specificity.** "Make it cute" isn't a design direction. "The cursor should change to a pixel paw when you hover over a card" is. The more specific the wish, the more satisfying the result.

**You don't have to know how to build something to make it.** This is the one I'm still sitting with. I spent a long time believing that certain kinds of making were closed to me because I didn't have the technical skills. This project shifted something. The ideas — what it should feel like, what it should say, when it should be quiet — those were always mine to have. The gap between the idea and the thing was just a collaboration problem.

---

## What's next

The repo is on GitHub at [github.com/annchichi/catwatchpr](https://github.com/annchichi/catwatchpr). It's private for now, but I'm thinking about opening it up — or at least sharing it with teammates who might want their own pixel cat watching their PRs.

If you work on a GitHub-heavy project and you recognise this feeling — the missed comment, the invisible merge, the PR that sat unreviewed because nobody's notification stood out — maybe it'll be useful to you too.

Or maybe you'll want a different animal entirely. I hear there's room for a ghost dog.

---

*Ann Chia-Hui Tai is a designer at Automattic working on WooCommerce.*
