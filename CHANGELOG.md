# Changelog

All notable changes to DriveCam are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [v0.1.1] – 2026-05-05

### ✨ New Features

- **Audio toggle** – Users can now mute or unmute the microphone at any time,
  whether a recording session is active or not. ([#28])
- **End-drawer navigation** – A slide-out end drawer replaces the previous
  navigation approach and provides quick access to all screens.  The bottom
  app bar was also simplified at the same time.
- **Privacy Policy page** – A Privacy Policy screen is now available inside
  the end drawer, fulfilling the app's data-transparency commitment. ([#41])

### 🐛 Bug Fixes

- **Prevent saving a clip while not recording** – Tapping the "save clip"
  button when the camera is idle no longer silently fails; the action is now
  blocked and an appropriate guard is in place. ([#40])
- **Dark-mode dropdown backgrounds** – Dropdown menus were invisible against
  the dark background. The theme now correctly applies surface colours so menu
  items are always readable. ([#36])
- **SafeArea for end-drawer button** – The end-drawer icon was partially hidden
  by system-UI overlays (status bar / notch) on certain devices. The button is
  now wrapped in a `SafeArea` widget. ([#42])
- **`deleteOldestClipDB` crash guard** – The database helper now includes a
  `WHERE` clause guard in `deleteOldestClipDB` so that a call on an empty table
  does not produce an unexpected error. ([#50])

### 🧪 Tests & CI

- **GitHub Actions: run tests on PRs** – Every pull request now automatically
  runs `flutter analyze` and `flutter test`, blocking merges if either fails. ([#27])
- **Unit tests: `SettingsProvider`** – Full coverage for all provider
  functions, preference loading, and onboarding state persistence. ([#35])
- **Widget tests: clipping screen** – Tests covering the clip-saving
  screen interactions and guard conditions. ([#49])
- **Unit tests: database helpers & queries** – Tests for `DatabaseHelper`
  initialisation, CRUD operations, and `deleteOldestClipDB` behaviour
  using an in-memory SQLite database. ([#50])

### 🔗 Pull Requests in this release

| # | Title | Author |
|---|-------|--------|
| [#27] | Add GitHub Action to run tests for PRs | @xander1111 |
| [#28] | Add audio toggle | @rowandey |
| [#35] | Added unit tests for settings_provider | @rowandey |
| [#36] | Fixed dark-mode dropdown visibility | @KeenanBromley |
| [#40] | Prevent saving a clip when not recording | @xander1111 |
| [#41] | Created Privacy Policy page | @KeenanBromley |
| [#42] | Added SafeArea to end-drawer button | @shackfu1 |
| [#49] | Added tests for the clipping screen | @KeenanBromley |
| [#50] | Added tests for database functions | @xander1111 |

[#27]: https://github.com/rowandey/SE467-DriveCam/pull/27
[#28]: https://github.com/rowandey/SE467-DriveCam/pull/28
[#35]: https://github.com/rowandey/SE467-DriveCam/pull/35
[#36]: https://github.com/rowandey/SE467-DriveCam/pull/36
[#40]: https://github.com/rowandey/SE467-DriveCam/pull/40
[#41]: https://github.com/rowandey/SE467-DriveCam/pull/41
[#42]: https://github.com/rowandey/SE467-DriveCam/pull/42
[#49]: https://github.com/rowandey/SE467-DriveCam/pull/49
[#50]: https://github.com/rowandey/SE467-DriveCam/pull/50

---

## [v0.1.0] – 2026-04-10

Initial tracked release.

### Added

- Project README with scope, purpose, MLPs, and Flutter / Android setup guide. ([#20])
- CI/CD pipeline via GitHub Actions: lint, test, build, and upload APK artifact on pushes to `main`. ([#25])
- Automated GitHub Release creation on `v*` tag push or manual workflow dispatch. ([#26])

### New Contributors

- @Copilot – first contribution in [#20]
- @xander1111 – first contributions in [#25] and [#26]

[#20]: https://github.com/rowandey/SE467-DriveCam/pull/20
[#25]: https://github.com/rowandey/SE467-DriveCam/pull/25
[#26]: https://github.com/rowandey/SE467-DriveCam/pull/26

[v0.1.1]: https://github.com/rowandey/SE467-DriveCam/compare/v0.1.0...v0.1.1
[v0.1.0]: https://github.com/rowandey/SE467-DriveCam/releases/tag/v0.1.0
