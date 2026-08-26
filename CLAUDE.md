# CLAUDE.md

Project-specific guardrails. **Read every section before touching this repo.**

## Release process — MANDATORY

Sparkle release tooling remains available, but runtime update checks are
disabled in the shipped app. Keep release artifacts valid without re-enabling
runtime update behavior unless explicitly requested.

### The loop (3 commands)

```sh
echo "X.Y.Z" > VERSION                                # 1. Bump
git commit -am "chore(release): bump VERSION to X.Y.Z" \
  && git tag vX.Y.Z                                   # 2. Commit + tag
git push origin main vX.Y.Z                           # 3. Push (fires CI)
```

The marketing landing site at `ericjypark/codex-island-landing` has its own
`VERSION` file (the hero chip + footer read it at build time). Bump it in
that repo too, in the same release sweep, or the public site keeps showing
the prior version even after `brew install` ships the new one.

That's it. CI does **everything else** in ~1.5 min:

- Builds the universal DMG
- Signs it with the EdDSA key from the `SPARKLE_ED_PRIVATE_KEY` secret
- Generates `appcast.xml` listing the new version
- Uploads DMG + appcast as release assets
- Mirrors the cask to `ericjypark/homebrew-tap` with the new version + SHA-256

Watch with `gh run watch --exit-status` if you want confirmation, or just trust it.

### Hard rules — break these and you brick auto-update

1. **`VERSION` must be a single-monotonic version like `0.0.X`, NOT `1` or `100` or anything weird.** `build.sh` uses `$VERSION` as both `CFBundleVersion` and `CFBundleShortVersionString`. Sparkle compares `CFBundleVersion` of the running app against `sparkle:version` in the appcast using Apple's component-wise comparator — so `"1"` parses as `[1]` and is **larger than** `"0.0.99"`. Stay in semver. Always increase.

2. **The Sparkle public key in `build.sh` (`SU_PUBLIC_KEY="bz1g..."`) must NEVER be changed casually.** Every existing install verifies updates against this exact key. Change it and every prior install rejects every future update silently. The matching private key lives in (a) the maintainer's macOS Keychain under service `https://sparkle-project.org` and (b) the `SPARKLE_ED_PRIVATE_KEY` GitHub Actions secret. To rotate, see the migration note in `docs/SPARKLE.md` (TL;DR: don't).

3. **Don't manually edit `Casks/codexisland.rb` for a version bump.** CI rewrites it on the homebrew-tap side at release time. Manual version/SHA edits are overwritten or drift. (Editing unrelated cask metadata — postflight, zap, livecheck — via a normal commit is fine; CI preserves those.)

4. **Never edit appcast XML files by hand.** The appcast is a release asset built by `release.sh` from the signed DMG. Hand-edits invalidate the EdDSA signature.

5. **Never commit `Vendor/`.** It's gitignored. The `bin/sign_update`, `bin/generate_keys`, etc. binaries live there for local use; CI re-vendors via `scripts/setup-sparkle.sh`.

### CI secrets (one-time, already configured)

These two GitHub Actions secrets exist on the `codex-island` repo:

- **`SPARKLE_ED_PRIVATE_KEY`** — the EdDSA private key. Without it CI fails at the signing step.
- **`HOMEBREW_TAP_TOKEN`** — fine-grained PAT with `contents: write` on `ericjypark/homebrew-tap` only. Without it the cask-sync step warns and skips, but the GitHub Release still ships.

If either is rotated, regenerate via the original instructions in `docs/SPARKLE.md`.

### Runtime update behavior

Do not add a runtime update prompt or scheduler. `AppDelegate` deliberately
does not create an updater; Sparkle is retained only for release packaging.

### Things that have already broken and how they were fixed

History — read before re-stepping on these rakes:

| Problem | Symptom | Root cause | Fix |
|---|---|---|---|
| `CFBundleVersion = "1"` hardcoded | Sparkle never sees any update as newer | `"1"` > `"0.0.X"` in component-wise comparison | `build.sh` now sets it to `$VERSION` |
| `SUPublicEDKey` empty in CI builds | Sparkle silently rejects every signed update | Public key was in gitignored `Vendor/` only | Public key hardcoded in `build.sh` |
| `xattr -d` non-recursive in cask postflight | "Updater failed to start" on first Check Now | Quarantine attr remained on Sparkle's nested `Updater.app` | `xattr -dr` (recursive) |
| `--no-quarantine` in install docs | `brew install` fails with "switch is disabled" | Homebrew removed the flag in late 2025 | Cask postflight strips the attr; flag removed from docs |
| `…` after `$VAR` in shell scripts | CI fails with `unbound variable` | Non-UTF-8 locale on runners makes bash include trailing bytes in identifier | Use `${VAR}…` braces, or stick to ASCII in echo strings |
| Old yonsei email in commits | Vercel rejected landing deploys | Local git config used unverified email | Set `git config user.email` to a GitHub-verified address before committing |
| Landing tried to read `../VERSION` | Vercel build ENOENT'd at `/vercel/VERSION` | Landing is its own repo; Vercel only checks out `codex-island-landing`, so `..` escapes the build root | Landing has its own `VERSION` file, read with `path.join(process.cwd(), "VERSION")` — sync it on every release |

