// HLS recording session: coordinates the native recorder (HlsRecorderChannel)
// to produce short MP4 segments and keeps the .m3u8 manifest on disk up to
// date after every rotation.
//
// How the freeze was fixed (design change from the previous version):
//   Before: _rotate() called controller.stopVideoRecording() +
//           controller.startVideoRecording(), which caused Android's
//           MediaRecorder.stop() to run on the platform thread and freeze
//           the UI every 5 seconds.
//
//   After:  _rotate() calls HlsRecorderChannel.rotateSegment(), which
//           forwards to MediaRecorder.setNextOutputFile() on the Kotlin side.
//           The encoder keeps running; the camera session is not touched;
//           the preview has zero interruption. No CameraController is needed.
//
// Other design notes:
//   - Kotlin writes segment files directly to the session directory using the
//     paths this class provides. No file-rename step is needed.
//   - In-memory _segments is updated immediately after rotateSegment returns
//     so ClipProvider snapshots are always current.
//   - Manifest appends are serialised via _ingestChain (a chained Future) so
//     the #EXTINF entries always land in segment order even when multiple
//     appends are queued.
//   - stop() and pauseForSwap() await _ingestChain before sealing the
//     manifest, ensuring no entries are lost.

import 'dart:async';
import 'dart:io';

import 'package:drivecam/export/hls_recorder_channel.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'hls_manifest.dart';

/// Owns the recording loop for a single session. One instance per recording.
/// Not reusable after [stop] is called — construct a new one for the next
/// session.
class HlsRecordingSession {
  /// Target duration per segment. The real durations are measured at rotation
  /// time and will be slightly shorter due to the keyframe-boundary rounding
  /// inherent to setNextOutputFile.
  static const int segmentTargetSeconds = 5;

  /// UUID identifying this recording. Also the session directory name.
  final String id;

  /// Absolute path to the session directory (contains manifest + segments).
  final String sessionDir;

  /// Absolute path to the manifest file. Clients store this in the DB as
  /// [Recording.recordingLocation].
  final String manifestPath;

  // All completed segments, in order. Updated immediately in _rotate() before
  // the manifest append, so ClipProvider.forceRotate() snapshots are current.
  final List<SegmentRef> _segments = [];

  // Index of the segment file currently being recorded.
  // seg_00000.mp4 = index 0, seg_00001.mp4 = index 1, etc.
  int _currentSegIndex = 0;

  // When the current segment started. Kept for forceRotate() fallback only;
  // primary duration measurement is now done in Kotlin.
  DateTime? _currentSegmentStart;

  // Periodic rotation timer. Null when the session is idle or stopped.
  Timer? _rotateTimer;

  // Guards against re-entrant _rotate() calls if a rotation is still awaiting
  // HlsRecorderChannel.rotateSegment() when the next timer tick fires.
  bool _rotating = false;

  bool _started = false;
  bool _stopped = false;

  // Sequential chain of manifest-append Futures. Each append is chained onto
  // the previous so entries always land in segment order. stop() and
  // pauseForSwap() await this chain before sealing the manifest.
  Future<void> _ingestChain = Future<void>.value();

  HlsRecordingSession._(this.id, this.sessionDir, this.manifestPath);

  /// Create a new session, materialising its directory on disk. Does not
  /// start recording — call [start] after the native recorder is ready.
  ///
  /// Parameters:
  ///   [recordingsRootDir] — absolute path to the directory under which the
  ///     per-session UUID subdirectory will be created.
  ///
  /// Returns the initialised (but not yet started) session.
  static Future<HlsRecordingSession> create({
    required String recordingsRootDir,
  }) async {
    final id = const Uuid().v4();
    final sessionDir = p.join(recordingsRootDir, id);
    await Directory(sessionDir).create(recursive: true);
    final manifestPath = p.join(sessionDir, 'manifest.m3u8');
    await HlsManifest.writeHeader(
      File(manifestPath),
      targetDurationSecs: segmentTargetSeconds + 1,
    );
    return HlsRecordingSession._(id, sessionDir, manifestPath);
  }

  /// Returns the filename for segment [index], e.g. "seg_00003.mp4".
  String _segName(int index) =>
      'seg_${index.toString().padLeft(5, '0')}.mp4';

  /// Snapshot of completed segments at this instant. Safe to iterate from
  /// any context — the returned list is a copy.
  List<SegmentRef> get segments => List.unmodifiable(_segments);

