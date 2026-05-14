// sensor_provider_csv_test.dart
// Exercises the crash-detection provider with CSV fixtures that model sensor
// readings similar to what a BeamNG.tech export could provide. The tests keep
// the production app code unchanged by replaying the CSV data through a fake
// sensor source and a spy clip provider.

import 'dart:async';
import 'dart:io';

import 'package:drivecam/provider/clip_provider.dart';
import 'package:drivecam/provider/recording_provider.dart';
import 'package:drivecam/provider/settings_provider.dart';
import 'package:drivecam/provider/sensor_provider.dart';
import 'package:drivecam/services/sensor_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Small value object representing one CSV row from a sensor export.
class _CsvSensorSample {
  /// Creates a sample with the timestamp and sensor magnitudes from the CSV.
  const _CsvSensorSample({
    required this.timestampMs,
    required this.userAx,
    required this.userAy,
    required this.userAz,
    required this.gyroX,
    required this.gyroY,
    required this.gyroZ,
  });

  /// Sample timestamp measured in milliseconds from the start of the replay.
  final int timestampMs;

  /// Gravity-removed accelerometer x-axis reading.
  final double userAx;

  /// Gravity-removed accelerometer y-axis reading.
  final double userAy;

  /// Gravity-removed accelerometer z-axis reading.
  final double userAz;

  /// Gyroscope x-axis reading.
  final double gyroX;

  /// Gyroscope y-axis reading.
  final double gyroY;

  /// Gyroscope z-axis reading.
  final double gyroZ;

  /// Builds a sample from a CSV line with the expected numeric columns.
  factory _CsvSensorSample.fromCsvLine(String line) {
    final columns = line.split(',').map((part) => part.trim()).toList();
    if (columns.length < 7) {
      throw FormatException('Expected at least 7 columns in sensor CSV line: $line');
    }

    return _CsvSensorSample(
      timestampMs: int.parse(columns[0]),
      userAx: double.parse(columns[1]),
      userAy: double.parse(columns[2]),
      userAz: double.parse(columns[3]),
      gyroX: double.parse(columns[4]),
      gyroY: double.parse(columns[5]),
      gyroZ: double.parse(columns[6]),
    );
  }
}

/// Fake sensor source that lets the test push accelerometer and gyroscope data
/// directly into the provider.
class _FakeSensorSource implements SensorEventSource {
  /// Creates the in-memory sensor source with sync broadcast streams so replay
  /// steps remain deterministic.
  _FakeSensorSource()
      : _accelController =
            StreamController<UserAccelerometerEvent>.broadcast(sync: true),
        _gyroController = StreamController<GyroscopeEvent>.broadcast(sync: true);

  final StreamController<UserAccelerometerEvent> _accelController;
  final StreamController<GyroscopeEvent> _gyroController;

  /// Counts how many times the production code asked this source to start.
  int startCalls = 0;

  /// Counts how many times the production code asked this source to stop.
  int stopCalls = 0;

  @override
  Stream<UserAccelerometerEvent> get userAccelerometerStream =>
      _accelController.stream;

  @override
  Stream<GyroscopeEvent> get gyroscopeStream => _gyroController.stream;

  @override
  void start() {
    startCalls++;
  }

  @override
  void stop() {
    stopCalls++;
  }

  /// Sends one replay sample into both sensor streams.
  void emit(_CsvSensorSample sample) {
    _accelController.add(
      UserAccelerometerEvent(sample.userAx, sample.userAy, sample.userAz),
    );
    _gyroController.add(
      GyroscopeEvent(sample.gyroX, sample.gyroY, sample.gyroZ),
    );
  }

  /// Closes the fake streams after a test finishes.
  Future<void> dispose() async {
    await _accelController.close();
    await _gyroController.close();
  }
}

/// Spy version of `ClipProvider` that records trigger calls without touching
/// the file system or video pipeline.
class _ClipProviderSpy extends ClipProvider {
  /// Creates the spy around a recording provider.
  _ClipProviderSpy(super.recordingProvider);

  /// Number of times the provider tried to save a live clip.
  int saveCalls = 0;

  /// Number of times the provider tried to show clip progress.
  int progressCalls = 0;

  /// The last save request that the sensor system issued.
  ({int clipDurationSeconds, int secondsPre, String triggerType})?
      lastSaveArguments;

