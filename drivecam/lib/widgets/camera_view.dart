import 'dart:async';

import 'package:camera/camera.dart';
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
  Timer? _clipTimer;

  Future<void> _initCamera(String quality, String framerate) async {
    _camera ??= (await availableCameras()).first;
    final controller = CameraController(
      _camera!,
      SettingsProvider.qualityToPreset(quality),
      fps: SettingsProvider.framerateToFps(framerate),
    );
    await controller.initialize();
    if (!mounted) return;
    context.read<RecordingProvider>().setCameraController(controller);
    _controller = controller;
    _currentQuality = quality;
    _currentFramerate = framerate;
  }

  Future<void> _triggerClipSave() async {
    final recordingProvider = context.read<RecordingProvider>();
    final settingsProvider = context.read<SettingsProvider>();

    final secondsPre = SettingsProvider.clipDurationToSeconds(
      settingsProvider.preDurationLength,
    );
    final secondsPost = SettingsProvider.clipDurationToSeconds(
      settingsProvider.postDurationLength,
    );
    final seconds = secondsPre + secondsPost;

    if (secondsPost == 0) {
      recordingProvider.saveClipFromLive(
        clipDurationSeconds: seconds,
        secondsPre: secondsPre,
      );
    } else {
      _clipTimer?.cancel();
      recordingProvider.startClipProgress(secondsPost);
      // Clip is only actually taken and saved once post second counter expires.
      // Unfortunately, the technology to look into the future doesn't exist yet.
      _clipTimer = Timer(Duration(seconds: secondsPost), () {
        recordingProvider.saveClipFromLive(
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
    _initFuture = _initCamera(settings.quality, settings.framerate);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settingsProvider = context.watch<SettingsProvider>();
    final quality = settingsProvider.quality;
    final framerate = settingsProvider.framerate;
    if (_currentQuality != null &&
        (quality != _currentQuality || framerate != _currentFramerate)) {
      _controller?.dispose();
      setState(() {
        _controller = null;
        _initFuture = _initCamera(quality, framerate);
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
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            _controller != null) {
          return InkWell(
            onTap: () {
              _triggerClipSave();
            },
            child: SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller!.value.previewSize?.height ?? 1,
                  height: _controller!.value.previewSize?.width ?? 1,
                  child: CameraPreview(_controller!),
                ),
              ),
            ),
          );
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }
}
