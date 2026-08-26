# CodexIsland

[English](README.md) | [简体中文](README.zh-CN.md)

<p align="center">
  <img src="Assets/codexisland-logo.png" width="160" alt="CodexIsland logo">
</p>

<p align="center">
  <a href="https://hits.sh/github.com/ericjypark/codex-island/">
    <img alt="README visitors" src="https://hits.sh/github.com/ericjypark/codex-island.svg?label=visitors&color=007ec6&labelColor=555555">
  </a>
</p>

> Your AI usage limits, living in your notch.

CodexIsland is a native macOS overlay that turns the MacBook notch into a
Dynamic-Island-style live activity for Claude Code and Codex usage limits. It
sits quietly over the notch, peeks on hover with the 5-hour headline, and
expands on click to show both providers' 5-hour and weekly windows with reset
timing, chart controls, local-log cost estimates, and a year-at-a-glance usage
history.

https://github.com/user-attachments/assets/195beeff-0f70-4d6b-8f3d-9f31d9c0b989


The app is free, open source, unsigned, and local-first. It launches the
Claude Code and Codex CLIs you already use in a local pseudo-terminal, then
parses their interactive usage screens. It never reads their credentials or
calls provider usage/OAuth endpoints itself.

## What it does

- **Two providers, four windows.** Claude 5h + 7d and Codex 5h + 7d live in
  one panel.
- **Notch-native overlay.** The compact state is a black pill aligned to the
  physical notch, drawn with continuous (squircle) corners that match the
  hardware. On non-notched displays it falls back to a configurable menu-bar
  pill.
- **Hover to peek.** The silhouette widens just enough to show each visible
  provider's 5-hour percentage and reset headline, or keep those headlines
  visible at rest with **Always show usage**.
- **Four swipeable screens.** Click to expand, then swipe between **Usage**,
  **Cost**, **Models**, and **Overview**. Cost estimates today and month-to-date
  spend and token throughput from local Claude Code, Codex CLI, and OpenCode
  session data. Models keeps provider quota windows and local model throughput
  together; Overview renders the current year's activity as a contribution-style
  calendar.
- **Used or remaining quota.** Display provider windows as usage consumed or
  quota remaining.
- **Approaching-limit alerts.** Optional warning and critical thresholds tint
  the island and pulse the peek pill as a visible 5-hour window nears its
  limit.
- **Configurable token counting.** The TOKENS hero can sum every token type
  that crossed the wire (cache included, ccusage parity) or input + output
  only — the latter matches Anthropic's claude.ai stats panel.
- **Click-through outside the island.** The window ignores mouse events outside
  the visible silhouette so the menu bar and apps underneath still work.
- **Five chart styles.** Ring, Bar, Stepped, Numeric, and Sparkline. Pick the
  default in Settings or Command-click the expanded panel to cycle. Sparkline
  uses real readings recorded by CodexIsland during successful refreshes.
- **On-demand refresh.** Click `synced Xs ago` in the panel header to refetch
  immediately; the next scheduled poll re-arms from there.
- **Cobalt glow + Low Power Mode.** A soft glow around the island signals an
  in-flight refresh. Low Power Mode hides the steady-state glow so it only
  pulses during active work.
- **Settings without a Dock icon.** A quiet gear in the expanded panel opens a
  custom, resizable settings window with General, Display, and Providers tabs.
- **English and Simplified Chinese.** Follow the macOS language automatically
  or choose a language in Settings.
- **Display selection.** Auto-pick a notched display or pin the island to a
  specific connected display. Non-notched displays offer compact and
  notch-style widths.
- **Configurable safe polling.** Choose 5m, 15m, or 30m. Each poll is a
  status-only CLI session, never a direct provider API request.
- **Universal binary.** `build.sh` compiles arm64 and x86_64 slices and merges
  them with `lipo`, targeting macOS 13+.
- **No runtime auto-updates.** Sparkle's release tooling remains in the
  repository, but the shipped app does not start update checks or downloads.
- **Native app privacy.** No app telemetry, no crash reporting, no third-party
  app analytics, and no proxy service.

## Install

### Homebrew

```sh
brew install --cask ericjypark/tap/codexisland
```

The first invocation auto-taps `ericjypark/homebrew-tap`. The cask strips the
Gatekeeper quarantine attribute automatically (CodexIsland is unsigned by
Apple).

### Direct download

