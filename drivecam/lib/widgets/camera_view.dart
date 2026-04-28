// CameraView — hosts the live camera preview and drives clip/recording triggers.
//
// Before this rewrite the widget used Flutter's camera plugin (CameraController
// + CameraPreview). That plugin internally calls MediaRecorder.stop() on the
// Android main thread during each HLS segment rotation, causing a visible
// freeze every 5 seconds.
//
// This version replaces the camera plugin with our own Camera2 + MediaRecorder
// pipeline (HlsRecorderHandler.kt) exposed through HlsRecorderChannel. The
// preview is rendered with a plain Flutter Texture widget backed by a Camera2
// SurfaceTexture registered with Flutter's TextureRegistry.
//
// Permission handling:
//   The Flutter camera plugin previously requested CAMERA and RECORD_AUDIO
//   permissions automatically during CameraController.initialize(). Since we
//   now call Camera2 directly, we must request them ourselves via
//   permission_handler before opening the device.
//
//   _checkAndRequestPermissions() is called from initState (via _initFuture).
//   It requests CAMERA always and MICROPHONE when audio is enabled.  If the
//   user permanently denies the permission, we show an actionable error with a
//   button that opens the system app settings.
//
// Orientation handling:
//   Camera2 sensors on Android phones are physically mounted in landscape
//   (sensor orientation = 90° for most back cameras). The raw frames that
//   land in the SurfaceTexture are therefore in landscape regardless of how
//   the phone is held.
//
//   In landscape mode no correction is needed — sensor landscape matches
//   display landscape. In portrait mode the Texture must be rotated 90° CCW
//   (= 270° CW = quarterTurns: 3 in RotatedBox) to appear upright.
//
//   The formula `(4 - sensorOrientation ~/ 90) % 4` generalises this for any
//   sensor orientation value, not just the common 90°:
//     sensorOrientation = 90  → (4 - 1) % 4 = 3 quarter-turns CW ✓
//     sensorOrientation = 270 → (4 - 3) % 4 = 1 quarter-turn  CW ✓
//
// Settings change while recording:
//   Only the audio toggle can change while recording (the quality/fps dropdowns
//   are disabled). When it changes this widget calls pauseSessionForSwap() →
//   HlsRecorderChannel.updateSettings() → resumeSessionWith(), which updates
//   the MediaRecorder's audio setting without closing the camera. There is one
//   brief capture-session reconfiguration (startRecording() adds the recorder
//   surface), but the camera device stays open throughout.

import 'dart:async';

import 'package:drivecam/export/hls_recorder_channel.dart';
import 'package:drivecam/provider/clip_provider.dart';
import 'package:drivecam/provider/recording_provider.dart';
import 'package:drivecam/provider/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

class CameraView extends StatefulWidget {
  const CameraView({super.key});

