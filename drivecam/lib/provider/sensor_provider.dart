// sensor_provider.dart
// Implements detection logic that fuses user-accelerometer and gyroscope
// signals to detect impacts or sudden movements and triggers an automatic
// clip save via the existing ClipProvider. The implementation intentionally
// keeps configuration simple (hardcoded defaults) so the system can be
// validated before adding tuning UI or persistence.

import 'dart:async';
import 'dart:math';

import 'package:drivecam/provider/clip_provider.dart';
import 'package:drivecam/provider/recording_provider.dart';
import 'package:drivecam/provider/settings_provider.dart';
import 'package:drivecam/services/sensor_service.dart';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// SensorProvider listens to the SensorService while recording and evaluates a
/// simple fused metric to decide whether to trigger an automatic clip save.
///
/// Design decisions:
/// - Uses `userAccelerometerEvents` (gravity-removed) and `gyroscopeEvents`.
/// - Combines magnitudes with configurable weights and compares against a
///   threshold. A short debounce and cooldown are applied to avoid spurious
///   re-triggers.
class SensorProvider extends ChangeNotifier {
  final RecordingProvider _recordingProvider;
  final ClipProvider _clipProvider;
  final SettingsProvider _settingsProvider;
  final SensorEventSource _sensorSource;
  final DateTime Function() _now;

  // Tunable parameters (defaults chosen conservatively).
  bool enabled = true; // Master toggle; can be expanded to persist later.
  double accelWeight = 1.0;
  double gyroWeight = 0.5;
  double metricThreshold = 12.0; // Combined metric threshold
  int debounceMs = 100; // Require metric > threshold for this duration
  int cooldownMs = 10000; // Minimum ms between triggers

  // Internal state
  StreamSubscription<UserAccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  DateTime? _candidateStart;
  DateTime? _lastTrigger;
  double _lastAccelMag = 0.0;
  double _lastGyroMag = 0.0;
  Timer? _postTimer;

  /// Create a SensorProvider backed by the given recording and clip providers
  /// and the settings provider (used to obtain pre/post durations).
  ///
  /// The optional [sensorSource] and [now] parameters are injected in tests so
  /// CSV fixtures can be replayed deterministically without touching the real
  /// hardware sensor APIs.
  SensorProvider(
    this._recordingProvider,
    this._clipProvider,
    this._settingsProvider,
    {
    SensorEventSource? sensorSource,
    DateTime Function()? now,
  }) : _sensorSource = sensorSource ?? SensorService(),
        _now = now ?? DateTime.now {
    // React to recording state changes to start/stop sensor subscriptions.
    _recordingProvider.addListener(_onRecordingChanged);
    // If app started while already recording, begin listening immediately.
    if (_recordingProvider.isRecording) _startListening();
  }

  /// Responds to recording state changes by turning the sensor listeners on
  /// and off with the recording session.
  void _onRecordingChanged() {
    if (!enabled) return;
    if (_recordingProvider.isRecording) {
      _startListening();
    } else {
      _stopListening();
    }
  }

  /// Starts the sensor source and subscribes to the accelerometer and
  /// gyroscope streams used by the fused impact detector.
  void _startListening() {
    _sensorSource.start();
    // Subscribe to the throttled broadcast streams from the service.
    _accelSub ??= _sensorSource.userAccelerometerStream.listen((e) {
      _lastAccelMag = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
      _evaluate();
    });
    _gyroSub ??= _sensorSource.gyroscopeStream.listen((e) {
      _lastGyroMag = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
      _evaluate();
    });
  }

  /// Cancels the active sensor subscriptions and clears any in-progress
  /// trigger state so a fresh recording starts from a clean slate.
  void _stopListening() {
    _accelSub?.cancel();
    _accelSub = null;
    _gyroSub?.cancel();
    _gyroSub = null;
    _sensorSource.stop();
    _candidateStart = null;
    _postTimer?.cancel();
    _postTimer = null;
  }

  /// Recomputes the fused sensor metric and decides whether the current sample
  /// sequence has crossed the threshold long enough to count as a trigger.
  void _evaluate() {
    // Compute fused metric
    final metric = accelWeight * _lastAccelMag + gyroWeight * _lastGyroMag;
    final now = _now();

    // If currently in cooldown, ignore
    if (_lastTrigger != null && now.difference(_lastTrigger!).inMilliseconds < cooldownMs) {
      _candidateStart = null;
      return;
    }

    if (metric >= metricThreshold) {
      _candidateStart ??= now;
      final elapsed = now.difference(_candidateStart!).inMilliseconds;
      if (elapsed >= debounceMs) {
        // Trigger and reset state
        _lastTrigger = now;
        _candidateStart = null;
        _onTrigger();
      }
    } else {
      // Reset candidate if metric falls back below threshold
      _candidateStart = null;
    }
  }

  /// Converts the current sensor state into a clip request using the same pre
  /// and post duration settings that the manual recording flow already uses.
  void _onTrigger() {
    // Use settings provider durations (pre + post) to match manual behavior
    final secondsPre = SettingsProvider.clipDurationToSeconds(
      _settingsProvider.preDurationLength,
    );
    final secondsPost = SettingsProvider.clipDurationToSeconds(
      _settingsProvider.postDurationLength,
    );
    final totalSeconds = secondsPre + secondsPost;

    // If post is zero, save immediately; otherwise start progress and wait
    if (secondsPost == 0) {
      _clipProvider.saveClipFromLive(
        clipDurationSeconds: totalSeconds,
        secondsPre: secondsPre,
        triggerType: 'sensor',
      );
    } else {
      // Start UI progress
      _clipProvider.startClipProgress(secondsPost);
      _postTimer?.cancel();
      _postTimer = Timer(Duration(seconds: secondsPost), () {
        _clipProvider.saveClipFromLive(
          clipDurationSeconds: totalSeconds,
          secondsPre: secondsPre,
          triggerType: 'sensor',
        );
      });
    }
  }

  /// Manually enable or disable sensor-based detection. When disabling the
  /// provider stops its subscriptions immediately.
  void setEnabled(bool value) {
    enabled = value;
    if (!enabled) {
      _stopListening();
    } else if (_recordingProvider.isRecording) {
      _startListening();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _recordingProvider.removeListener(_onRecordingChanged);
    _stopListening();
    super.dispose();
  }
}

