// recording_provider.dart
// Manages the full lifecycle of a recording session: start/stop, segment
// tracking, rolling-buffer eviction, and final file assembly via FFmpeg.
//
// Rolling-buffer design:
//   Recording is split into segments when clips are saved, settings change,
//   or the periodic 5-minute flush timer fires. Each completed segment carries
//   a duration (seconds) and an estimated byte count (bitrate × duration ÷ 8).
//   After every addSegment call, _evictOldestIfNeeded drops the oldest
//   segment(s) from disk and the tracking list until both the time limit and
//   the storage limit from SettingsProvider are satisfied. The final saved
//   recording only contains the segments that survived eviction.

import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/recording.dart';
import 'settings_provider.dart';

// Holds metadata for one completed video segment so the rolling-buffer
// eviction logic can account for duration and estimated storage without
// additional disk I/O.
class _SegmentInfo {
  final String path;
  final int durationSeconds;
  final int estimatedBytes;
  const _SegmentInfo({
    required this.path,
    required this.durationSeconds,
    required this.estimatedBytes,
  });
}

class RecordingProvider extends ChangeNotifier {
  // SettingsProvider reference is required so eviction can read the current
  // footage time limit and storage limit without going through the widget tree.
  final SettingsProvider _settingsProvider;
  RecordingProvider(this._settingsProvider);

  bool isRecording = false;
  CameraController? _controller;
  CameraController? get controller => _controller;
  DateTime? _recordingStartTime;
  DateTime? get recordingStartTime => _recordingStartTime;
  // Tracks the start of the current camera segment (resets on each flush).
  // Used to compute correct in-segment offsets for clip extraction.
  DateTime? _segmentStartTime;
  DateTime? get segmentStartTime => _segmentStartTime;
  bool _isBusy = false;
  bool get isBusy => _isBusy;

  // Completed segments accumulated during this session. Each entry carries
  // path + duration + estimated size so eviction can be done without disk I/O.
  final List<_SegmentInfo> _segmentInfos = [];
  // Running totals updated by addSegment / _evictOldestIfNeeded so the check
  // is O(1) rather than O(n) on every segment add.
  int _totalSegmentDurationSeconds = 0;
  int _totalSegmentEstimatedBytes = 0;

  // The video bitrate (bps) set by CameraView after each controller init.
  // Required for per-segment byte estimation: bytes = bitrate × seconds ÷ 8.
  int? _videoBitrate;

  // Fires every 5 minutes while recording to flush the current segment to disk,
  // giving the rolling-buffer eviction a chance to drop old footage on time.
  Timer? _flushTimer;
  // CameraView sets this to its _doPeriodicFlush method after each controller
  // init. The timer calls it instead of accessing the controller directly,
  // keeping camera I/O in the widget layer where context is available.
  VoidCallback? onFlushRequested;

  // Callback invoked after a recording is saved; used by ClipProvider to
  // process any pending clip that was queued during the recording stop.
  Future<void> Function()? onRecordingSaved;

  void lockBusy() => _isBusy = true;
  void unlockBusy() => _isBusy = false;

  void setCameraController(CameraController controller) {
    _controller = controller;
  }

  /// Stores the target video bitrate (bps) for the current camera configuration.
  /// Called by CameraView after every (re)initialization so segment size
  /// estimation in addSegment always uses the current encoding bitrate.
  void setVideoBitrate(int bitrate) => _videoBitrate = bitrate;

  void setSegmentStartTime(DateTime t) => _segmentStartTime = t;

  /// Registers a completed segment and immediately enforces rolling-buffer limits.
  ///
  /// [path] is the on-disk path of the flushed segment file.
  /// [durationSeconds] is how long this segment ran; used for time-limit checks
  /// and to estimate stored bytes via bitrate × duration ÷ 8.
  /// After adding, _evictOldestIfNeeded deletes the oldest segment(s) as needed
  /// so the total stays within both the footage time limit and storage limit.
  void addSegment(String path, int durationSeconds) {
    // Estimate storage consumed by this segment. Using the fixed encoder bitrate
    // gives reliable estimates because the camera controller is constrained to
    // that bitrate. Fall back to 0 if bitrate isn't set yet (should not happen
    // in normal use since setVideoBitrate is called before recording starts).
    final estimatedBytes = _videoBitrate != null
        ? (_videoBitrate! * durationSeconds) ~/ 8
        : 0;
    _segmentInfos.add(_SegmentInfo(
      path: path,
      durationSeconds: durationSeconds,
      estimatedBytes: estimatedBytes,
    ));
    _totalSegmentDurationSeconds += durationSeconds;
    _totalSegmentEstimatedBytes += estimatedBytes;
    _evictOldestIfNeeded();
  }

