// sensor_service.dart
// Provides a lightweight abstraction over sensors_plus streams. This service
// centralizes subscriptions to the device's user-accelerometer and
// gyroscope streams and exposes broadcast streams that are throttled to a
// configurable rate. Keeping this plumbing isolated makes it easier to test
// and to move processing into an isolate later if needed.

import 'dart:async';

import 'package:sensors_plus/sensors_plus.dart';

/// Contract for objects that expose the sensor streams used by the crash
/// detection system.
///
/// This indirection makes the detection logic easy to test with fake streams
/// built from CSV fixtures while keeping the production implementation backed
/// by `sensors_plus`.
abstract class SensorEventSource {
  /// Stream of gravity-removed accelerometer readings.
  Stream<UserAccelerometerEvent> get userAccelerometerStream;

  /// Stream of gyroscope readings.
  Stream<GyroscopeEvent> get gyroscopeStream;

  /// Starts forwarding platform sensor data into the exposed streams.
  void start();

  /// Stops forwarding platform sensor data into the exposed streams.
  void stop();
}

/// Singleton service that exposes broadcast streams for user accelerometer and
/// gyroscope events. The streams are throttled to reduce CPU usage by default.
class SensorService implements SensorEventSource {
  SensorService._internal();
  static final SensorService _instance = SensorService._internal();
  factory SensorService() => _instance;

  // Internal controllers for broadcasting events to multiple listeners.
  final StreamController<UserAccelerometerEvent> _accelController =
      StreamController<UserAccelerometerEvent>.broadcast();
  final StreamController<GyroscopeEvent> _gyroController =
      StreamController<GyroscopeEvent>.broadcast();

  Stream<UserAccelerometerEvent> get userAccelerometerStream =>
      _accelController.stream;
  Stream<GyroscopeEvent> get gyroscopeStream => _gyroController.stream;

  StreamSubscription<UserAccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  // Throttle interval in milliseconds. Default ~50Hz -> 20ms.
  int throttleMs = 20;

  /// Starts listening to the platform sensor streams and forwards events to
  /// the broadcast streams. If already started this is a no-op.
  void start() {
    if (_accelSub != null || _gyroSub != null) return;

    int lastAccel = 0;
    int lastGyro = 0;

    _accelSub = userAccelerometerEvents.listen((event) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - lastAccel >= throttleMs) {
        lastAccel = now;
        _accelController.add(event);
      }
    });

    _gyroSub = gyroscopeEvents.listen((event) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - lastGyro >= throttleMs) {
        lastGyro = now;
        _gyroController.add(event);
      }
    });
  }

  /// Stops listening to the platform streams and closes current subscriptions.
  /// Does not close the broadcast controllers so consumers can re-subscribe.
  void stop() {
    _accelSub?.cancel();
    _accelSub = null;
    _gyroSub?.cancel();
    _gyroSub = null;
  }

  /// Dispose the service and close controllers. After calling dispose the
  /// service instance should not be used again.
  void dispose() {
    stop();
    _accelController.close();
    _gyroController.close();
  }
}

