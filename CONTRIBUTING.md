# Contributing to FreeDroid

## Build setup

1. Install Xcode 16.3 or newer.
2. Install SwiftLint and XcodeGen: `brew install swiftlint xcodegen`.
3. Generate the Xcode project: `Scripts/generate-project.sh`.
4. `open FreeDroid.xcworkspace` and build.

## Regenerating the Xcode project

Always use `Scripts/generate-project.sh`, not `xcodegen` directly. The wrapper runs XcodeGen and then patches the resulting `project.pbxproj` to add `package =` references on every local Swift Package product — Xcode 26's UI requires this field, but XcodeGen 2.45 does not emit it.

## Coding rules

- **No inline `//` comments.** Names carry meaning. DocC `///` only on public package APIs. SwiftLint enforces this.
- **No `print`.** Use `os.Logger`.
- **Tests first** — TDD: red, green, refactor.
- **One commit per logical change.** Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `test:`, `refactor:`).
- **Swift 6 strict concurrency** — no warnings allowed.

## Pull requests

- One feature per PR.
- All tests must pass in CI.
- SwiftLint must pass with zero warnings.
- New public API requires DocC comments.

## Architecture

Read `docs/superpowers/specs/2026-05-12-freedroid-design.md` first.
