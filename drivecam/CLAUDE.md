# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

DriveCam is a Flutter dashcam app for recording video footage and saving clips. It targets mobile platforms, specifically iOS and Android.

## Common Commands

```bash
flutter pub get       # Install dependencies
flutter run           # Run the app
flutter analyze       # Lint (uses flutter_lints)
flutter test          # Run tests
flutter build apk     # Android
flutter build ios     # iOS
```

## Additional Instructions
This is a college level Computer Science Student project and the intent of this class is to provide a learning experience for the student.  The students should learn core fundamental programming skills but also be able to use AI LLM assist agents. 

Provide guidance and suggestions and in comments to help the student learn and grow as a developer. The instructions should be clear, concise, and actionable, and should encourage the student to think critically about their code and the design decisions they make.

Conversation rules:
- Indicate the the coder that this LLM configuration file is in use. This will help the student understand that the instructions provided are based on the guidelines outlined in this file and can serve as a reference for future coding projects.
- Encourage the student to ask questions about the code and the design decisions made, and provide explanations to help them understand the concepts and best practices involved. This will foster a collaborative learning environment and help the student grow as a developer.
 - Highlight scale limitation and potential performance issues in the code, and suggest ways to optimize it for larger datasets or more complex scenarios. This will help the student understand the importance of writing efficient code and considering scalability in their designs.
 - Highlight security implications of the code, and suggest ways to mitigate potential vulnerabilities. This will help the student understand the importance of writing secure code and considering security in their designs.
 - Highlight maintainability issues in the code, and suggest ways to improve it for better readability and ease of maintenance. This will help the student understand the importance of writing maintainable code and considering maintainability in their designs.
 - Encourage the student to write tests for their code, and provide guidance on how to write effective tests that cover different scenarios and edge cases. This will help the student understand the importance of testing and how to ensure their code is robust and reliable.
 - Provide feedback on the student's code, including suggestions for improvement and areas where they can learn more. This will help the student identify areas for growth and encourage them to continue learning and improving their skills as a developer.

Anytime code is added or modified, ensure that it adheres to the following guidelines:
 - A comment should be added above any segment of code added or modified that explains how the code works and if there are any design decisions that were made. This will help the student understand the code and the reasoning behind it.
 - Every function should have a comment above it that explains what the function does, its parameters, and its return value. This will help the student understand the purpose of the function and how to use it effectively.
 - Every file should have a comment at the top that explains the purpose of the file and any important information about its contents. This will help the student understand the overall structure of the project and how different files relate to each other.
 - Follow consistent coding style and conventions throughout the codebase, such as naming conventions, indentation, and formatting. This will help the student understand the importance of writing clean and consistent code, and make it easier for them to read and maintain their code in the future.
 - For user interface behavior implementation and styling, refer to documentation in the /doc directory for design guidelines, application purpose, customer feedback and branding best practices. This will help the student understand the importance of following design guidelines and best practices when implementing user interfaces, and ensure that their code is consistent with the overall design of the project. 
 

## Architecture

**State management** uses the Provider pattern with four `ChangeNotifier` providers (`lib/provider/`) initialized in `main.dart`. All preferences are loaded eagerly in `main()` before `runApp`:
- `ThemeProvider` — light/dark mode persisted via `shared_preferences`. Defines full `ColorScheme` objects for both themes and a `clipSavedColor`.
- `SettingsProvider` — recording/clip settings (framerate, quality, durations, storage limits) and `onboardingComplete` flag, persisted via `shared_preferences`.
- `RecordingProvider` — owns recording state and lifecycle. Manages start/stop via `CameraController`, saves recordings with FFmpeg thumbnail generation, and tracks segments for concatenation via FFmpeg concat demuxer when the session ends. Exposes `recordingStartTime` for the elapsed-time indicator. Accepts an `onRecordingSaved` callback (used by `ClipProvider`) invoked after each recording is saved.
- `ClipProvider` — owns clip saving logic and clip notification state. Handles pre/post duration timer logic, FFmpeg clip extraction, thumbnail generation, and storage limit enforcement. Supports saving clips from a live recording (stop/restart cycle) or from the most recent saved recording. Manages `clipSaved`, `clipInProgress`, `clipProgressEndTime`, and `_pendingClip` (queued clip deferred until the current recording save completes).

**Database** (`lib/database/`): SQLite via `sqflite`, accessed through a singleton `DatabaseHelper`. Initialized eagerly in `main()` via `DatabaseHelper().database`. Schema is defined in `queries.dart`:
- `recording` table — single-row table representing the most recent completed recording. Replaced each time a new recording finishes.
- `clips` table — one row per saved clip with metadata (timestamp, duration, size, trigger type, flagged status, file paths). Ordered by `date_time DESC`.

