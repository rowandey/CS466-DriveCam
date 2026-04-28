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

  /// Map a quality label to a (width, height) pixel size for the native
  /// Camera2 recorder. Values are standard resolutions that virtually all
  /// Android cameras support; HlsRecorderHandler snaps to the closest
  /// actually-supported size if the exact value is unavailable.
  static ({int width, int height}) qualityToSize(String quality) {
    switch (quality) {
      case '480p':  return (width: 640,  height: 480);
      case '720p':  return (width: 1280, height: 720);
      case '1080p': return (width: 1920, height: 1080);
      case '4K':    return (width: 3840, height: 2160);
      default:      return (width: 1280, height: 720);
    }
  }

  /// Kept for backward compatibility with existing unit tests.
  /// New code should use [qualityToSize] instead.
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
