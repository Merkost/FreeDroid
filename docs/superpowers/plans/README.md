# FreeDroid Implementation Plans

This directory contains the eleven sub-project plans that together build FreeDroid v1.0. Each plan produces working, testable software on its own and is meant to be executed in dependency order.

Source spec: [`../specs/2026-05-12-freedroid-design.md`](../specs/2026-05-12-freedroid-design.md)

## Order of execution

| # | Plan | Produces | Depends on |
|---|---|---|---|
| 1 | [Foundation](2026-05-12-01-foundation.md) | Workspace, `FreeDroidDomain` package, empty SwiftUI app, CI baseline | — |
| 2 | [UI Design System](2026-05-12-02-ui-design-system.md) | `FreeDroidUI` with tokens, themes, all components, snapshot tests | 1 |
| 3 | [ADB Transport](2026-05-12-03-adb-transport.md) | `FreeDroidADB` package + integration tests | 1 |
| 4 | [MTP Transport](2026-05-12-04-mtp-transport.md) | `FreeDroidMTP` package, libmtp xcframework | 1 |
| 5 | [Data Layer](2026-05-12-05-data-layer.md) | `FreeDroidData` package: repositories, caches, USB watcher, registry, transfer queue | 1, 3, 4 |
| 6 | [Device Management Feature](2026-05-12-06-device-management-feature.md) | Sidebar with live device cards and Trust prompt | 2, 5 |
| 7 | [File Browser Feature](2026-05-12-07-file-browser-feature.md) | In-app file browser per device | 2, 5 |
| 8 | [Gallery Feature](2026-05-12-08-gallery-feature.md) | Masonry photo gallery with thumbnails | 2, 5 |
| 9 | [Transfer Feature](2026-05-12-09-transfer-feature.md) | Transfer queue UI, liquid progress, toasts | 2, 5, 6, 7, 8 |
| 10 | [FSKit Extension](2026-05-12-10-fskit-extension.md) | `FreeDroidIPC` package + `FreeDroidFS` extension — Finder mount | 5 |
| 11 | [Distribution](2026-05-12-11-distribution.md) | Signing, notarization, DMG, GitHub Releases, Sparkle, Homebrew Cask | 10 |

## Execution options

For each plan, you can choose between:

1. **Subagent-Driven (recommended)** — dispatch a fresh subagent per task with two-stage review between tasks. Use `superpowers:subagent-driven-development`.
2. **Inline Execution** — execute tasks in the current session with batched checkpoints. Use `superpowers:executing-plans`.

## Conventions

All plans follow the same conventions:

- **TDD-first** — every feature begins with a failing test.
- **Conventional Commits** — `feat:`, `fix:`, `chore:`, `docs:`, `test:`, `refactor:`.
- **No inline comments** — code is self-documenting; DocC `///` only on public package APIs.
- **Swift 6 strict concurrency** — every package enables it from day one.
- **No `print`** — `os.Logger` only.
- **No mocking frameworks** — protocol stubs and explicit test doubles.

## Milestone tags

When each plan completes, tag with the milestone:

```
v0.0.1-foundation
v0.1.0-ui-design-system
v0.2.0-adb-transport
v0.3.0-mtp-transport
v0.4.0-data-layer
v0.5.0-device-management
v0.6.0-file-browser
v0.7.0-gallery
v0.8.0-transfer
v0.9.0-fskit-mount
v1.0.0
```

The first publicly distributable release is `v1.0.0`, after Plan #11 ships the signed/notarized pipeline.
