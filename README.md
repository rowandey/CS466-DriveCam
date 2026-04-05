# DriveCam 📷

**SE467: Software Startup II — Oregon State University Cascades**  
*Team: Rowan Dey, Keenan Bromley, Xander Bailey, Sasha Hackenbruck*  
*Professor: Jesse Rosenzweig*

---

## Overview

DriveCam is a **mobile dashcam application** built with Flutter that turns your smartphone into a
fully featured dash camera. The app continuously records video while driving and lets you quickly
save, review, and manage clips — all while keeping your footage private and stored locally on your
device.

The project targets **Android** as its primary platform, with Flutter enabling a single codebase
that can also support iOS.

---

## Purpose

Existing dash cameras require purchasing and mounting dedicated hardware (expensive, time-consuming
setup), and existing dashcam apps on the market have opaque data-sharing practices — often sharing
footage and metadata with third parties without clear disclosure to the user.

DriveCam solves both problems:

- **No hardware purchase required** — your existing smartphone does the job.
- **No hidden data sharing** — all footage stays on your device. Period.

---

## Minimum Lovable Products (MLPs)

The following three MLPs define the core value DriveCam delivers to users:

### MLP 1 — Strong Data Privacy 🔒

> *"Users will love having strong data security that doesn't get in the way of using the app."*

All video footage and metadata are stored **entirely on-device** using a local SQLite database and
the device's app document directory. DriveCam never transmits footage or personal data to any
server, including our own. This is a deliberate architectural decision — the absence of a backend
is itself the privacy guarantee.

**Why this matters:** Current dashcam apps on the market do not clearly disclose what data they
collect or how it is shared. DriveCam's local-only approach eliminates this concern entirely.

### MLP 2 — Fast and Flexible Clip Saving ✂️

> *"Users will love being able to quickly and easily save clips, with multiple options to do so."*

Drivers can't always react immediately after an incident. DriveCam addresses this with multiple
clip-saving trigger methods:

- **Manual tap** — tap the camera preview to immediately save a clip with configurable pre- and
  post-event duration.
- **Motion / sensor-based triggers** — the app can automatically detect events (planned).
- **Voice commands** — save a clip hands-free by speaking a phrase (planned).

Clips are extracted from the continuous recording buffer using FFmpeg, so no footage is lost
between the trigger and when the clip is actually saved.

### MLP 3 — Automatic Storage Management 💾

> *"Users will love not having to worry about data storage, running out of storage space, or losing
> access to potentially important clips."*

Continuous video recording consumes storage quickly. DriveCam manages this automatically:

- Configurable **storage limits** define the maximum space the app is allowed to use.
- When the limit is reached, the **oldest clips are deleted first** to make room for new ones.
- The most recent full recording is always kept available for clip extraction.
- Users can also configure **recording quality and framerate** to balance quality against storage
  usage.

---

## Platform Support

| Platform | Status |
|----------|--------|
| **Android** | ✅ Primary target |
| iOS | 🔄 Supported via Flutter (secondary) |

DriveCam is built with **[Flutter](https://flutter.dev/)**, Google's open-source UI framework,
which compiles to native Android and iOS code from a single Dart codebase. This means features
developed once work across both platforms without duplication.

To build for Android:

```bash
flutter build apk
```

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| UI Framework | [Flutter](https://flutter.dev/) (Dart) |
| State Management | Provider pattern (`ChangeNotifier`) |
| Video Recording | `camera` plugin + `ffmpeg_kit_flutter_new` |
| Local Storage | SQLite via `sqflite` |
| User Preferences | `shared_preferences` |
| Video Playback | `video_player` |

---

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart SDK `^3.10.4`)
- Android Studio or VS Code with Flutter/Dart extensions
- A physical Android device (camera access is required — emulators have limited camera support)

### Setup

```bash
# 1. Clone the repository
git clone https://github.com/rowandey/CS466-DriveCam.git
cd CS466-DriveCam/drivecam

# 2. Install dependencies
flutter pub get

# 3. Run the app on a connected device
flutter run
```

### Common Commands

```bash
flutter analyze        # Run the linter (uses flutter_lints)
flutter test           # Run unit tests
flutter build apk      # Build an Android APK
flutter build ios      # Build for iOS (requires macOS + Xcode)
```

---

## Project Architecture

DriveCam uses a layered architecture with four `ChangeNotifier` providers that manage all
application state:

- **`ThemeProvider`** — light/dark mode, persisted across sessions.
- **`SettingsProvider`** — recording quality, framerate, clip durations, and storage limits.
- **`RecordingProvider`** — owns the camera controller and recording lifecycle. Segments are
  concatenated by FFmpeg when a session ends.
- **`ClipProvider`** — handles clip extraction (pre/post buffer logic), FFmpeg processing,
  thumbnail generation, and storage limit enforcement.

Footage files (recordings, clips, thumbnails) are stored in the app's document directory. The
SQLite database tracks clip metadata and the most recent recording. See
[`drivecam/CLAUDE.md`](drivecam/CLAUDE.md) for a detailed architecture reference.

---

## Branding

| Token | Value |
|-------|-------|
| Primary Color | `#0072AC` (dark blue) |
| Secondary Color | `#4AB9E7` (light blue) |
| Light Accent | `#FFFFFF` |
| Dark Accent | `#1A1A1A` |
