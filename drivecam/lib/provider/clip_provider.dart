import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/clip.dart';
import '../models/recording.dart';
import 'recording_provider.dart';
import 'settings_provider.dart';

/// Owns clip saving logic, clip notification state, and clip storage enforcement.
///
/// After each clip is saved the provider checks whether the total size of all
/// stored clips exceeds [SettingsProvider.clipStorageLimit]. If so it deletes
/// the oldest clip(s) — FIFO, by [date_time] ascending — until the total is
/// back within the limit. This mirrors how [RecordingProvider] evicts old
/// recording segments.
class ClipProvider extends ChangeNotifier {
  final RecordingProvider _recordingProvider;
  final SettingsProvider _settingsProvider;

  // [_settingsProvider] is needed to read clipStorageLimit during eviction.
  ClipProvider(this._recordingProvider, this._settingsProvider);

  bool clipSaved = false;
  bool clipInProgress = false;
  DateTime? clipProgressEndTime;
  // Pending clip request to process after recording stops.
  ({int secondsPre, String triggerType})? _pendingClip;

  void dismissClipNotification() {
    clipSaved = false;
    notifyListeners();
  }

  /// Mark that a clip was saved and notify listeners.
  void markClipSaved() {
    clipSaved = true;
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

  /// Enforces the clip storage limit by deleting the oldest clips first.
  ///
  /// Loads all clips from the database, sums their sizes, then removes the
  /// oldest clip (lowest [date_time]) repeatedly until the total is within
  /// [SettingsProvider.clipStorageLimit]. Both the video file and its thumbnail
  /// are deleted from disk before the DB row is removed.
  ///
  /// This is intentionally called *after* [insertClipDB] so the newly saved
  /// clip is included in the total — if it alone would exceed the limit the
  /// enforcement still fires and evicts the oldest entry, which may be the
  /// clip that was just saved if no other clips exist.
  ///
  /// Exposed without a leading underscore so that unit tests can call it
  /// directly after seeding the database. Do not call this from production
  /// code outside of the two save methods below.
  @visibleForTesting
  Future<void> enforceClipStorageLimit() async {
    final limitBytes = SettingsProvider.clipStorageLimitToBytes(
        _settingsProvider.clipStorageLimit);

    // loadAllClips returns clips ordered date_time DESC (newest first),
    // so the oldest clip is always at the tail of the list.
    final clips = await Clip.loadAllClips();
    var totalBytes = clips.fold<int>(0, (sum, c) => sum + c.clipSize);
    int fromEnd = clips.length - 1;

    while (totalBytes > limitBytes && fromEnd >= 0) {
      final oldest = clips[fromEnd];
      // Delete files from disk; ignore errors if files are already missing.
      try { await File(oldest.clipLocation).delete(); } catch (_) {}
      try { await File(oldest.thumbnailLocation).delete(); } catch (_) {}
      await oldest.deleteClipDB();
      totalBytes -= oldest.clipSize;
      fromEnd--;
    }
  }

  /// Saves a clip of the last N seconds of the active recording.
  /// secondsPre is how many seconds before the trigger to include; used as
  /// the fallback clip length when the live recording is no longer available.
  Future<void> saveClipFromLive({
    required int clipDurationSeconds,
    required int secondsPre,
    String triggerType = 'manual',
  }) async {
    if (_recordingProvider.isBusy || !_recordingProvider.isRecording) {
      // Queue for processing: immediately if not busy, or after _saveRecording completes
      _pendingClip = (secondsPre: secondsPre, triggerType: triggerType);
      if (!_recordingProvider.isBusy) await processPendingClip();
      return;
    }
    if (_recordingProvider.controller == null ||
        !_recordingProvider.controller!.value.isInitialized) {
      return;
    }
    _recordingProvider.lockBusy();
    try {
      await _saveClipFromLive(clipDurationSeconds, triggerType);
      notifyListeners();
    } catch (e) {
      debugPrint('Clip save failed: $e');
    } finally {
      _recordingProvider.unlockBusy();
    }
  }

  /// Saves a pending clip from the most recent recording, ending at the
  /// recording's last frame (the most recent available footage).
  Future<void> processPendingClip() async {
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
    if (_recordingProvider.isRecording) return;
    if (_recordingProvider.isBusy) return;
    assert(endSeconds > startSeconds, 'endSeconds must be after startSeconds');
    _recordingProvider.lockBusy();
    try {
      await _saveClipFromRecording(startSeconds, endSeconds, triggerType);
      notifyListeners();
    } catch (e) {
      debugPrint('Clip save failed: $e');
    } finally {
      _recordingProvider.unlockBusy();
    }
  }

  Future<void> _saveClipFromLive(
    int clipDurationSeconds,
    String triggerType,
  ) async {
    final controller = _recordingProvider.controller!;
    // Stop recording to flush the video file to disk.
    final xFile = await controller.stopVideoRecording();
    // Use segmentStartTime (not recordingStartTime) so the offset is relative
    // to this segment, not the entire session.
    final elapsed = _recordingProvider.segmentStartTime != null
        ? DateTime.now().difference(_recordingProvider.segmentStartTime!).inSeconds
        : clipDurationSeconds;

    // Restart immediately to minimise the gap in the continuous recording.
    await controller.startVideoRecording();
    _recordingProvider.setSegmentStartTime(DateTime.now());

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

    // Re-encode clip to H.264/AAC for maximum compatibility with platform players.
    await FFmpegKit.execute(
      '-y -i ${xFile.path} -ss $startSecs -t $actualDuration -c:v libx264 -preset veryfast -crf 23 -c:a aac -b:a 128k $clipPath',
    );

    // Keep xFile around — it is added to segments so it can be concatenated
    // into the full session recording when recording stops. Pass elapsed so
    // rolling-buffer eviction in RecordingProvider can correctly account for
    // this segment's duration and estimated storage.
    _recordingProvider.addSegment(xFile.path, elapsed);

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

    // Remove oldest clip(s) if the total clip storage now exceeds the limit.
    await enforceClipStorageLimit();
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

    // Re-encode clip to H.264/AAC for maximum compatibility with platform players.
    await FFmpegKit.execute(
      '-y -i ${recording.recordingLocation} -ss $startSeconds -t $duration -c:v libx264 -preset veryfast -crf 23 -c:a aac -b:a 128k $clipPath',
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

    // Remove oldest clip(s) if the total clip storage now exceeds the limit.
    await enforceClipStorageLimit();
    _clearClipProgress();
    clipSaved = true;
  }
}
