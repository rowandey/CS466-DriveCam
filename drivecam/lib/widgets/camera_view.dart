import 'package:camera/camera.dart';
import 'package:drivecam/provider/recording_provider.dart';
import 'package:drivecam/provider/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CameraView extends StatefulWidget {
  final CameraDescription camera;
  const CameraView({super.key, required this.camera});

  @override
  State<CameraView> createState() => _CameraViewState();
}


class _CameraViewState extends State<CameraView> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  String? _currentQuality;
  String? _currentFramerate;

  void _initCamera(String quality, String framerate) {
    _controller = CameraController(
      widget.camera,
      SettingsProvider.qualityToPreset(quality),
      fps: SettingsProvider.framerateToFps(framerate),
    );

    final recordingProvider = context.read<RecordingProvider>();
    _initializeControllerFuture = _controller.initialize().then((_) {
      recordingProvider.setCameraController(_controller);
    });
    _currentQuality = quality;
    _currentFramerate = framerate;
  }

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _initCamera(settings.quality, settings.framerate);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = context.watch<SettingsProvider>();
    final quality = settings.quality;
    final framerate = settings.framerate;
    if (_currentQuality != null && (quality != _currentQuality || framerate != _currentFramerate)) {
      _controller.dispose();
      setState(() => _initCamera(quality, framerate));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initializeControllerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          return SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller.value.previewSize?.height ?? 1,
                height: _controller.value.previewSize?.width ?? 1,
                child: CameraPreview(_controller),
              ),
            ),
          );
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }
}
