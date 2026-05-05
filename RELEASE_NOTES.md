# DriveCam — Release Notes

**Version:** v0.1.1  
**Release Date:** 2026-05-05  
**Platform:** Android (primary) · iOS (secondary, via Flutter)  
**Minimum Android SDK:** As required by `camera` and `ffmpeg_kit_flutter_new` dependencies

---

## Overview

DriveCam is a privacy-first mobile dashcam application that turns your Android smartphone into a
fully featured dash camera. All video footage and metadata are stored exclusively on-device; no
data is ever transmitted to external servers.

This release (v0.1.1) builds on the initial v0.1.0 foundation by adding user-facing features,
fixing several bugs discovered during internal testing, and expanding automated test coverage.

---

## ✅ Working Functionality

### Core Recording
- **Continuous video recording** — The camera view records video in the background. A single
  rolling session is maintained in the app's local storage.
- **Start / stop recording** — The record button on the main camera view starts and stops a
  session. State is communicated via a clearly visible recording indicator.
- **Video quality and framerate settings** — Supported options are 480p / 720p / 1080p / 4K and
  15 / 30 / 60 fps. Settings take effect immediately; the camera reinitializes without losing an
  active recording session.
- **Audio toggle** — Microphone audio can be enabled or disabled at any time, including while
  recording. Toggling audio mid-session stops the current segment, saves it, and restarts recording
  seamlessly so footage is not lost.
- **Orientation handling** — The camera preview adapts when the device is rotated. Rotation while
  recording is blocked to prevent data loss.

### Clip Saving
- **Manual clip trigger (tap-to-clip)** — Tapping the camera preview while recording saves a clip.
  Clips capture a configurable amount of footage before (pre-duration) and after (post-duration)
  the tap.
- **Post-duration countdown** — When a post-duration is configured, a visual countdown indicator
  confirms that the clip window is still being captured before saving.
- **Clip extraction from previous recording** — If a clip is triggered while not actively
  recording, the app falls back to the most recent saved recording and extracts the clip from it.
- **Guard: no save when camera is idle** — Attempting to save a clip while the camera is not
  recording is properly handled; a pending clip is queued for the next available recording.
- **FFmpeg re-encoding** — Saved clips are re-encoded to H.264/AAC for maximum compatibility with
  native media players.
- **Clip thumbnails** — A thumbnail image is generated from the first frame of each clip using
  FFmpeg.

### Storage & Database
- **SQLite-backed clip metadata** — All clip metadata (timestamps, file paths, durations, sizes,
  trigger type, flag status) is persisted in a local SQLite database.
- **Rolling recording storage** — Only one full recording is kept on-disk at a time. When a new
  session ends, the previous recording file is automatically deleted.
- **`deleteOldestClipDB` guard** — When the clip storage limit is reached, the oldest clip is
  deleted first. A guard prevents errors when the clip table is empty.

### Settings
- **Persistent user preferences** — All settings (framerate, quality, footage limit, storage limit,
  clip durations, audio enabled, dark mode) are persisted via `SharedPreferences` and restored on
  app launch.
- **Recording settings:** framerate, quality, rolling footage time limit, total storage limit.
- **Clip settings:** pre-clip duration, post-clip duration, clip storage limit.

### User Interface
- **Onboarding flow** — First-time users are guided through an initial settings configuration
  before reaching the main camera view. Onboarding completion is persisted across app restarts.
- **End-drawer navigation** — A slide-out drawer (accessible via the ☰ menu button overlaid on
  the camera view, or from the top app bar on other screens) provides navigation to all app
  screens.
- **Clip Manager screen** — Displays all saved clips and the most recent recording. Tapping a
  clip or recording opens a full-screen player.
- **Settings screen** — All user-configurable options are presented as clearly labelled dropdowns.
- **Privacy Policy screen** — Accessible from the navigation drawer; explains what data is
  collected, what is not, and what is never shared.
- **Dark mode / Light mode** — Fully themed dark and light modes. Dropdown menus and all UI
  elements respect the active theme.