  /// Total duration of all completed segments in seconds. Does NOT include
  /// the currently-recording segment (not yet finalised).
  double get totalDurationSecs => HlsSegmentMath.totalDuration(_segments);

  /// When the currently-open segment started recording. Null when idle.
  DateTime? get currentSegmentStart => _currentSegmentStart;

  // ───────────────────────────────────────────────────────────────────────────
  // start
  // ───────────────────────────────────────────────────────────────────────────

  /// Begin recording. Kotlin starts writing to [seg_00000.mp4] and the
  /// rotation timer is armed. Throws [StateError] if called more than once.
  ///
  /// Parameters:
  ///   [deviceRotation] — current device rotation in degrees (0=portrait,
  ///     90=landscape) forwarded to Kotlin for the MP4 orientation hint.
  Future<void> start({int deviceRotation = 0}) async {
    if (_started) throw StateError('HlsRecordingSession already started');
    _started = true;
    _currentSegIndex = 0;
    final firstPath = p.join(sessionDir, _segName(0));
    await HlsRecorderChannel.startRecording(
      outputPath: firstPath,
      deviceRotation: deviceRotation,
    );
    _currentSegmentStart = DateTime.now();
    _rotateTimer = Timer.periodic(
      const Duration(seconds: segmentTargetSeconds),
      (_) => _safeRotate(),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // _safeRotate / _rotate
  // ───────────────────────────────────────────────────────────────────────────

  /// Guard wrapper: skips this rotation if a previous one is still running
  /// (can happen on a very slow device) or if the session has been stopped.
  Future<void> _safeRotate() async {
    if (_rotating || _stopped) return;
    _rotating = true;
    try {
      await _rotate();
    } catch (e) {
      debugPrint('HlsRecordingSession rotate failed: $e');
    } finally {
      // _rotating is cleared here, NOT after the manifest append completes.
      // The append runs via _ingestChain and is independent of this guard.
      _rotating = false;
    }
  }

  /// Core segmentation step. Calls MediaRecorder.setNextOutputFile() via the
  /// recorder channel, which switches the encoder's output at the next keyframe
  /// without any camera-session interaction. Then schedules the manifest append.
  ///
  /// The freeze that existed in the previous implementation (CameraController
  /// stop + start every 5 s) is eliminated here — the only work on the Dart
  /// side after the channel call is trivial in-memory bookkeeping.
  Future<void> _rotate() async {
    final completedIdx = _currentSegIndex;
    final nextIdx      = _currentSegIndex + 1;
    final nextPath     = p.join(sessionDir, _segName(nextIdx));

    // This is the key call. Kotlin forwards it to setNextOutputFile().
    // Returns the wall-clock elapsed time of the segment that just ended.
    final durationSecs = await HlsRecorderChannel.rotateSegment(
      nextOutputPath: nextPath,
    );
    // Update bookkeeping before scheduling the manifest append so that
    // forceRotate() callers see a current snapshot of _segments immediately.
    _currentSegIndex = nextIdx;
    _currentSegmentStart = DateTime.now();
    final ref = SegmentRef(uri: _segName(completedIdx), durationSecs: durationSecs);
    _segments.add(ref);

    // Schedule the manifest append without awaiting it. The ingest chain
    // serialises appends so #EXTINF entries always land in segment order.
    _scheduleManifestAppend(ref);
  }

  /// Append [ref] to the on-disk manifest as the next step in [_ingestChain].
  /// Each call chains onto the previous Future so that concurrent rotations
  /// never interleave their manifest writes.
  ///
  /// Parameters:
  ///   [ref] — the just-completed segment to record in the manifest.
  void _scheduleManifestAppend(SegmentRef ref) {
    _ingestChain = _ingestChain.then((_) async {
      await HlsManifest.appendSegment(File(manifestPath), ref);
    }).catchError((Object e) {
      debugPrint('HlsRecordingSession manifest append failed: $e');
    });
  }

  // ───────────────────────────────────────────────────────────────────────────
  // forceRotate
  // ───────────────────────────────────────────────────────────────────────────

  /// Force a rotation outside the periodic timer's schedule. Used by
  /// [ClipProvider] so a trigger clip can include footage up to the moment of
  /// the call, not just up to the last timer-fired segment.
  ///
  /// After this returns, [segments] contains the newly-completed segment.
  /// The manifest append may still be in flight via [_ingestChain], but the
  /// in-memory state is current — ClipProvider reads [segments], not the
  /// manifest file.
  Future<void> forceRotate() async {
    if (_stopped) return;
    await _safeRotate();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // pauseForSwap / resumeWith
  // ───────────────────────────────────────────────────────────────────────────

  /// Pause the session for a mid-recording settings change (e.g. audio toggle).
  ///
  /// Stops the native recorder to flush the current segment, cancels the timer,
  /// and drains all pending manifest appends. The session remains alive so
  /// [resumeWith] can resume recording on the same manifest without losing
  /// accumulated segments. The camera stays open; only the capture session is
  /// reconfigured (preview-only mode) by Kotlin's stopRecording().
  Future<void> pauseForSwap() async {
    if (_stopped) return;
    _rotateTimer?.cancel();
    _rotateTimer = null;

    // Spin-wait for any in-flight rotation to complete its channel call.
    while (_rotating) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    // Flush the current segment and return its duration.
    final durationSecs = await HlsRecorderChannel.stopRecording();
    if (durationSecs >= 0.1) {
      final ref = SegmentRef(uri: _segName(_currentSegIndex), durationSecs: durationSecs);
      _segments.add(ref);
      _scheduleManifestAppend(ref);
    }
    _currentSegmentStart = null;

    // Drain all queued manifest appends before the caller changes settings,
    // so the manifest is consistent when recording resumes.
    await _ingestChain;
  }

  /// Counterpart to [pauseForSwap]: start a fresh segment and re-arm the
  /// rotation timer after a settings change.
  ///
  /// Parameters:
  ///   [deviceRotation] — current device rotation for the MP4 orientation hint.
  ///
  /// Throws [StateError] if the session has already been stopped.
  Future<void> resumeWith({int deviceRotation = 0}) async {
    if (_stopped) throw StateError('Cannot resume a stopped HlsRecordingSession');
    _currentSegIndex++;
    final nextPath = p.join(sessionDir, _segName(_currentSegIndex));
    await HlsRecorderChannel.startRecording(
      outputPath: nextPath,
      deviceRotation: deviceRotation,
    );
    _currentSegmentStart = DateTime.now();
    _rotateTimer = Timer.periodic(
      const Duration(seconds: segmentTargetSeconds),
      (_) => _safeRotate(),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // stop
  // ───────────────────────────────────────────────────────────────────────────

  /// Stop recording, flush the last segment, wait for all queued manifest
  /// appends, and seal the manifest with #EXT-X-ENDLIST. After this returns,
  /// the manifest is a complete VOD playlist and the session is unusable.
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _rotateTimer?.cancel();
    _rotateTimer = null;

    // Wait for any in-flight _rotate() to finish its channel call.
    while (_rotating) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    // Finalise the last segment. Kotlin's stopRecording() runs MediaRecorder.stop()
    // on a background thread so the Dart event loop stays free during the MP4
    // finalisation step. The await here resolves once the preview session is
    // restored and the duration is known.
    final durationSecs = await HlsRecorderChannel.stopRecording();

    // Only record the segment if it has meaningful content (> 100 ms).
    // A sub-100ms fragment at the very start (user tapped stop immediately)
    // would look malformed to media players.
    if (durationSecs >= 0.1) {
      final ref = SegmentRef(uri: _segName(_currentSegIndex), durationSecs: durationSecs);
      _segments.add(ref);
      _scheduleManifestAppend(ref);
    }
    _currentSegmentStart = null;

    // Drain all pending manifest appends before writing #EXT-X-ENDLIST.
    // Without this the manifest could be sealed before the last #EXTINF
    // entry is written, producing a truncated VOD playlist.
    await _ingestChain;
    await HlsManifest.closeManifest(File(manifestPath));
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Accessors
  // ───────────────────────────────────────────────────────────────────────────

  /// Absolute path to the first completed segment's file (used by
  /// [RecordingProvider] for thumbnail extraction). Null if no segments have
  /// been completed yet (i.e. the recording was stopped before the first
  /// rotation — the last segment is at [_segName(0)] in that case, but it is
  /// added to [_segments] during [stop()], so callers should check
  /// [segments.isNotEmpty] after [stop()] returns).
  String? get firstSegmentAbsolutePath {
    if (_segments.isEmpty) return null;
    return p.join(sessionDir, _segments.first.uri);
  }
}
