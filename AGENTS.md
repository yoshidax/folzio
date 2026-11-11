# AGENTS.md

Folzio is a native macOS (15+, Apple silicon) image and video browser built with Swift 6, AppKit, and SwiftPM.
It has no external dependencies and no network access. See `docs/development.md` for setup and project layout.

## Commands

- Build: `swift build`
- Test gate: `swift test --no-parallel --skip FolzioPerformanceTests`
- One suite: `swift test --filter <SuiteName>`
- Performance tests run alone: `swift test --filter FolzioPerformanceTests`
- Guardrails: `scripts/check-no-network.sh`, `scripts/check-no-archive-writes.sh`, `scripts/check-readme-sync.sh`
- Launch the app: `scripts/make-app.sh && open .build/Folzio.app`

A change is done when the test gate and every guardrail relevant to the touched files pass.

## Architecture

- `FolzioCore` holds state and decision logic and stays free of AppKit. `FolzioApp` (AppKit) draws and handles input.
  Put new logic in Core so it is testable without UI.
- Decoding, directory enumeration, and file operations run off the main thread.
- Code under `Sources/FolzioCore/Archive` reads zip files only.
- The only URL literal in `Sources` is the repository link in `AboutInfo.swift`; the app never opens connections.

## Localization

- Every user-visible string is a `TextKey` in `Sources/FolzioLocalization/TextKey.swift`.
- Add each key to both `en.lproj` and `ja.lproj` (`Localizable.strings`, plus `.stringsdict` for counts).

## Tests

- Use Swift Testing (`import Testing`, `@Test`, `#expect`).
- Core logic and error cases go in `FolzioCoreTests`; AppKit behavior goes in `FolzioAppTests`.
- Generate media in tests with `FixtureKit`.

## Docs and commits

- English and Japanese docs are pairs (`README.md` / `README.ja.md`, `docs/*.md` / `docs/*.ja.md`).
  Edit both in one change and keep their headings, lists, tables, and code blocks aligned.
- Write code comments in English.
- Commit messages follow Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`), with the issue key if any: `(TAK-5)`.
