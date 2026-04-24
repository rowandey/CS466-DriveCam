import 'dart:async';

import 'package:camera/camera.dart';
import 'package:drivecam/provider/clip_provider.dart';
import 'package:drivecam/provider/recording_provider.dart';
import 'package:drivecam/provider/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CameraView extends StatefulWidget {
  const CameraView({super.key});

  @override
  State<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView> {
  CameraController? _controller;
  late Future<void> _initFuture;
  CameraDescription? _camera;
  String? _currentQuality;
  String? _currentFramerate;
  // Tracks the audio setting that was used when the controller was last created.
  // null until the first init completes.
  bool? _currentAudioEnabled;
  Orientation? _currentOrientation;
  Timer? _clipTimer;

  /// Initializes (or reinitializes) the [CameraController] with the given settings.
  Future<void> _initCamera(
    String quality,
    String framerate,
    bool audioEnabled,
  ) async {
    _camera ??= (await availableCameras()).first;
    // enableAudio controls whether the microphone is captured.
    final controller = CameraController(
      _camera!,
      SettingsProvider.qualityToPreset(quality),
      fps: SettingsProvider.framerateToFps(framerate),
      enableAudio: audioEnabled,
    );
    await controller.initialize();
    if (!mounted) return;
    context.read<RecordingProvider>().setCameraController(controller);
    _controller = controller;
    _currentQuality = quality;
    _currentFramerate = framerate;
    _currentAudioEnabled = audioEnabled;
  }

  Future<void> _triggerClipSave() async {
    final clipProvider = context.read<ClipProvider>();
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
        secondsPre: secondsPre,
      );
    } else {
      _clipTimer?.cancel();
      clipProvider.startClipProgress(secondsPost);
      // Clip is only actually taken and saved once post second counter expires.
      // Unfortunately, the technology to look into the future doesn't exist yet.
      _clipTimer = Timer(Duration(seconds: secondsPost), () {
        clipProvider.saveClipFromLive(
          clipDurationSeconds: seconds,
          secondsPre: secondsPre,
        );
      });
    }
  }

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _initFuture = _initCamera(settings.quality, settings.framerate, settings.audioEnabled);
  }

  /// Stops the current recording segment, disposes the old controller,
  /// reinitializes with new settings (e.g. a changed audio toggle), then
  /// restarts recording so the session continues uninterrupted.
  Future<void> _reinitCameraWhileRecording(
    CameraController oldController,
    String quality,
    String framerate,
    bool audioEnabled,
  ) async {
    final recordingProvider = context.read<RecordingProvider>();
    // Guard against concurrent clip saves or other busy operations.
    if (recordingProvider.isBusy) return;

    recordingProvider.lockBusy();
    try {
      // Flush the current video segment to disk so no footage is lost.
      final xFile = await oldController.stopVideoRecording();
      // Register the segment so it gets concatenated when recording ends.
      recordingProvider.addSegment(xFile.path);

      // Dispose the old controller before creating the new one.
      oldController.dispose();

      // Bring up a fresh controller with the updated settings.
      await _initCamera(quality, framerate, audioEnabled);
      if (!mounted) return;

      // Resume recording on the new controller to maintain a continuous session.
      await _controller!.startVideoRecording();
      recordingProvider.setSegmentStartTime(DateTime.now());
    } catch (e) {
      debugPrint('Camera reinit while recording failed: $e');
    } finally {
      recordingProvider.unlockBusy();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settingsProvider = context.watch<SettingsProvider>();
    final quality = settingsProvider.quality;
    final framerate = settingsProvider.framerate;
    final audioEnabled = settingsProvider.audioEnabled;
    final orientation = MediaQuery.of(context).orientation;

    final audioChanged =
        _currentAudioEnabled != null && audioEnabled != _currentAudioEnabled;

    // Special case: audio setting changed while actively recording.
    if (audioChanged && context.read<RecordingProvider>().isRecording) {
      _currentAudioEnabled = audioEnabled;
      final oldController = _controller!;
      setState(() {
        _controller = null;
        _initFuture = _reinitCameraWhileRecording(
          oldController,
          quality,
          framerate,
          audioEnabled,
        );
      });
      return;
    }

    // Include audio changes in the general "settings changed" check so a
    // non-recording reinit picks up the new enableAudio value.
    final settingsChanged = _currentQuality != null &&
        (quality != _currentQuality ||
            framerate != _currentFramerate ||
            audioChanged);
    final orientationChanged =
        _currentOrientation != null && orientation != _currentOrientation;
    _currentOrientation = orientation;

    // Reinitialize the camera when settings change, or when the device is
    // rotated while not recording.
    if (settingsChanged ||
        (orientationChanged &&
            !context.read<RecordingProvider>().isRecording)) {
      _controller?.dispose();
      setState(() {
        _controller = null;
        _initFuture = _initCamera(quality, framerate, audioEnabled);
      });
    }
  }

  @override
  void dispose() {
    _clipTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            _controller != null) {
          final previewSize = _controller!.value.previewSize;
          // previewSize is in sensor coordinates (landscape: width > height).
          // In portrait we swap to match the rotated display; in landscape the
          // sensor and screen orientations align so we use them directly.
          final width = isLandscape
              ? (previewSize?.width ?? 1)
              : (previewSize?.height ?? 1);
          final height = isLandscape
              ? (previewSize?.height ?? 1)
              : (previewSize?.width ?? 1);

          // Stack provides layering so the menu button can overlay the camera preview.
          // The menu button allows users to open the end drawer from the camera view.
          return Stack(
            children: [
              InkWell(
                onTap: () {
                  if (context.read<RecordingProvider>().isRecording) {
                    _triggerClipSave();
                  }
                },
                child: SizedBox.expand(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: width,
                      height: height,
                      child: CameraPreview(_controller!),
                    ),
                  ),
                ),
              ),
              // Menu button overlay positioned at top-right to access the navigation drawer.
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.menu),
                  color: Colors.white,
                  iconSize: 28,
                  onPressed: () => Scaffold.of(context).openEndDrawer(),
                ),
              ),
            ],
          );
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }
}
