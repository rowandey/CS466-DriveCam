import 'dart:io';

import 'package:camera/camera.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';

import '../models/clip.dart';
import '../models/recording.dart';

class RecordingProvider extends ChangeNotifier {
  bool isRecording = false;
  bool clipSaved = false;
  bool clipInProgress = false;
  DateTime? clipProgressEndTime;
  CameraController? _controller;
  DateTime? _recordingStartTime;
  DateTime? get recordingStartTime => _recordingStartTime;
  // Tracks the start of the current camera segment (resets on each clip save).
  // Used to compute correct in-segment offsets for clip extraction.
  DateTime? _segmentStartTime;
  bool _isBusy = false;
  // Pending clip request to process after recording stops.
  ({int secondsPre, String triggerType})? _pendingClip;
  // Accumulates all stopped segments so they can be concatenated into one
  // continuous recording when the session ends.
  final List<String> _segments = [];

  void dismissClipNotification() {
    clipSaved = false;
    notifyListeners();
  }

  void startClipProgress(int postDurationSeconds) {
    clipInProgress = true;
    clipSaved = false;
    clipProgressEndTime =
        DateTime.now().add(Duration(seconds: postDurationSeconds));
    notifyListeners();
  }

  void _clearClipProgress() {
    clipInProgress = false;
    clipProgressEndTime = null;
  }

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
    await _processPendingClip();
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

  /// Saves a clip of the last N seconds of the active recording.
  /// secondsPre is how many seconds before the trigger to include; used as
  /// the fallback clip length when the live recording is no longer available.
  Future<void> saveClipFromLive({
    required int clipDurationSeconds,
    required int secondsPre,
    String triggerType = 'manual',
  }) async {
    if (_isBusy || !isRecording) {
      // Queue for processing: immediately if not busy, or after _saveRecording completes
      _pendingClip = (secondsPre: secondsPre, triggerType: triggerType);
      if (!_isBusy) await _processPendingClip();
      return;
    }
    if (_controller == null || !_controller!.value.isInitialized) return;
    _isBusy = true;
    try {
      await _saveClipFromLive(clipDurationSeconds, triggerType);
      notifyListeners();
    } catch (e) {
      debugPrint('Clip save failed: $e');
    } finally {
      _isBusy = false;
    }
  }

  /// Saves a pending clip from the most recent recording, ending at the
  /// recording's last frame (the most recent available footage).
  Future<void> _processPendingClip() async {
    final pending = _pendingClip;
    _pendingClip = null;
    if (pending == null) return;
    final recording = await Recording.openRecordingDB();
    if (recording == null) return;
    final end = recording.recordingLength;
    if (end == 0) return;
    final start = (end - pending.secondsPre).clamp(0, end);
    await _saveClipFromRecording(start, end, pending.triggerType);
    notifyListeners();
  }

  /// Saves a clip from the most-recent saved recording between two time frames.
  Future<void> saveClipFromRecording({
    required int startSeconds,
    required int endSeconds,
    String triggerType = 'manual',
  }) async {
    if (isRecording) return;
    if (_isBusy) return;
    assert(endSeconds > startSeconds, 'endSeconds must be after startSeconds');
    _isBusy = true;
    try {
      await _saveClipFromRecording(startSeconds, endSeconds, triggerType);
      notifyListeners();
    } catch (e) {
      debugPrint('Clip save failed: $e');
    } finally {
      _isBusy = false;
    }
  }

  Future<void> _saveClipFromLive(
    int clipDurationSeconds,
    String triggerType,
  ) async {
    // Stop recording to flush the video file to disk.
    final xFile = await _controller!.stopVideoRecording();
    // Use _segmentStartTime (not _recordingStartTime) so the offset is relative
    // to this segment, not the entire session.
    final elapsed = _segmentStartTime != null
        ? DateTime.now().difference(_segmentStartTime!).inSeconds
        : clipDurationSeconds;

    // Restart immediately to minimise the gap in the continuous recording.
    await _controller!.startVideoRecording();
    _segmentStartTime = DateTime.now();

    final appDir = await getApplicationDocumentsDirectory();
    final clipsDir = Directory('${appDir.path}/clips');
    final thumbnailsDir = Directory('${appDir.path}/thumbnails');
    await Future.wait([
      clipsDir.create(recursive: true),
      thumbnailsDir.create(recursive: true),
    ]);

    final startSecs = (elapsed - clipDurationSeconds).clamp(0, elapsed);
    final actualDuration = elapsed - startSecs;

    final id = const Uuid().v4();
    final clipPath = '${clipsDir.path}/$id.mp4';
    final thumbnailPath = '${thumbnailsDir.path}/$id.jpg';
    final now = DateTime.now();

    await FFmpegKit.execute(
      '-y -i ${xFile.path} -ss $startSecs -t $actualDuration -c copy $clipPath',
    );

    // Keep xFile around — it is added to _segments so it can be concatenated
    // into the full session recording when recording stops.
    _segments.add(xFile.path);

    if (!await File(clipPath).exists()) return;

    final fileSize = await File(clipPath).length();
    await FFmpegKit.execute('-y -i $clipPath -vframes 1 -q:v 2 $thumbnailPath');

    await Clip(
      id: id,
      dateTime: now.toIso8601String(),
      dateTimePretty: DateFormat('yyyy-MM-dd HH:mm').format(now),
      clipLength: actualDuration,
      clipSize: fileSize,
      triggerType: triggerType,
      isFlagged: false,
      clipLocation: clipPath,
      thumbnailLocation: thumbnailPath,
    ).insertClipDB();
    _clearClipProgress();
    clipSaved = true;
  }

  Future<void> _saveClipFromRecording(
    int startSeconds,
    int endSeconds,
    String triggerType,
  ) async {
    final recording = await Recording.openRecordingDB();
    if (recording == null) return;

    final appDir = await getApplicationDocumentsDirectory();
    final clipsDir = Directory('${appDir.path}/clips');
    final thumbnailsDir = Directory('${appDir.path}/thumbnails');
    await Future.wait([
      clipsDir.create(recursive: true),
      thumbnailsDir.create(recursive: true),
    ]);

    final duration = endSeconds - startSeconds;

    final id = const Uuid().v4();
    final clipPath = '${clipsDir.path}/$id.mp4';
    final thumbnailPath = '${thumbnailsDir.path}/$id.jpg';
    final now = DateTime.now();

    await FFmpegKit.execute(
      '-y -i ${recording.recordingLocation} -ss $startSeconds -t $duration -c copy $clipPath',
    );

    if (!await File(clipPath).exists()) return;

    final fileSize = await File(clipPath).length();
    await FFmpegKit.execute('-y -i $clipPath -vframes 1 -q:v 2 $thumbnailPath');

    await Clip(
      id: id,
      dateTime: now.toIso8601String(),
      dateTimePretty: DateFormat('yyyy-MM-dd HH:mm').format(now),
      clipLength: duration,
      clipSize: fileSize,
      triggerType: triggerType,
      isFlagged: false,
      clipLocation: clipPath,
      thumbnailLocation: thumbnailPath,
    ).insertClipDB();
    _clearClipProgress();
    clipSaved = true;
  }
}
