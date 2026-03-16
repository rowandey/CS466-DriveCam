import 'dart:io';
import 'package:drivecam/models/recording.dart';
import 'package:flutter/material.dart';

class RecordingDisplay extends StatelessWidget {
  const RecordingDisplay({super.key});

  static String _formatDuration(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  // should only use GB when appropriate
  static String _formatSize(int? bytes) {
    if (bytes == null) return 'Unknown size';
    if (bytes >= 1024 * 1024 * 1024) {
      final gb = bytes / (1024 * 1024 * 1024);
      return '${gb.toStringAsFixed(2)} GB';
    }
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Recording?>(
      future: Recording.openRecordingDB(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final recording = snapshot.data;
        if (recording == null) {
          return const SizedBox(
            height: 200,
            child: Center(child: Text('No recording available')),
          );
        }

        final durationText = _formatDuration(recording.recordingLength);
        final sizeText = _formatSize(recording.recordingSize);

        return Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (recording.thumbnailLocation != null &&
                    File(recording.thumbnailLocation!).existsSync())
                  Image.file(
                    File(recording.thumbnailLocation!),
                    fit: BoxFit.cover,
                  )
                else
                  const Placeholder(),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '$sizeText - $durationText',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