**Screens** (`lib/screens/`):
- `main_shell.dart` — root scaffold wrapping `HomePage` with `RecordingIndicator` and `ClipSavedNotification` overlays plus `MyBottomNavBar`. Checks `onboardingComplete` on first load and pushes the onboarding flow if needed.
- `home_page.dart` — wraps `CameraView` widget. Loads theme prefs on init.
- `settings.dart` — uses shared `SettingsList` widget with `MyAppBar` and `MyBottomNavBar`.
- `onboarding/onboarding.dart` — welcome screen with branding and "Begin Setup" button.
- `onboarding/onboarding_settings.dart` — reuses `SettingsList` for initial config; "Finish Setup" calls `completeOnboarding()` and pops back to root.
- `footage/all_footage_display.dart` — shows `ClipDisplay` grid and `RecordingDisplay` separated by a divider. Tapping the recording navigates to `FootageViewer`.
- `footage/clip_display.dart` — `StatefulWidget` that loads all clips from DB, renders a 2-column grid of `_ClipTile` widgets with thumbnails, size, duration, and a delete button. Tapping navigates to `FootageViewer` with the clip's file path. Refreshes after deletion.
- `footage/recording_display.dart` — `StatefulWidget` showing the latest recording thumbnail, size, duration, and a delete button. Refreshes after deletion.
- `footage/footage_viewer.dart` — full-screen video player. Accepts an optional `filePath` (used for clips); falls back to loading the latest recording from DB. Uses `VideoPlayerController.file`. Portrait: video fills available space with `FootageEditor` below. Landscape: video fills the body with `FootageEditor` controls overlaid at the bottom via a gradient `Stack`.

**Widgets** (`lib/widgets/`):
- `camera_view.dart` — owns the `CameraController`, initialized from `SettingsProvider` quality/framerate. Reinitializes when settings change or when the device is rotated while not recording (camera plugin sets preview rotation at init time). Preview sizing is orientation-aware (swaps sensor dimensions in portrait, uses them directly in landscape). Tapping the preview triggers clip saving with pre/post duration timer logic.
- `recording_button.dart` — red when recording, gray otherwise, driven by `RecordingProvider`. Calls `toggleRecording()` on press.
- `delete_button.dart` — reusable `Positioned` delete button for thumbnail stacks. Shows a confirmation dialog before calling the `onDelete` callback.
- `footage_editor.dart` — video scrubber, playback controls, clip range selection, and Save Clip button. In landscape, collapses into a single compact row to minimise vertical footprint over the video overlay.
- `app_bars/bottom_app_bar.dart` — navigation bar with footage, recording button, and settings. Uses `NavPage` enum to track the active page; tapping the active page's icon pops back.
- `app_bars/app_bar.dart` — reusable `MyAppBar` with a title, themed with `colorScheme.primary`.
- `notifications_and_indicators/recording_indicator.dart` — red pill overlay showing "Recording MM:SS" elapsed time, driven by a 1-second timer while `isRecording` is true.
- `notifications_and_indicators/clip_saved_notification.dart` — shows an orange "Clip in progress N" countdown pill while `clipInProgress` is true (post-duration timer running), then transitions to a green "Clip Saved" pill when `clipSaved` is true. Dismissible on tap.
- `settings/setting_dropdown.dart` — reusable labeled dropdown used across settings screens.
- `settings/settings_list.dart` — extracted `ListView` of all settings dropdowns and dark mode toggle, shared by `SettingsScreen` and `OnboardingSettings`.

**Models** (`lib/models/`):
- `recording.dart` — `Recording` with `insertRecordingDB`, `openRecordingDB`, `updateRecordingDB`, `deleteRecordingDB` methods backed by SQLite.
- `clip.dart` — `Clip` with `insertClipDB`, `loadAllClips`, `updateFlagDB`, `deleteClipDB`, `deleteOldestClipDB` methods backed by SQLite.

**File storage**: Recordings are saved to `<appDocuments>/recordings/<uuid>.mp4`. Clips are saved to `<appDocuments>/clips/<uuid>.mp4`. Thumbnails (first frame, extracted by ffmpeg) are saved to `<appDocuments>/thumbnails/<uuid>.jpg`. When a new recording finishes, the previous recording's files and DB row are deleted first. When clips are saved during a live recording, the recording is stopped and restarted; all segments are tracked and concatenated into one continuous file at session end.

**Orientation**: All screens support portrait and landscape. `CameraView` reinitializes the controller on rotation (when not recording) so the platform camera plugin picks up the new orientation. `FootageViewer` uses an overlay `Stack` layout in landscape. All other screens use standard Flutter layouts (`ListView`, `SingleChildScrollView`) that adapt naturally.

## Brand Colors

- Light blue: `#4AB9E7`
- Dark blue: `#0072AC`
