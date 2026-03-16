import 'dart:io';

import 'package:drivecam/models/recording.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class FootageViewer extends StatefulWidget {
  const FootageViewer({super.key});

  @override
  State<FootageViewer> createState() => _FootageViewerState();
}

class _FootageViewerState extends State<FootageViewer> {
  VideoPlayerController? _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRecording();
  }

  Future<void> _loadRecording() async {
    final recording = await Recording.openRecordingDB();
    if (!mounted) return;

    if (recording == null) {
      setState(() {
        _loading = false;
        _error = 'No recording found.';
      });
      return;
    }

    final file = File(recording.recordingLocation);
    if (!file.existsSync()) {
      setState(() {
        _loading = false;
        _error = 'Recording file not found.';
      });
      return;
    }

    final controller = VideoPlayerController.file(file);
    await controller.initialize();
    if (!mounted) {
      controller.dispose();
      return;
    }

    setState(() {
      _controller = controller;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlayback() {
    final c = _controller!;
    setState(() {
      c.value.isPlaying ? c.pause() : c.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Recording'),
      ),
      body: Center(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const CircularProgressIndicator(color: Colors.white);
    }
    if (_error != null) {
      return Text(_error!, style: const TextStyle(color: Colors.white));
    }

    final controller = _controller!;
    return GestureDetector(
      onTap: _togglePlayback,
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(controller),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: VideoProgressIndicator(
                controller,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: Colors.white,
                  bufferedColor: Colors.white38,
                  backgroundColor: Colors.white12,
                ),
              ),
            ),
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: controller,
              builder: (context, value, child) => AnimatedOpacity(
                opacity: value.isPlaying ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 72,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