  /// Records live-save requests instead of running the real clip pipeline.
  @override
  Future<void> saveClipFromLive({
    required int clipDurationSeconds,
    required int secondsPre,
    String triggerType = 'manual',
  }) async {
    saveCalls++;
    lastSaveArguments = (
      clipDurationSeconds: clipDurationSeconds,
      secondsPre: secondsPre,
      triggerType: triggerType,
    );
  }

  /// Records when the provider would have shown progress for a delayed save.
  @override
  void startClipProgress(int postDurationSeconds) {
    progressCalls++;
  }
}

/// Loads sensor replay samples from a CSV fixture on disk.
Future<List<_CsvSensorSample>> _loadSamplesFromCsv(String relativePath) async {
  final file = File(relativePath);
  final lines = await file.readAsLines();
  return lines
      .skip(1)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('#'))
      .map(_CsvSensorSample.fromCsvLine)
      .toList(growable: false);
}

/// Replays a CSV fixture by advancing the fake clock and emitting each row into
/// the fake sensor streams.
Future<void> _replaySamplesFromCsv(
  String relativePath,
  _FakeSensorSource source,
  void Function(int timestampMs) setCurrentTimeMs,
) async {
  final samples = await _loadSamplesFromCsv(relativePath);
  for (final sample in samples) {
    setCurrentTimeMs(sample.timestampMs);
    source.emit(sample);
  }
}

/// Entry point for the CSV replay tests that validate the crash detector.
void main() {
  group('SensorProvider CSV fixtures', () {
    late RecordingProvider recordingProvider;
    late SettingsProvider settingsProvider;
    late _FakeSensorSource sensorSource;
    late _ClipProviderSpy clipSpy;
    late SensorProvider sensorProvider;
    late int currentTimeMs;
    final baseTime = DateTime.utc(2026, 5, 14, 12, 0, 0);

    /// Returns the current simulated time for the provider under test.
    DateTime now() => baseTime.add(Duration(milliseconds: currentTimeMs));

    setUp(() {
      recordingProvider = RecordingProvider();
      recordingProvider.isRecording = true;
      settingsProvider = SettingsProvider()
        ..preDurationLength = '5s'
        ..postDurationLength = '0s';
      sensorSource = _FakeSensorSource();
      clipSpy = _ClipProviderSpy(recordingProvider);
      currentTimeMs = 0;
      sensorProvider = SensorProvider(
        recordingProvider,
        clipSpy,
        settingsProvider,
        sensorSource: sensorSource,
        now: now,
      );
    });

    tearDown(() async {
      sensorProvider.dispose();
      await sensorSource.dispose();
    });

    // Categorized fixtures: keep crash and quiet recordings in separate
    // directories. This makes expectations explicit and avoids relying on
    // filename conventions.
    final crashDir = Directory('test/fixtures/crash');
    final quietDir = Directory('test/fixtures/quiet');

    // Helper to collect CSV files from a directory.
    List<File> _collectCsv(Directory d) {
      return d.existsSync()
          ? d
              .listSync()
              .whereType<File>()
              .where((f) => f.path.toLowerCase().endsWith('.csv'))
              .toList()
          : <File>[];
    }

    final crashFiles = _collectCsv(crashDir);
    final quietFiles = _collectCsv(quietDir);

    for (final file in crashFiles) {
      final filename = file.path.split(Platform.pathSeparator).last;
      test('replay crash fixture $filename -> expect trigger', () async {
        await _replaySamplesFromCsv(
          file.path,
          sensorSource,
          (timestampMs) => currentTimeMs = timestampMs,
        );

        expect(sensorSource.startCalls, 1);
        // Expect exactly one save for each crash fixture. The test dataset is
        // organized so each crash CSV should contain one crash event.
        expect(clipSpy.saveCalls, equals(1), reason: 'Expected exactly one save for $filename');
        expect(clipSpy.lastSaveArguments, isNotNull);
        expect(clipSpy.lastSaveArguments?.triggerType, 'sensor');
      });
    }

    for (final file in quietFiles) {
      final filename = file.path.split(Platform.pathSeparator).last;
      test('replay quiet fixture $filename -> expect no trigger', () async {
        await _replaySamplesFromCsv(
          file.path,
          sensorSource,
          (timestampMs) => currentTimeMs = timestampMs,
        );

        expect(sensorSource.startCalls, 1);
        expect(clipSpy.saveCalls, 0, reason: 'Expected no saves for $filename');
        expect(clipSpy.lastSaveArguments, isNull);
      });
    }
  });
}