Download the current `CodexIsland-X.Y.Z.dmg` from the
[latest release](https://github.com/ericjypark/codex-island/releases/latest),
drag the app to `/Applications`, then run:

```sh
xattr -dr com.apple.quarantine /Applications/CodexIsland.app
```

<details>
<summary>Why is the dequarantine command necessary?</summary>

CodexIsland is unsigned because Apple charges $99/year for a Developer ID
certificate, and this is a free open-source project. The command removes the
macOS Gatekeeper quarantine attribute that triggers the "cannot be opened
because Apple cannot check it for malicious software" warning. The source code
is in this repository for audit.

If a sponsored Apple Developer ID becomes available via
[GitHub Sponsors](https://github.com/sponsors/ericjypark), signed builds can
follow.
</details>

<details>
<summary>I do not want to use Terminal. What do I do?</summary>

1. Drag `CodexIsland.app` to `/Applications`.
2. Try to open it. macOS will block it because the build is unsigned.
3. Open **System Settings -> Privacy & Security**.
4. Scroll to the bottom and find the blocked CodexIsland message.
5. Click **Open Anyway**, then re-launch the app.
</details>

## First run

CodexIsland does not ask for passwords, API keys, or OAuth tokens. Sign in to
the CLI first, then configure the required Claude proxy and any optional
Codex proxy:

- **Claude:** enter a valid HTTP(S) proxy in Settings. The app launches
  `claude` in two independent PTY sessions: `/usage` supplies Current session,
  all-model weekly, and model-specific weekly windows; `/status` supplies the
  CLI-reported login method. An empty proxy disables both requests.
- **Codex:** add every account explicitly in Settings; each profile needs a
  display name and `CODEX_HOME`, plus an optional HTTP(S) proxy. When blank,
  CodexIsland clears inherited proxy variables so that profile runs directly.
  CodexIsland launches
  `codex` under that `CODEX_HOME`, runs `/status` up to three times in the same
  PTY session (three seconds apart), and keeps profiles isolated. Subscription
  percentages are never added or averaged: with multiple profiles, their
  named windows are shown separately in the expanded quota list. If `/status`
  identifies API-key mode, it shows no fabricated subscription quota; local
  token and cost estimates remain available. Empty or invalid profiles do not
  run.

The first fetch starts at app launch so the panel usually has values ready by
the first peek. Later automatic provider refreshes follow the selected interval;
opening Settings alone does not start another CLI session.

## Using the app

- Hover the notch to peek at the current 5-hour usage.
- Click the island to expand the full panel.
- Swipe horizontally on the panel (or use the indicator dots) to move between
  **Usage**, **Cost**, **Models**, and **Overview**.
- Move away to collapse it.
- Command-click the expanded panel to cycle chart styles on the active screen
  (Usage cycles Ring/Bar/Stepped/Numeric/Sparkline; Cost cycles
  USD/VALUE/TOKENS/TREND; Overview has one calendar view).
- Click `synced Xs ago` in the panel header to refetch immediately.
- Click the gear in the lower-left corner of the expanded panel to open
  Settings, or press ⌘,.
- Press ⌘Q while the pointer is over the island to quit. You can also
  quit from Settings.

Provider visibility is display-only. Hiding a provider removes that provider's
logo and column from the island, but the app keeps the latest usage values in
memory so showing it again does not require a reset.

## Settings

Settings is a custom `NSWindow`, not the system Settings scene. The app still
runs as an accessory app with no Dock icon and no menu bar.

- **General:** Launch at Login, 5m/15m/30m refresh interval, app language,
  Always show usage, Low Power Mode, and configurable limit alerts.
- **Display:** used/remaining percentages, Usage and Cost visualization styles,
  target display, and island width on non-notched screens.
- **Providers:** Claude/Codex visibility and status, token-counting mode, and a
  manual refresh for local cost data.

Preferences are stored in `UserDefaults` under `MacIsland.*` keys, and Launch
at Login uses `SMAppService.mainApp`. Refresh, display, and provider changes
apply live; changing the app language offers to restart CodexIsland.

## Build from source

Requires macOS 13+ and a Swift toolchain from Xcode / Command Line Tools.

```sh
git clone https://github.com/ericjypark/codex-island
cd codex-island
./build.sh
open build/CodexIsland.app
```

There is no Xcode project and no SwiftPM package. `build.sh` runs `swiftc` over
`Sources/**/*.swift`, compiles arm64 and x86_64 slices, merges them with
`lipo`, copies bundled resources, and writes `Info.plist`.

Smoke test the native app:

```sh
./scripts/run-tests.sh
./scripts/verify.sh
```

`run-tests.sh` compiles and runs the credential-resolution and notch-height
test harnesses. `verify.sh` builds the app, launches the binary for one second,
then kills it if it is still alive.

## Release

Package a DMG:

```sh
npm install --global create-dmg
./release.sh
```

`release.sh` runs the native build, copies the `.app` to `dist/`, applies ad-hoc
codesigning, creates `dist/CodexIsland-X.Y.Z.dmg`, signs it with Sparkle's
EdDSA key when available, generates `dist/appcast.xml`, and prints the file size
and SHA-256.

Pushing a `v*` tag triggers `.github/workflows/release.yml` on `macos-15`,
builds the signed DMG and appcast, generates release notes from Conventional
Commits, publishes both artifacts in a GitHub Release, and mirrors the cask to
`ericjypark/homebrew-tap` when `HOMEBREW_TAP_TOKEN` is configured.

`Casks/codexisland.rb` is the Homebrew Cask template. Do not manually bump its
version or SHA for normal releases; CI copies it to the tap and rewrites those
fields from the tag and freshly built DMG.

## Repository layout

```text
.
├── Sources/
│   ├── App.swift
│   ├── Cost/                # Local-log cost + token aggregation
│   ├── Localization/        # Runtime localization helper
│   ├── Model/
│   ├── Theme/
│   ├── Usage/
│   ├── Views/
│   └── Window/
├── Resources/              # Icons, provider marks, localized strings
├── Assets/                 # README logo asset
├── Tests/                  # Bare-swiftc regression harnesses
├── docs/                   # Sparkle runbook, design specs
├── Casks/                  # Homebrew Cask template
├── scripts/                # Tests, native smoke test, Sparkle setup
├── build.sh                # Universal .app build
├── release.sh              # DMG packaging
└── VERSION
```

## Privacy

Native app behavior:

- No app telemetry.
- No app analytics.
- No crash reporting.
- No proxy server.
- No credentials are stored by CodexIsland.
- Model prices are fetched once a day from a public, GitHub-hosted catalog
  ([codex-island-model-catalog](https://github.com/ericjypark/codex-island-model-catalog)).
  The request carries no identifier, no token, and no usage data — it is a
  plain GET for a static JSON file, and the app works from a local cache when
  it fails.
- CodexIsland never reads `auth.json`, Keychain secrets, environment OAuth
  tokens, or API keys. Authentication and provider network traffic stay inside
  the child CLI process.
- The app passes only the configured `HTTP_PROXY` / `HTTPS_PROXY` (and Claude's
  local `NO_PROXY` exclusions) to those CLI sessions.
- The Cost screen reads local Claude Code session logs from
  `~/.claude/projects/**/*.jsonl` (and `~/.config/claude/...`, plus any path
  in `CLAUDE_CONFIG_DIR`), Codex session logs only from manually configured
  `CODEX_HOME/sessions/` directories, and OpenCode data from
  `~/.local/share/opencode/`. Aggregation happens entirely on-device — no log
  content is uploaded or shared anywhere.

The visitor badge at the top of this README is an external `hits.sh` image that
counts badge requests. It is not bundled with or contacted by the native app.

The app's only direct network request is the unauthenticated model-price
catalog in [`Sources/Cost/PricingCatalog.swift`](Sources/Cost/PricingCatalog.swift).
[`Sources/Usage/UsageFetcher.swift`](Sources/Usage/UsageFetcher.swift) only
launches the locally installed CLIs; local log readers live in
[`Sources/Cost/`](Sources/Cost/).

## Troubleshooting

**Claude shows `proxy required`, or Codex shows `codex proxy invalid`.**
Claude requires a valid `http://` or `https://` proxy. Codex may leave its
proxy blank, but if supplied it must be a valid HTTP(S) URL.

**Codex shows `add codex profile` or `codex home required`.**
Add a profile manually, then enter its absolute `CODEX_HOME` and proxy. The
app deliberately has no implicit `~/.codex` fallback.

**Which Codex profile does the compact island show?**
Quota percentages from different accounts cannot be combined. The island uses
the first usable enabled profile; Settings and the expanded quota list show
each named profile separately.

**The app shows stale values after an error.**
That is intentional. `UsageStore` keeps the previous good values when a refresh
returns only transient errors, so a temporary CLI failure does not turn the
panel into 0%. Configuration changes and API-key mode clear any old
subscription reading instead.

**Why can I not choose 30-second polling?**
The app starts full interactive CLI status sessions, so it exposes 5m, 15m,
and 30m only.

**Does it work without a notch?**
Yes. It falls back to a compact menu-bar pill; Settings can switch it to the
wider notch-style spacing.

**Does it support multiple monitors?**
Yes, with one island at a time. Auto mode prefers a notched display, then the
main display. You can also pin the island to a connected display in Settings;
if that display is unplugged, CodexIsland falls back to Auto.

**Will CLI status parsing break?**
Possibly. The usage panels are interactive TUI output. If a CLI release changes
its layout, report the redacted transcript and CLI version.

**Why is there no Dock icon?**
CodexIsland is an accessory app. Use the gear in the expanded island to open
Settings, and use Settings -> Quit to exit.

## Known limits

- Unsigned builds require dequarantine / Open Anyway.
- Claude and Codex status panels are interactive and can change between CLI
  versions.
- Sparkline history contains only readings CodexIsland records while it is
  running; providers do not expose historical usage series.
- Multi-monitor setups use one island, pinned to or auto-selected for one
  display at a time.
- Accessibility is partial: VoiceOver labels exist, but a high-contrast variant
  is not implemented yet.

## Acknowledgements

- [codexbar](https://github.com/steipete/codexbar) by Peter Steinberger -
  auth-source archaeology for Claude credential resolution.
- [LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern)
  by Sindre Sorhus - reference shape for `SMAppService.mainApp`.
- [Emil Kowalski](https://animations.dev) - animation timing and interaction
  discipline.

## Changelog

See [GitHub Releases](https://github.com/ericjypark/codex-island/releases) for
current release notes and [CHANGELOG.md](CHANGELOG.md) for curated milestone
notes.

## License

MIT - see [LICENSE](LICENSE).

<a href="https://www.star-history.com/?type=date&repos=ericjypark%2Fcodex-island">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=ericjypark/codex-island&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=ericjypark/codex-island&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=ericjypark/codex-island&type=date&legend=top-left" />
 </picture>
</a>
