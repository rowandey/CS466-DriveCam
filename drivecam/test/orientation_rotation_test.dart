// Tests for the recording-provider rotation mapping used by the DriveCam
// camera preview and MP4 orientation hint logic.
//
// These checks make sure the app keeps treating sensor orientation as a fixed
// hardware property while still converting live phone rotation into the degrees
// expected by MediaRecorder.setOrientationHint().

import 'package:drivecam/provider/recording_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_device_orientation/native_device_orientation.dart';

// Verifies that the helper converting device orientation into clockwise degrees
// matches the Android camera/MediaRecorder convention used by the app.
void main() {
  test('maps native device orientation to clockwise rotation degrees', () {
    expect(
      RecordingProvider.deviceRotationDegreesFor(NativeDeviceOrientation.portraitUp),
      0,
    );
    expect(
      RecordingProvider.deviceRotationDegreesFor(NativeDeviceOrientation.landscapeLeft),
      90,
    );
    expect(
      RecordingProvider.deviceRotationDegreesFor(NativeDeviceOrientation.portraitDown),
      180,
    );
    expect(
      RecordingProvider.deviceRotationDegreesFor(NativeDeviceOrientation.landscapeRight),
      270,
    );
    expect(
      RecordingProvider.deviceRotationDegreesFor(NativeDeviceOrientation.unknown),
      0,
    );
  });

  // Confirms the provider stores the latest rotation update so recording start
  // and resume calls can reuse it without asking the UI again.
  test('stores the latest live device rotation', () {
    final provider = RecordingProvider();

    provider.setDeviceRotation(90);
    expect(provider.deviceRotation, 90);

    provider.setDeviceRotation(270);
    expect(provider.deviceRotation, 270);
  });
}