## Architecture pointers

- `Sources/Window/IslandWindowController.swift` — borderless overlay window. Listens to `NSApplication.didChangeScreenParametersNotification` to reposition on display changes; prefers the screen with `safeAreaInsets.top > 0` (the notched display).
- `Sources/App.swift` — launches the overlay and local stores; runtime Sparkle checks stay disabled.
- `Sources/Usage/CLIStatusProbe.swift` — bounded PTY sessions. Claude and Codex each receive only `/status`; the probe never sends a prompt or reads credentials.
- `Sources/Usage/UsageFetcher.swift` — validates launch context and parses status text. It never reads `auth.json`, Keychain entries, OAuth tokens, or provider HTTP endpoints.
- `Sources/Usage/AppUsage.swift` — retains parsed plan/login state and independent quota windows. API, third-party, and signed-out states clear old subscription readings immediately.

## Build details

- `build.sh` — universal binary (arm64 + x86_64 via `lipo`), macOS 13+, ad-hoc codesign, embeds Sparkle.framework with `@executable_path/../Frameworks` rpath.
- Unsigned by Apple — no $99 Developer ID. The ad-hoc sign is just to dodge "is damaged and can't be opened" Gatekeeper rejection on download. Sparkle's EdDSA signing handles update integrity independently.
- `scripts/setup-sparkle.sh` downloads Sparkle 2.9.1 into `Vendor/Sparkle/` (idempotent). Runs automatically as part of `build.sh`.

## What NOT to change without explicit user request

- The `5m / 15m / 30m` polling presets (`Sources/Model/RefreshIntervalStore.swift`) — Anthropic rate-limits aggressively. Anything below 5m burns the daily quota.
- The bundle ID `dev.codexisland.CodexIsland` — changing it orphans every existing user's preferences and Launch-at-Login registration.
- The `SU_PUBLIC_KEY` constant in `build.sh`. See hard rule #2.

## `docs/` vs `notes/` — what gets committed

This repo is public open source. `docs/` is for things a contributor or
curious user would read. `notes/` is gitignored and is for maintainer-only
operational material. **When in doubt, default to `notes/`** — it's
trivial to promote a file later, painful to scrub git history.

**`docs/` (committed, public):**
- Build / release / signing process (e.g. `SPARKLE.md`).
- Architecture deep-dives, protocol notes, contributor onboarding.
- Anything that helps someone reading the source understand it or ship a PR.

**`notes/` (gitignored, maintainer-only) — examples of what belongs here:**
- Launch / marketing playbooks (where to post, when to post, UTM schemas, channel-by-channel rules).
- Analytics & traffic ops (PostHog dashboards, GitHub traffic API workflows, install-funnel telemetry, dashboard URLs).
- Anything mentioning private infra: tokens, secret names, dashboard IDs, internal cron schedules — even if the secret value isn't there, the *shape* of the deployment is.
- Personal launch-strategy retrospectives, growth experiments, A/B copy drafts.

**Heuristic:** if removing the file from the public repo would *embarrass*
nothing and *help* nobody outside the maintainer, it belongs in `notes/`.
If it would actively help a contributor or a downstream packager, it
belongs in `docs/`.

When creating a new doc in this category, do **not** add it to `docs/` and
later move it — moving leaves a deletion in history that still shows the
title and intent. Create it in `notes/` from the start.

## Style

- Conventional Commits: `feat:`, `fix:`, `chore:`, `refactor:`, `test:`, `docs:`. No `Co-Authored-By` lines.
- Strict TypeScript / Swift — no `any`, no force-unwraps without justification.
- Default to no comments. Only add when the WHY is non-obvious (a constraint, a workaround for a specific bug, behavior that would surprise a reader).
- Match existing style in the file you're editing, even if you'd do it differently.
