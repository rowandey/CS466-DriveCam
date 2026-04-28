// Dart-side wrapper around the native Camera2 + MediaRecorder recording handler.
//
// All real work is in HlsRecorderHandler.kt (Android).
// This file keeps call-site code clean and provides typed APIs so the rest of
// the Dart codebase never needs to know channel names or argument shapes.
//
// Method overview:
//   initialize      — open the camera; returns preview dimensions + textureId
//   startRecording  — configure the camera session with a recorder surface and start
//   rotateSegment   — setNextOutputFile (zero-freeze segment switch)
//   stopRecording   — finalize the last segment; returns its elapsed duration
//   updateSettings  — update audio preference without closing the camera
//   dispose         — release all native resources

import 'package:flutter/services.dart';

class HlsRecorderChannel {
  // Must match HlsRecorderHandler.CHANNEL on the Kotlin side.
  static const MethodChannel _channel = MethodChannel('drivecam/hls_recorder');

  /// Open the back camera, start the preview, and return configuration data
  /// needed by the Dart layer to display the preview and correct orientation.
  ///
  /// Parameters:
  ///   [width]        — requested preview / recording width in pixels.
  ///   [height]       — requested preview / recording height in pixels.
  ///   [fps]          — target recording frame rate.
  ///   [audioEnabled] — whether to capture microphone audio.
  ///
  /// Returns a map with:
  ///   textureId        — Flutter Texture widget ID for the preview.
  ///   width            — actual width chosen by the camera (may differ from requested).
  ///   height           — actual height chosen by the camera.
  ///   sensorOrientation — camera sensor angle in degrees (typically 90 for back cameras).
  ///
  /// Throws [PlatformException] if the camera cannot be opened.
  static Future<Map<String, dynamic>> initialize({
    required int width,
    required int height,
    required int fps,
    required bool audioEnabled,
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'initialize',
      {
        'width': width,
        'height': height,
        'fps': fps,
        'audioEnabled': audioEnabled,
      },
    );
    return result!;
  }

  /// Configure the camera session with the MediaRecorder surface and start
  /// recording. Writes directly to [outputPath] in the HLS session directory,
  /// so no file rename is needed after recording.
  ///
  /// This call causes one brief camera session reconfiguration (adding the
  /// recorder surface), which produces a momentary preview interruption. All
  /// subsequent segment rotations via [rotateSegment] are freeze-free.
  ///
  /// Parameters:
  ///   [outputPath]     — absolute path for the first segment .mp4 file.
  ///   [deviceRotation] — current device rotation in degrees (0=portrait,
  ///                      90=landscape) used to set the correct MP4 orientation
  ///                      hint so gallery apps play the video upright.
  ///
  /// Throws [PlatformException] on error.
  static Future<void> startRecording({
    required String outputPath,
    int deviceRotation = 0,
  }) async {
    await _channel.invokeMethod<void>(
      'startRecording',
      {
        'outputPath': outputPath,
        'deviceRotation': deviceRotation,
      },
    );
  }

  /// Seamlessly rotate to [nextOutputPath] using MediaRecorder.setNextOutputFile.
  ///
  /// The encoder keeps running and the preview has zero interruption. The switch
  /// happens at the next sync frame (≤ 1 frame ≈ 33 ms at 30 fps), which is
  /// imperceptible to the user.
  ///
  /// Returns the wall-clock elapsed duration (in seconds) of the segment that
  /// just ended. This value is used for the [#EXTINF] entry in the manifest.
  ///
  /// Parameters:
  ///   [nextOutputPath] — absolute path for the next segment .mp4 file.
  ///
  /// Throws [PlatformException] if not currently recording or if API < 26.
  static Future<double> rotateSegment({required String nextOutputPath}) async {
    final result = await _channel.invokeMethod<double>(
      'rotateSegment',
      {'nextOutputPath': nextOutputPath},
    );
    return result ?? 0.0;
  }

  /// Finalize the last segment and drop back to preview-only mode.
  ///
  /// [MediaRecorder.stop()] runs on a background thread in Kotlin so the
  /// Android main thread stays responsive during MP4 finalisation. Returns
  /// once the preview session has been restored.
  ///
  /// Returns the elapsed duration (in seconds) of the final segment.
  ///
  /// Throws [PlatformException] if not currently recording.
  static Future<double> stopRecording() async {
    final result = await _channel.invokeMethod<double>('stopRecording');
    return result ?? 0.0;
  }

  /// Update recorder settings without closing the camera.
  ///
  /// Called when the user toggles the audio setting while recording is paused
  /// (between [stopRecording] and the next [startRecording]). The camera stays
  /// open so there is no additional preview interruption.
  ///
  /// Parameters:
  ///   [audioEnabled] — new audio preference.
  static Future<void> updateSettings({required bool audioEnabled}) async {
    await _channel.invokeMethod<void>(
      'updateSettings',
      {'audioEnabled': audioEnabled},
    );
  }

  /// Release all native resources (camera device, recorder, preview texture).
  ///
  /// Must be called when the camera view is disposed. Safe to call while
  /// recording — stops the recorder first. Safe to call multiple times.
  static Future<void> dispose() async {
    await _channel.invokeMethod<void>('dispose');
  }
}
