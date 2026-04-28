// RecordingProvider — owns the recording lifecycle.
//
// The CameraController from the Flutter camera plugin has been removed from
// this class entirely. The native recorder (HlsRecorderHandler.kt) now owns
// the CameraDevice and MediaRecorder directly. This class only coordinates
// the Dart-side HlsRecordingSession and the DB/thumbnail steps.
//
// Key change from the previous implementation:
//   Before: toggleRecording() used CameraController.startVideoRecording() /
//           stopVideoRecording() for each segment, causing a platform-thread
//           freeze every 5 s.
//   After:  HlsRecordingSession delegates to HlsRecorderChannel, which calls
//           MediaRecorder.setNextOutputFile() with no camera-session change
//           and no preview freeze.
//
// The public API that ClipProvider and CameraView consume is unchanged:
//   isRecording, isBusy, toggleRecording(), onRecordingSaved,
//   pauseSessionForSwap(), resumeSessionWith()

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../export/hls_export_channel.dart';
import '../hls/hls_session.dart';
import '../models/recording.dart';

class RecordingProvider extends ChangeNotifier {
  bool isRecording = false;

  // When the currently-active recording session began, in wall-clock time.
  // Used by the UI's "Recording MM:SS" elapsed-time indicator.
  DateTime? _recordingStartTime;
  DateTime? get recordingStartTime => _recordingStartTime;

  // Cross-provider mutex: prevents ClipProvider and toggleRecording from
  // stepping on each other while one of them is manipulating the recorder.
  bool _isBusy = false;
  bool get isBusy => _isBusy;

  // The active HLS recording session, if any. ClipProvider reads this to
  // snapshot segment metadata while recording is ongoing.
  HlsRecordingSession? _session;
  HlsRecordingSession? get session => _session;

  /// Callback invoked after a recording is saved to disk and the DB.
  /// ClipProvider wires this up to process any pending clips that were
  /// queued while the recording was stopping.
  Future<void> Function()? onRecordingSaved;

  /// [lockBusy] and [unlockBusy] give ClipProvider a way to hold the mutex
  /// while it performs a multi-step clip save that must not race with a
  /// recording stop.
  void lockBusy()   => _isBusy = true;
  void unlockBusy() => _isBusy = false;

  /// Flip recording state: start if currently idle, stop-and-save if
  /// currently recording. Guarded by [_isBusy] so that taps during a
  /// save window are silently ignored rather than producing a race.
  Future<void> toggleRecording({int deviceRotation = 0}) async {
    if (_isBusy) return;

    _isBusy     = true;
    isRecording = !isRecording;
    notifyListeners();

    try {
      if (isRecording) {
        await _startSession(deviceRotation: deviceRotation);
      } else {
        await _stopSessionAndSave();
      }
    } catch (e) {
      // Revert the optimistic UI flip so the user doesn't get stuck with a
      // wrong recording indicator if the native layer fails.
      isRecording = !isRecording;
      notifyListeners();
      debugPrint('Recording toggle failed: $e');
    } finally {
      _isBusy = false;
    }
  }

  /// Create the HLS session directory and start native recording.
  ///
  /// Parameters:
  ///   [deviceRotation] — passed to the session so Kotlin can embed the
  ///     correct orientation hint in the MP4 file.
  Future<void> _startSession({int deviceRotation = 0}) async {
    final appDir        = await getApplicationDocumentsDirectory();
    final recordingsRoot = p.join(appDir.path, 'recordings');
    await Directory(recordingsRoot).create(recursive: true);

    _session = await HlsRecordingSession.create(recordingsRootDir: recordingsRoot);
    await _session!.start(deviceRotation: deviceRotation);
    _recordingStartTime = DateTime.now();
  }

  /// Stop the session, extract a thumbnail, replace the DB row, and invoke
  /// the [onRecordingSaved] callback so ClipProvider can process pending clips.
  Future<void> _stopSessionAndSave() async {
    final session = _session;
    if (session == null) return;

    // stop() finalises the last segment and seals the manifest.
    await session.stop();

    final duration = _recordingStartTime != null
        ? DateTime.now().difference(_recordingStartTime!).inSeconds
        : session.totalDurationSecs.round();
    _recordingStartTime = null;
    _session            = null;

    // Sum segment file sizes for the DB metadata. The manifest itself is
    // small enough to ignore; this gives a cheap answer without MP4 parsing.
    var fileSize = 0;
    for (final seg in session.segments) {
      final f = File(p.join(session.sessionDir, seg.uri));
      if (await f.exists()) fileSize += await f.length();
    }

    // Generate a thumbnail from the first segment so the footage-library
    // screen can show a preview image without loading the full video.
    final appDir        = await getApplicationDocumentsDirectory();
    final thumbnailsDir = Directory(p.join(appDir.path, 'thumbnails'));
    await thumbnailsDir.create(recursive: true);
    final thumbnailPath = p.join(thumbnailsDir.path, '${session.id}.jpg');
    String? savedThumbnailPath;
    final firstSegPath = session.firstSegmentAbsolutePath;
    if (firstSegPath != null) {
      try {
        await HlsExportChannel.extractFirstFrame(
          videoPath:  firstSegPath,
          outputPath: thumbnailPath,
        );
        if (await File(thumbnailPath).exists()) {
          savedThumbnailPath = thumbnailPath;
        }
      } catch (e) {
        debugPrint('Thumbnail generation failed: $e');
      }
    }

    // Delete the previous recording's directory + thumbnail (the recording
    // table holds only one row at a time — single most-recent recording).
    final existing = await Recording.openRecordingDB();
    if (existing != null) {
      await _deleteRecordingArtifacts(existing);
      await existing.deleteRecordingDB();
    }

    final recording = Recording(
      id:                session.id,
      recordingLocation: session.manifestPath,
      recordingLength:   duration,
      recordingSize:     fileSize,
      thumbnailLocation: savedThumbnailPath,
    );
    await recording.insertRecordingDB();

    await onRecordingSaved?.call();
  }

  /// Best-effort cleanup of a recording's on-disk artifacts. The recording
  /// location is the manifest inside a session directory, so we delete the
  /// whole directory rather than a single file.
  ///
  /// Parameters:
  ///   [recording] — the DB row whose files should be removed.
  Future<void> _deleteRecordingArtifacts(Recording recording) async {
    final sessionDir = File(recording.recordingLocation).parent;
    try {
      if (await sessionDir.exists()) {
        await sessionDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Failed to delete recording dir: $e');
    }
    if (recording.thumbnailLocation != null) {
      try {
        await File(recording.thumbnailLocation!).delete();
      } catch (_) {}
    }
  }

  /// Called by CameraView when the audio setting changes while recording.
  /// Flushes the current segment and stops the native recorder (via the
  /// session) so CameraView can call [HlsRecorderChannel.updateSettings]
  /// and then [resumeSessionWith] to restart with the new audio setting.
  /// The camera stays open throughout — only the capture session is reconfigured.
  Future<void> pauseSessionForSwap() async {
    await _session?.pauseForSwap();
  }

  /// Counterpart to [pauseSessionForSwap]: restart native recording on the
  /// same session after the audio setting has been updated.
  ///
  /// Parameters:
  ///   [deviceRotation] — current device rotation for the MP4 orientation hint.
  Future<void> resumeSessionWith({int deviceRotation = 0}) async {
    await _session?.resumeWith(deviceRotation: deviceRotation);
  }
}