  @override
  State<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView> {
  // Flutter Texture ID returned by HlsRecorderChannel.initialize().
  int? _textureId;

  // Actual preview dimensions (in sensor / native coordinates, always landscape
  // for a back camera with 90° sensor orientation).
  int _previewWidth  = 1280;
  int _previewHeight = 720;

  // Sensor orientation in degrees. Used to compute the rotation correction for
  // the preview Texture widget. Typically 90 for back cameras on Android phones.
  int _sensorOrientation = 90;

  // Tracks which settings were used to initialise the camera, so we can detect
  // changes that require a reinitialisation.
  String? _currentQuality;
  String? _currentFramerate;
  bool?   _currentAudioEnabled;

  // Set to true when the user has permanently denied a required permission.
  // The build() method shows an error UI instead of a spinner/preview.
  bool _permissionDenied = false;

  // Future that resolves when the camera is ready (permissions granted + native
  // camera open). FutureBuilder uses this to show a loading spinner until the
  // first frame is available.
  late Future<void> _initFuture;

  // Post-duration clip timer: if postDuration > 0 s the clip is saved after
  // the timer fires, not immediately on tap.
  Timer? _clipTimer;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    // Permission check is the first step — _initCamera() only runs if granted.
    _initFuture = _checkAndRequestPermissions(
      settings.quality,
      settings.framerate,
      settings.audioEnabled,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Permission handling
  // ─────────────────────────────────────────────────────────────────────────

  /// Request CAMERA (always) and MICROPHONE (when audio is enabled) at runtime.
  ///
  /// The Flutter camera plugin previously did this automatically inside
  /// CameraController.initialize(). Since we now own the Camera2 pipeline we
  /// must request them ourselves before calling HlsRecorderChannel.initialize().
  ///
  /// Parameters:
  ///   [quality]      — forwarded to _initCamera on success.
  ///   [framerate]    — forwarded to _initCamera on success.
  ///   [audioEnabled] — determines whether MICROPHONE is also requested.
  Future<void> _checkAndRequestPermissions(
    String quality,
    String framerate,
    bool audioEnabled,
  ) async {
    // Build the list of permissions we need for this configuration.
    final permissions = [
      Permission.camera,
      if (audioEnabled) Permission.microphone,
    ];

    // request() shows the system dialog for any permission not yet decided.
    // Already-granted permissions are returned immediately with .granted.
    final statuses = await permissions.request();

    // Camera permission is mandatory — without it Camera2 throws SecurityException.
    if (statuses[Permission.camera] != PermissionStatus.granted) {
      if (mounted) setState(() => _permissionDenied = true);
      return;
    }

    // Microphone denial is non-fatal: record video-only instead of stopping.
    // HlsRecorderHandler handles audioEnabled=false gracefully.
    final effectiveAudio =
        audioEnabled && (statuses[Permission.microphone] == PermissionStatus.granted);

    await _initCamera(quality, framerate, effectiveAudio);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Camera initialisation
  // ─────────────────────────────────────────────────────────────────────────

  /// (Re)initialise the native camera recorder with the given settings.
  ///
  /// If the camera is already open (textureId != null) it is disposed first.
  /// HlsRecorderChannel.initialize() opens the Camera2 device, creates a
  /// SurfaceTexture preview, and returns the Flutter texture ID and the
  /// actual frame dimensions.
  ///
  /// Parameters:
  ///   [quality]       — quality label from SettingsProvider ("720p", etc.).
  ///   [framerate]     — framerate label ("30 fps", etc.).
  ///   [audioEnabled]  — whether to capture microphone audio.
  Future<void> _initCamera(
    String quality,
    String framerate,
    bool audioEnabled,
  ) async {
    // Dispose the current camera before opening a new one.
    if (_textureId != null) {
      await HlsRecorderChannel.dispose();
    }

    final size = SettingsProvider.qualityToSize(quality);
    final fps  = SettingsProvider.framerateToFps(framerate);

    final result = await HlsRecorderChannel.initialize(
      width:        size.width,
      height:       size.height,
      fps:          fps,
      audioEnabled: audioEnabled,
    );

    if (!mounted) return;
    setState(() {
      _textureId         = result['textureId'] as int;
      _previewWidth      = result['width']  as int;
      _previewHeight     = result['height'] as int;
      _sensorOrientation = result['sensorOrientation'] as int;
      _currentQuality        = quality;
      _currentFramerate      = framerate;
      _currentAudioEnabled   = audioEnabled;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Clip trigger
  // ─────────────────────────────────────────────────────────────────────────

  /// Handle a tap on the preview: trigger a clip save with the configured
  /// pre/post duration.
  Future<void> _triggerClipSave() async {
    final clipProvider     = context.read<ClipProvider>();
    final settingsProvider = context.read<SettingsProvider>();

    final secondsPre = SettingsProvider.clipDurationToSeconds(
      settingsProvider.preDurationLength,
    );
    final secondsPost = SettingsProvider.clipDurationToSeconds(
      settingsProvider.postDurationLength,
    );
    final seconds = secondsPre + secondsPost;

    if (secondsPost == 0) {
      clipProvider.saveClipFromLive(
        clipDurationSeconds: seconds,
        secondsPre:          secondsPre,
      );
    } else {
      _clipTimer?.cancel();
      clipProvider.startClipProgress(secondsPost);
      // Wait for the post-duration window to fill, then save.
      _clipTimer = Timer(Duration(seconds: secondsPost), () {
        clipProvider.saveClipFromLive(
          clipDurationSeconds: seconds,
          secondsPre:          secondsPre,
        );
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Mid-recording audio toggle
  // ─────────────────────────────────────────────────────────────────────────

  /// Handle the audio toggle while recording is active.
  ///
  /// Pauses the session (flushes the current segment), updates the audio
  /// setting on the native recorder, then resumes recording. The camera
  /// device stays open — only the capture session is reconfigured by
  /// startRecording() inside resumeSessionWith().
  ///
  /// Parameters:
  ///   [audioEnabled] — the new audio preference.
  Future<void> _reinitCameraWhileRecording(bool audioEnabled) async {
    final recordingProvider = context.read<RecordingProvider>();
    if (recordingProvider.isBusy) return;
    // Capture orientation before any await so context is not used across an async gap.
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    recordingProvider.lockBusy();
    try {
      // Flush the current segment and drop to preview-only mode.
      await recordingProvider.pauseSessionForSwap();

      // Push the new audio setting into the Kotlin handler without closing
      // the camera (no dispose/initialize round-trip needed).
      await HlsRecorderChannel.updateSettings(audioEnabled: audioEnabled);
      _currentAudioEnabled = audioEnabled;

      // Restart recording on the next segment with the updated setting.
      await recordingProvider.resumeSessionWith(
        deviceRotation: isLandscape ? 90 : 0,
      );
    } catch (e) {
      debugPrint('Camera reinit while recording failed: $e');
    } finally {
      recordingProvider.unlockBusy();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Settings / dependency changes
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settingsProvider = context.watch<SettingsProvider>();
    final quality          = settingsProvider.quality;
    final framerate        = settingsProvider.framerate;
    final audioEnabled     = settingsProvider.audioEnabled;

    final audioChanged =
        _currentAudioEnabled != null && audioEnabled != _currentAudioEnabled;

    // If the audio setting changed while actively recording, update the
    // native recorder without closing the camera.
    if (audioChanged && context.read<RecordingProvider>().isRecording) {
      _currentAudioEnabled = audioEnabled;
      _reinitCameraWhileRecording(audioEnabled);
      return;
    }

    // Full reinit when quality, framerate, or audio changes while NOT
    // recording. Orientation changes no longer trigger a reinit — the
    // RotatedBox in build() adapts automatically without touching the camera.
    final settingsChanged = _currentQuality != null &&
        (quality != _currentQuality ||
            framerate != _currentFramerate ||
            audioChanged);

    if (settingsChanged) {
      setState(() {
        _textureId  = null;
        // Re-run through permission check in case the user changed audio while
        // a microphone permission was previously denied.
        _initFuture = _checkAndRequestPermissions(quality, framerate, audioEnabled);
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _clipTimer?.cancel();
    // Dispose is fire-and-forget: we can't await in dispose().
    // ignore: unawaited_futures
    HlsRecorderChannel.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Show a clear error when the user has denied the camera permission.
    if (_permissionDenied) return _buildPermissionDenied(context);

    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            _textureId == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return _buildPreview(context);
      },
    );
  }

  /// Shown when the camera permission is permanently denied.
  ///
  /// Provides an "Open Settings" button so the user can grant the permission
  /// from the Android app settings page without leaving the app manually.
  Widget _buildPermissionDenied(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography, size: 64, color: Colors.white54),
            const SizedBox(height: 16),
            const Text(
              'Camera permission is required.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              'Grant camera access in Settings, then reopen the app.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60, fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              // openAppSettings() opens the system settings page for this app
              // so the user can toggle the camera permission without leaving.
              onPressed: openAppSettings,
              child: const Text('Open Settings'),
            ),
          ],
        ),
      ),
    );
  }

  /// Build the camera preview with tap-to-clip, orientation correction, and
  /// the menu button overlay.
  ///
  /// Orientation detection uses LayoutBuilder (actual pixel constraints) rather
  /// than MediaQuery.of(context).orientation. MediaQuery reports the *device*
  /// orientation which can lag or be incorrect when the parent scaffold
  /// constrains the available size differently from the screen. LayoutBuilder
  /// always reflects the real space this widget occupies, so the rotation
  /// correction is based on what is actually being rendered.
  Widget _buildPreview(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Portrait when the available height exceeds the available width.
        final isPortrait = constraints.maxHeight > constraints.maxWidth;

        // Compute how many 90° CW quarter-turns RotatedBox must apply so the
        // raw sensor frame (always in sensor coordinates) appears upright.
        //
        // The sensor orientation is the clockwise angle through which the raw
        // frame must be rotated to appear upright in portrait (device natural
        // orientation). Android Camera2 definition:
        //   sensorOrientation=90  → rotate raw frame 90° CW → upright portrait
        //   sensorOrientation=270 → rotate raw frame 270° CW → upright portrait
        //
        // In landscape the sensor's long axis aligns with the display, so no
        // correction is needed.
        final quarterTurns = isPortrait ? _sensorOrientation ~/ 90 : 0;

        final sensorW = _previewWidth.toDouble();
        final sensorH = _previewHeight.toDouble();

        // After rotation in portrait the sensor's width/height swap in layout
        // space. Use the post-rotation size for the outer SizedBox so FittedBox
        // scales with the correct aspect ratio.
        final displayW = isPortrait ? sensorH : sensorW;
        final displayH = isPortrait ? sensorW : sensorH;

        // RotatedBox applies the correction prior to layout so the parent sees
        // the corrected size. quarterTurns=0 in landscape is a no-op.
        final previewWidget = RotatedBox(
          quarterTurns: quarterTurns,
          child: SizedBox(
            width:  sensorW,
            height: sensorH,
            child:  Texture(textureId: _textureId!),
          ),
        );

        return Stack(
          children: [
            // The preview fills the available space with BoxFit.cover semantics,
            // cropping any excess rather than letterboxing.
            InkWell(
              onTap: _triggerClipSave,
              child: SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width:  displayW,
                    height: displayH,
                    child:  previewWidget,
                  ),
                ),
              ),
            ),
            // Menu button overlay: opens the end drawer from anywhere on the
            // camera preview without requiring a separate app bar.
            Positioned(
              top:   8,
              right: 8,
              child: IconButton(
                icon:      const Icon(Icons.menu),
                color:     Colors.white,
                iconSize:  28,
                onPressed: () => Scaffold.of(context).openEndDrawer(),
              ),
            ),
          ],
        );
      },
    );
  }
}