### CI / CD
- **Automated test suite on PRs** — GitHub Actions runs `flutter analyze` and `flutter test` on
  every pull request, blocking merges if either fails.
- **Release build pipeline** — Pushing a `v*` tag, or manually triggering the workflow, runs the
  full lint-test-build pipeline and creates a GitHub Release with the APK attached.

---

## 🐛 Known Bugs

One bug has been confirmed as of this release.

| Summary | Details |
|---------|---------|
| **Clip can be triggered before recording has fully started** | When the user presses Record, the app's internal `isRecording` flag is set to `true` and the UI updates immediately, but the camera hardware has not yet begun capturing video. If the user taps the preview in this brief window, the clip-save logic sees `isRecording = true` and queues a clip request — but no footage exists yet, so no clip is produced. **Workaround:** Wait for the recording indicator to appear steadily before tapping to save a clip. |

### Planned Features (Not Yet Implemented)

The following are planned features that have not yet been implemented. They are listed here for
transparency so users understand what to expect in a future release.

| # | Feature |
|---|---------|
| [#14] | Automatic event/crash detection using phone sensors |
| [#13] | Voice-command clip triggering |
| [#22] | Video compression for reduced storage usage |
| [#33] | Switch recording format to HLS (`.m3u8`) for improved segment management |
| [#43] | Opt-in user analytics (KPI metrics) |

---

## 📋 Issues Fixed Since v0.1.0

| # | Fix |
|---|-----|
| [#36] | Dark-mode dropdown menus were invisible — theme colours corrected |
| [#40] | Clip button while not recording produced a silent failure — replaced with a pending-clip queue |
| [#42] | Navigation drawer icon was partially hidden by the system status bar — wrapped in `SafeArea` |
| [#50] | `deleteOldestClipDB` called on an empty table caused an unexpected error — WHERE guard added |

---

## 🧪 Test Coverage (as of v0.1.1)

| Area | Type | Status |
|------|------|--------|
| `SettingsProvider` — all setters, preference loading, onboarding | Unit | ✅ |
| `DatabaseHelper` — init, CRUD, `deleteOldestClipDB` | Unit | ✅ |
| `queries.dart` — all query functions | Unit | ✅ |
| Clipping screen — save interactions, guard conditions | Widget | ✅ |
| Recording screen | Widget/Unit | ⚠️ Partial (see [#44]) |

---

## 📦 Installation

1. Download the APK from the [v0.1.1 GitHub Release page].
2. On your Android device, enable *Install from Unknown Sources* in Settings → Security.
3. Open the downloaded APK file and follow the on-screen prompts to install.
4. Grant camera and microphone permissions when prompted on first launch.

> **Note:** A physical Android device is required. Android emulators have limited or no camera
> hardware access and are not supported for recording.

---

## 👥 Contributors

| Contributor | Role |
|-------------|------|
| @rowandey | Project lead, audio toggle, settings tests |
| @KeenanBromley | Privacy Policy page, dark-mode fix, clipping tests |
| @xander1111 | CI/CD pipelines, clip-save guard, database tests |
| @shackfu1 | End-drawer navigation, SafeArea fix |

---

[#13]: https://github.com/rowandey/SE467-DriveCam/issues/13
[#14]: https://github.com/rowandey/SE467-DriveCam/issues/14
[#22]: https://github.com/rowandey/SE467-DriveCam/issues/22
[#33]: https://github.com/rowandey/SE467-DriveCam/issues/33
[#36]: https://github.com/rowandey/SE467-DriveCam/pull/36
[#40]: https://github.com/rowandey/SE467-DriveCam/pull/40
[#42]: https://github.com/rowandey/SE467-DriveCam/pull/42
[#43]: https://github.com/rowandey/SE467-DriveCam/issues/43
[#44]: https://github.com/rowandey/SE467-DriveCam/issues/44
[#50]: https://github.com/rowandey/SE467-DriveCam/pull/50
[v0.1.1 GitHub Release page]: https://github.com/rowandey/SE467-DriveCam/releases/tag/v0.1.1
