# Contributing to CodexIsland

Thanks for being here. CodexIsland is small enough that any contribution moves the project meaningfully — bug reports especially. Here's how to keep things smooth.

## Reporting bugs

Open an issue. Useful things to include:

- macOS version (`sw_vers`) — particularly if the notch detection or window placement is off.
- Output of `defaults read dev.codexisland.CodexIsland` if it's a settings-related bug.
- A short description of what you expected vs. what happened.
- Whether Claude / Codex actually has data populated in the panel — include the
  visible CLI error and the selected proxy/profile configuration, never any
  credentials.

If Claude or Codex changes its interactive status screen, attach a redacted
PTY transcript from `claude /status` or `codex /status`. Do not capture or
share OAuth tokens, API keys, `auth.json`, Keychain data, or provider HTTP
responses: the app deliberately never reads or calls those sources.

## Building locally

```sh
./build.sh
open build/CodexIsland.app
```

`./scripts/verify.sh` builds and smoke-launches the binary for one second — useful in pre-commit hooks since the app runs forever and a normal `./build.sh && ./build/.../CodexIsland` would block.

No Xcode project, no SwiftPM. Just `swiftc Sources/**/*.swift`.

## Code style

- **Lowercase Conventional Commits.** `feat(scope): summary`, `fix(scope): summary`, `chore: summary`. Body explains the *why*, not the *what*. The diff is the what. See git log for examples.
- **Atomic commits.** One logical change per commit; each commit must build and run via `./scripts/verify.sh`.
- **No AI vocabulary** — words like *comprehensive*, *delve*, *crucial*, *robust*, *seamless* are banned in commit messages, code comments, and docs. Direct words are better.
- **No `Co-Authored-By` lines** — including Claude / Copilot / etc. tags. Keep authorship clean.
- **Comments only when the WHY is non-obvious.** A hidden constraint, a workaround for a specific bug, behavior that would surprise a reader. If removing the comment wouldn't confuse the next person, don't write it.
- **Match existing style.** This codebase favors small files, named extensions on `Animation` / `Color`, and explicit `@MainActor` where AppKit insists.

## Things that need work

- Multi-monitor support. Right now the app chooses one target screen: the first notched display, otherwise `NSScreen.main`. Users with multiple notched displays should ideally see one panel per screen (or at least an option).
- Real history for the SparkChart. The synthesized noise is honestly decorative. If either Anthropic or OpenAI exposes a usage time-series, we should switch.
- Accessibility. VoiceOver labels exist, but a high-contrast variant and a full keyboard/focus pass still need work.
- Sponsor an Apple Developer ID via [GitHub Sponsors](https://github.com/sponsors/ericjypark) and we'll ship a signed build.

## Code of conduct

See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). Short version: be kind.