  /// Deletes oldest segments from disk and the tracking list until accumulated
  /// duration and estimated storage are both within the user's configured limits.
  /// Called automatically by addSegment — no need to call it directly.
  void _evictOldestIfNeeded() {
    final limitSeconds = SettingsProvider.footageLimitToSeconds(
      _settingsProvider.footageLimit,
    );
    final limitBytes = SettingsProvider.storageLimitToBytes(
      _settingsProvider.storageLimit,
    );
    // Loop from oldest to newest, dropping until both constraints are satisfied.
    // Design note: we only evict COMPLETED segments. The current in-progress
    // segment (still being written by the camera controller) cannot be evicted
    // here; the periodic flush creates checkpoints so it becomes evictable.
    while (_segmentInfos.isNotEmpty) {
      final overTime = _totalSegmentDurationSeconds > limitSeconds;
      final overStorage = _totalSegmentEstimatedBytes > limitBytes;
      if (!overTime && !overStorage) break;
      final oldest = _segmentInfos.removeAt(0);
      _totalSegmentDurationSeconds -= oldest.durationSeconds;
      _totalSegmentEstimatedBytes -= oldest.estimatedBytes;
      // Permanently delete the evicted segment — this is intentional rolling-
      // buffer behavior, not an error. The user's chosen limits define how
      // much history is retained.
      try {
        File(oldest.path).deleteSync();
      } catch (_) {}
    }
  }

  /// Starts the periodic 5-minute flush timer that drives rolling-buffer
  /// enforcement during long recordings with no clip saves or settings changes.
  void _startFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      // Delegate the actual stop/restart to CameraView so camera I/O stays
      // in the widget layer where the controller and context are accessible.
      onFlushRequested?.call();
    });
  }

  void _stopFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  /// Toggles between recording and stopped states.
  /// On start: clears accumulated segments, starts the flush timer.
  /// On stop: cancels the flush timer, saves and concatenates all segments.
  Future<void> toggleRecording() async {
    if (_isBusy) return;
    if (_controller == null || !_controller!.value.isInitialized) return;

    _isBusy = true;
    isRecording = !isRecording;
    notifyListeners();

    try {
      if (isRecording) {
        // Clear any leftover state from a previous session before starting fresh.
        _segmentInfos.clear();
        _totalSegmentDurationSeconds = 0;
        _totalSegmentEstimatedBytes = 0;
        await _controller!.startVideoRecording();
        final now = DateTime.now();
        _recordingStartTime = now;
        _segmentStartTime = now;
        // Begin periodic flushes so rolling-buffer limits are enforced even
        // when no clips are saved and no settings changes occur.
        _startFlushTimer();
      } else {
        // Stop the flush timer before saving so it can't fire mid-save.
        _stopFlushTimer();
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

    // Build the full ordered path list: survived segments + live final file.
    // Segments that were evicted by _evictOldestIfNeeded are already deleted
    // from disk and removed from _segmentInfos, so they are not included here.
    final allPaths = [
      ..._segmentInfos.map((s) => s.path),
      xFile.path,
    ];

    if (allPaths.length == 1) {
      // No prior segments (either none were created or all were evicted) —
      // move the single final file directly without FFmpeg overhead.
      await File(xFile.path).copy(videoPath);
      await File(xFile.path).delete();
    } else {
      // Concatenate surviving segments + the live final file into one
      // continuous recording that covers whatever the rolling buffer retained.
      await _concatenateSegments(allPaths, videoPath, appDir.path);
      for (final path in allPaths) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
    }

    // Clear rolling-buffer tracking state for this session.
    _segmentInfos.clear();
    _totalSegmentDurationSeconds = 0;
    _totalSegmentEstimatedBytes = 0;

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
