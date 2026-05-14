import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  // All Options
  static const List<String> framerateOptions = ['15 fps', '30 fps', '60 fps'];
  static const List<String> qualityOptions = ['480p', '720p', '1080p', '4K'];
  static const List<String> footageLimitOptions = ['30min', '1h', '1.5h', '2h', '3h', '4h', '5h', '6h'];
  static const List<String> storageLimitOptions = ['1GB', '2GB', '4GB', '8GB', '12GB', '16GB', '32GB', '64GB'];
  static const List<String> clipDurationOptions = ['0s', '5s', '30s', '1m', '2m', '3m', '5m'];
  static const List<String> clipStorageLimitOptions = ['1GB', '2GB', '4GB', '6GB', '8GB'];

  // Mappings
  static ResolutionPreset qualityToPreset(String quality) {
    switch (quality) {
      case '480p': return ResolutionPreset.medium;
      case '720p': return ResolutionPreset.high;
      case '1080p': return ResolutionPreset.veryHigh;
      case '4K': return ResolutionPreset.ultraHigh;
      default: return ResolutionPreset.high;
    }
  }

  static int framerateToFps(String framerate) {
    switch (framerate) {
      case '15 fps': return 15;
      case '30 fps': return 30;
      case '60 fps': return 60;
      default: return 30;
    }
  }

  /// Maps a quality + framerate pair to a target video bitrate in bits per second.
  /// Values are calibrated for dashcam H.264 encoding: high enough for readable
  /// license plates and road detail, low enough to keep storage predictable.
  /// Using fixed bitrates (rather than letting the encoder decide) is what makes
  /// accurate storage-consumption estimates possible — if the encoder picks its
  /// own bitrate you can't know in advance how large a file will be.
  ///
  /// Rough storage math: bitrate (bps) × seconds ÷ 8 = bytes.
  /// Example: 10 Mbps × 3600 s ÷ 8 = 4.5 GB per hour at 1080p/30fps.
  static int videoBitrateForSettings(String quality, String framerate) {
    final fps = framerateToFps(framerate);
    switch (quality) {
      case '480p':
        if (fps <= 15) return 1000000;   // 1 Mbps
        if (fps <= 30) return 2000000;   // 2 Mbps
        return 3500000;                  // 3.5 Mbps @ 60fps
      case '720p':
        if (fps <= 15) return 3000000;   // 3 Mbps
        if (fps <= 30) return 5000000;   // 5 Mbps
        return 8000000;                  // 8 Mbps @ 60fps
      case '1080p':
        if (fps <= 15) return 6000000;   // 6 Mbps
        if (fps <= 30) return 10000000;  // 10 Mbps
        return 16000000;                 // 16 Mbps @ 60fps
      case '4K':
        if (fps <= 15) return 20000000;  // 20 Mbps
        if (fps <= 30) return 35000000;  // 35 Mbps
        return 50000000;                 // 50 Mbps @ 60fps
      default:
        return 5000000; // fallback: 720p/30fps equivalent
    }
  }

  /// Converts a footage time-limit string to seconds.
  /// Used by RecordingProvider to compare total accumulated segment duration
  /// against the user's chosen limit and evict the oldest segment when exceeded.
  static int footageLimitToSeconds(String value) {
    switch (value) {
      case '30min': return 1800;
      case '1h':    return 3600;
      case '1.5h':  return 5400;
      case '2h':    return 7200;
      case '3h':    return 10800;
      case '4h':    return 14400;
      case '5h':    return 18000;
      case '6h':    return 21600;
      default:      return 7200;
    }
  }

  /// Converts a footage storage-limit string to bytes.
  /// Used alongside footageLimitToSeconds — whichever limit (time or storage)
  /// is hit first determines when the oldest segment is dropped.
  static int storageLimitToBytes(String value) {
    // 1 GB = 1024^3 bytes (binary gigabytes, matching platform storage reporting)
    const gb = 1024 * 1024 * 1024;
    switch (value) {
      case '1GB':  return 1 * gb;
      case '2GB':  return 2 * gb;
      case '4GB':  return 4 * gb;
      case '8GB':  return 8 * gb;
      case '12GB': return 12 * gb;
      case '16GB': return 16 * gb;
      case '32GB': return 32 * gb;
      case '64GB': return 64 * gb;
      default:     return 4 * gb;
    }
  }

  static int clipDurationToSeconds(String value) {
    switch (value) {
      case '0s': return 0;
      case '5s':  return 5;
      case '30s': return 30;
      case '1m':  return 60;
      case '2m':  return 120;
      case '3m':  return 180;
      case '5m':  return 300;
      default:    return 120;
    }
  }

  // Recording default settings
  String framerate = framerateOptions[1];
  String quality = qualityOptions[1];
  String footageLimit = footageLimitOptions[3];
  String storageLimit = storageLimitOptions[2];
  // Audio is enabled by default — disable to record video-only (silent) footage.
  bool audioEnabled = true;

  // Clip default settings
  String preDurationLength = clipDurationOptions[2];
  String postDurationLength = clipDurationOptions[2];
  String clipStorageLimit = clipStorageLimitOptions[1];

  // Onboarding
  bool onboardingComplete = false;

  Future<void> loadPrefs() async {
    final prefs = SharedPreferencesAsync();
    framerate = await prefs.getString('framerate') ?? framerateOptions[1];
    quality = await prefs.getString('quality') ?? qualityOptions[1];
    footageLimit = await prefs.getString('footageLimit') ?? footageLimitOptions[3];
    storageLimit = await prefs.getString('storageLimit') ?? storageLimitOptions[2];
    preDurationLength = await prefs.getString('preDurationLength') ?? clipDurationOptions[2];
    postDurationLength = await prefs.getString('postDurationLength') ?? clipDurationOptions[2];
    clipStorageLimit = await prefs.getString('clipStorageLimit') ?? clipStorageLimitOptions[1];
    // Default to true so new installs record with audio out of the box.
    audioEnabled = await prefs.getBool('audioEnabled') ?? true;
    onboardingComplete = await prefs.getBool('onboardingComplete') ?? false;
    notifyListeners();
  }

  Future<void> completeOnboarding() async {
    onboardingComplete = true;
    notifyListeners();
    await SharedPreferencesAsync().setBool('onboardingComplete', true);
  }

  // Setters
  // Set shared preferences after getting notification out to prevent delays
  void setFramerate(String value) async {
    framerate = value;
    notifyListeners();
    await SharedPreferencesAsync().setString('framerate', value);
  }

  void setQuality(String value) async {
    quality = value;
    notifyListeners();
    await SharedPreferencesAsync().setString('quality', value);
  }

  void setFootageLimit(String value) async {
    footageLimit = value;
    notifyListeners();
    await SharedPreferencesAsync().setString('footageLimit', value);
  }

  void setStorageLimit(String value) async {
    storageLimit = value;
    notifyListeners();
    await SharedPreferencesAsync().setString('storageLimit', value);
  }

  void setPreDurationLength(String value) async {
    preDurationLength = value;
    notifyListeners();
    await SharedPreferencesAsync().setString('preDurationLength', value);
  }

  void setPostDurationLength(String value) async {
    postDurationLength = value;
    notifyListeners();
    await SharedPreferencesAsync().setString('postDurationLength', value);
  }

  void setClipStorageLimit(String value) async {
    clipStorageLimit = value;
    notifyListeners();
    await SharedPreferencesAsync().setString('clipStorageLimit', value);
  }

  // Audio toggle
  void setAudioEnabled(bool value) async {
    audioEnabled = value;
    notifyListeners();
    await SharedPreferencesAsync().setBool('audioEnabled', value);
  }
}
