import 'dart:async';

import 'package:drivecam/provider/recording_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class RecordingIndicator extends StatefulWidget {
  const RecordingIndicator({
    super.key,
  });

  @override
  State<RecordingIndicator> createState() => _RecordingIndicatorState();
}

class _RecordingIndicatorState extends State<RecordingIndicator> {
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _ensureTimer(bool isRecording) {
    if (isRecording && _timer == null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() {});
      });
    } else if (!isRecording && _timer != null) {
      _timer?.cancel();
      _timer = null;
    }
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RecordingProvider>(
      builder: (context, recording, _) {
        _ensureTimer(recording.isRecording);
        if (!recording.isRecording) return const SizedBox.shrink();

        final elapsed = recording.recordingStartTime != null
            ? DateTime.now().difference(recording.recordingStartTime!)
            : Duration.zero;

        return SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 12, top: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Recording ${_formatDuration(elapsed)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
