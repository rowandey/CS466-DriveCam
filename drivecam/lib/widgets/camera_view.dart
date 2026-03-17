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

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _initFuture = _initCamera(settings.quality, settings.framerate);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = context.watch<SettingsProvider>();
    final quality = settings.quality;
    final framerate = settings.framerate;
    if (_currentQuality != null && (quality != _currentQuality || framerate != _currentFramerate)) {
      _controller?.dispose();
      setState(() {
        _controller = null;
        _initFuture = _initCamera(quality, framerate);
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done && _controller != null) {
          return SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller!.value.previewSize?.height ?? 1,
                height: _controller!.value.previewSize?.width ?? 1,
                child: CameraPreview(_controller!),
              ),
            ),
          );
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }
}
