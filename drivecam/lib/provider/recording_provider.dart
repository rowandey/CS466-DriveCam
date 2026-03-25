import 'dart:io';

import 'package:camera/camera.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/recording.dart';

class RecordingProvider extends ChangeNotifier {
  bool isRecording = false;
  CameraController? _controller;
  CameraController? get controller => _controller;
  DateTime? _recordingStartTime;
  DateTime? get recordingStartTime => _recordingStartTime;
  // Tracks the start of the current camera segment (resets on each clip save).
  // Used to compute correct in-segment offsets for clip extraction.
  DateTime? _segmentStartTime;
  DateTime? get segmentStartTime => _segmentStartTime;
  bool _isBusy = false;
  bool get isBusy => _isBusy;
  // Accumulates all stopped segments so they can be concatenated into one
  // continuous recording when the session ends.
  final List<String> _segments = [];

  // Callback invoked after a recording is saved; used by ClipProvider to
  // process any pending clip that was queued during the recording stop.
  Future<void> Function()? onRecordingSaved;

  void lockBusy() => _isBusy = true;
  void unlockBusy() => _isBusy = false;

  void addSegment(String path) => _segments.add(path);
  void setSegmentStartTime(DateTime t) => _segmentStartTime = t;

  void setCameraController(CameraController controller) {
    _controller = controller;
  }

  Future<void> toggleRecording() async {
    if (_isBusy) return;
    if (_controller == null || !_controller!.value.isInitialized) return;

    _isBusy = true;
    isRecording = !isRecording;
    notifyListeners();

    try {
      if (isRecording) {
        _segments.clear();
        await _controller!.startVideoRecording();
        final now = DateTime.now();
        _recordingStartTime = now;
        _segmentStartTime = now;
      } else {
        await _saveRecording();
      }
    } catch (e) {
      isRecording = !isRecording;
      notifyListeners();
      debugPrint('Recording toggle failed: $e');
    } finally {
      _isBusy = false;
    }
  }

  Future<void> _saveRecording() async {
    final xFile = await _controller!.stopVideoRecording();
    final duration = _recordingStartTime != null
        ? DateTime.now().difference(_recordingStartTime!).inSeconds
        : 0;
    _recordingStartTime = null;
    _segmentStartTime = null;

    // Set up storage directories
    final appDir = await getApplicationDocumentsDirectory();
    final recordingsDir = Directory('${appDir.path}/recordings');
    final thumbnailsDir = Directory('${appDir.path}/thumbnails');
    await Future.wait([
      recordingsDir.create(recursive: true),
      thumbnailsDir.create(recursive: true),
    ]);

    // Generate paths
    final id = const Uuid().v4();
    final videoPath = '${recordingsDir.path}/$id.mp4';
    final thumbnailPath = '${thumbnailsDir.path}/$id.jpg';

    // Include the final segment
    _segments.add(xFile.path);

    if (_segments.length == 1) {
      // No clip saves interrupted this session — move the file directly.
      await File(xFile.path).copy(videoPath);
      await File(xFile.path).delete();
    } else {
      // Clip saves caused stop/restart cycles. Concatenate all segments into
      // one continuous recording so the viewer sees the full session.
      await _concatenateSegments(_segments, videoPath, appDir.path);
      for (final seg in _segments) {
        try {
          await File(seg).delete();
        } catch (_) {}
      }
    }
    _segments.clear();

    // Get file size in bytes
    final fileSize = await File(videoPath).length();

    // Generate thumbnail from first frame
    await FFmpegKit.execute(
      '-y -i $videoPath -vframes 1 -q:v 2 $thumbnailPath',
    );
    final thumbnailExists = await File(thumbnailPath).exists();

    // Delete previous recording (single-row table)
    final existing = await Recording.openRecordingDB();
    if (existing != null) {
      try {
        await File(existing.recordingLocation).delete();
      } catch (_) {}
      if (existing.thumbnailLocation != null) {
        try {
          await File(existing.thumbnailLocation!).delete();
        } catch (_) {}
      }
      await existing.deleteRecordingDB();
    }

    // Save new recording to database
    final recording = Recording(
      id: id,
      recordingLocation: videoPath,
      recordingLength: duration,
      recordingSize: fileSize,
      thumbnailLocation: thumbnailExists ? thumbnailPath : null,
    );
    await recording.insertRecordingDB();
    // Process any clip request that arrived while recording was stopping.
    await onRecordingSaved?.call();
  }

  /// Concatenates multiple video segments into a single output file using the
  /// FFmpeg concat demuxer. Segments must be from the same codec/format.
  Future<void> _concatenateSegments(
    List<String> segments,
    String outputPath,
    String appDirPath,
  ) async {
    final fileListPath = '$appDirPath/concat_list.txt';
    // Escape single quotes in paths for the FFmpeg concat file format.
    final fileList = segments
        .map((s) => "file '${s.replaceAll("'", "'\\''")}'")
        .join('\n');
    await File(fileListPath).writeAsString(fileList);
    await FFmpegKit.execute(
      '-y -f concat -safe 0 -i $fileListPath -c copy $outputPath',
    );
    try {
      await File(fileListPath).delete();
    } catch (_) {}
  }
}
