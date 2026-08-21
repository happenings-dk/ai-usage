# Changelog

All notable changes to AI Usage are documented here.

## [0.2.0] - 2026-08-21

### Added

- Use AI Usage as a full macOS desktop app while keeping the menu bar dashboard.
- Open a floating Quick Look panel from a customizable one- or two-step global shortcut sequence.
- View Claude, Codex, Gemini, and Grok together in equal-height dashboard cards.
- Download universal macOS ZIP and drag-to-install DMG artifacts from GitHub Releases.
- Install releases with one command, checksum and Developer ID verification, and recoverable replacement.
- Install over-the-air updates with signed publisher validation and an atomic swap helper.

### Changed

- Apply the Happenings Apple design system across desktop, menu bar, Quick Look, and settings surfaces.
- Build universal Apple silicon and Intel application bundles by default.
- Isolate pull-request CI from the tag-only Developer ID signing, notarization, and release job.

### Fixed

- Find CLI installations managed by NVM and common user-level package managers when launched from Finder.
- Make version checks actionable per CLI and avoid stale npm registry responses.
- Run independent CLI version probes concurrently so checks no longer appear stuck.
- Re-sign the completed app bundle after adding its icon and metadata.
