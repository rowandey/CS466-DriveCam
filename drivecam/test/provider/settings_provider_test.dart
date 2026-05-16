// SettingsProvider tests.

import 'package:camera/camera.dart';
import 'package:drivecam/provider/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  // Set up the memory for tests
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  // qualityToPreset
  group('SettingsProvider.qualityToPreset', () {
    test('maps 480p to ResolutionPreset.medium', () {
      expect(
        SettingsProvider.qualityToPreset('480p'),
        ResolutionPreset.medium,
      );
    });

    test('maps 720p to ResolutionPreset.high', () {
      expect(
        SettingsProvider.qualityToPreset('720p'),
        ResolutionPreset.high,
      );
    });

    test('maps 1080p to ResolutionPreset.veryHigh', () {
      expect(
        SettingsProvider.qualityToPreset('1080p'),
        ResolutionPreset.veryHigh,
      );
    });

    test('maps 4K to ResolutionPreset.ultraHigh', () {
      expect(
        SettingsProvider.qualityToPreset('4K'),
        ResolutionPreset.ultraHigh,
      );
    });

    test('unknown value falls back to ResolutionPreset.high', () {
      expect(
        SettingsProvider.qualityToPreset('unknown'),
        ResolutionPreset.high,
      );
    });
  });

  // framerateToFps
  group('SettingsProvider.framerateToFps', () {
    test('maps "15 fps" to 15', () {
      expect(SettingsProvider.framerateToFps('15 fps'), 15);
    });

    test('maps "30 fps" to 30', () {
      expect(SettingsProvider.framerateToFps('30 fps'), 30);
    });

    test('maps "60 fps" to 60', () {
      expect(SettingsProvider.framerateToFps('60 fps'), 60);
    });

    test('unknown value falls back to 30', () {
      expect(SettingsProvider.framerateToFps('unknown'), 30);
    });
  });

  // clipDurationToSeconds
  group('SettingsProvider.clipDurationToSeconds', () {
    test('maps "0s" to 0', () {
      expect(SettingsProvider.clipDurationToSeconds('0s'), 0);
    });

    test('maps "5s" to 5', () {
      expect(SettingsProvider.clipDurationToSeconds('5s'), 5);
    });

    test('maps "30s" to 30', () {
      expect(SettingsProvider.clipDurationToSeconds('30s'), 30);
    });

    test('maps "1m" to 60', () {
      expect(SettingsProvider.clipDurationToSeconds('1m'), 60);
    });

    test('maps "2m" to 120', () {
      expect(SettingsProvider.clipDurationToSeconds('2m'), 120);
    });

    test('maps "3m" to 180', () {
      expect(SettingsProvider.clipDurationToSeconds('3m'), 180);
    });

    test('maps "5m" to 300', () {
      expect(SettingsProvider.clipDurationToSeconds('5m'), 300);
    });

    test('unknown value falls back to 120', () {
      expect(SettingsProvider.clipDurationToSeconds('unknown'), 120);
    });
  });

  // Default constructor state
  group('SettingsProvider default state', () {
    late SettingsProvider settings;

    setUp(() => settings = SettingsProvider());

    test('default framerate is 30 fps', () {
      expect(settings.framerate, SettingsProvider.framerateOptions[1]);
    });

    test('default quality is 720p', () {
      expect(settings.quality, SettingsProvider.qualityOptions[1]);
    });

    test('audio is enabled by default', () {
      expect(settings.audioEnabled, isTrue);
    });

    test('onboarding is not complete by default', () {
      expect(settings.onboardingComplete, isFalse);
    });

    test('analytics is disabled by default', () {
      expect(settings.analyticsEnabled, isFalse);
    });

    test('default pre-duration is 30s', () {
      expect(settings.preDurationLength, SettingsProvider.clipDurationOptions[2]);
    });

    test('default post-duration is 30s', () {
      expect(settings.postDurationLength, SettingsProvider.clipDurationOptions[2]);
    });
  });

  // Setter state changes and listener notifications
  // Verify that the state changed and that listeners were notified
  group('SettingsProvider setters', () {
    late SettingsProvider settings;
    late int notifyCount;

    setUp(() {
      settings = SettingsProvider();
      notifyCount = 0;
      settings.addListener(() => notifyCount++);
    });

    test('setFramerate updates framerate and notifies', () {
      settings.setFramerate('60 fps');
      expect(settings.framerate, '60 fps');
      expect(notifyCount, 1);
    });

    test('setQuality updates quality and notifies', () {
      settings.setQuality('1080p');
      expect(settings.quality, '1080p');
      expect(notifyCount, 1);
    });

    test('setAudioEnabled to false updates state and notifies', () {
      settings.setAudioEnabled(false);
      expect(settings.audioEnabled, isFalse);
      expect(notifyCount, 1);
    });

    test('setAudioEnabled toggle round-trip notifies twice', () {
      settings.setAudioEnabled(false);
      settings.setAudioEnabled(true);
      expect(settings.audioEnabled, isTrue);
      expect(notifyCount, 2);
    });

    test('setAnalyticsEnabled updates state and notifies', () {
      settings.setAnalyticsEnabled(true);
      expect(settings.analyticsEnabled, isTrue);
      expect(notifyCount, 1);
    });

    test('setPreDurationLength updates state and notifies', () {
      settings.setPreDurationLength('1m');
      expect(settings.preDurationLength, '1m');
      expect(notifyCount, 1);
    });

    test('setPostDurationLength updates state and notifies', () {
      settings.setPostDurationLength('5m');
      expect(settings.postDurationLength, '5m');
      expect(notifyCount, 1);
    });

    test('setFootageLimit updates state and notifies', () {
      settings.setFootageLimit('1h');
      expect(settings.footageLimit, '1h');
      expect(notifyCount, 1);
    });

    test('setStorageLimit updates state and notifies', () {
      settings.setStorageLimit('8GB');
      expect(settings.storageLimit, '8GB');
      expect(notifyCount, 1);
    });

    test('setClipStorageLimit updates state and notifies', () {
      settings.setClipStorageLimit('4GB');
      expect(settings.clipStorageLimit, '4GB');
      expect(notifyCount, 1);
    });
  });

  // loadPrefs — default fallback behaviour
  group('SettingsProvider.loadPrefs defaults', () {
    test('loadPrefs applies coded defaults when no prefs are stored', () async {
      final settings = SettingsProvider();
      await settings.loadPrefs();

      expect(settings.framerate, SettingsProvider.framerateOptions[1]);
      expect(settings.quality, SettingsProvider.qualityOptions[1]);
      expect(settings.audioEnabled, isTrue);
      expect(settings.onboardingComplete, isFalse);
      expect(settings.analyticsEnabled, isFalse);
    });

    test('loadPrefs notifies listeners', () async {
      final settings = SettingsProvider();
      int notifyCount = 0;
      settings.addListener(() => notifyCount++);

      await settings.loadPrefs();

      expect(notifyCount, 1);
    });
  });

  // loadPrefs — restoring persisted values
  group('SettingsProvider.loadPrefs restores persisted values', () {
    test('loadPrefs reads framerate from store', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({
        'framerate': '15 fps',
      });

      final settings = SettingsProvider();
      await settings.loadPrefs();

      expect(settings.framerate, '15 fps');
    });

    test('loadPrefs reads quality from store', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({
        'quality': '4K',
      });

      final settings = SettingsProvider();
      await settings.loadPrefs();

      expect(settings.quality, '4K');
    });

    test('loadPrefs reads audioEnabled false from store', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({
        'audioEnabled': false,
      });

      final settings = SettingsProvider();
      await settings.loadPrefs();

      expect(settings.audioEnabled, isFalse);
    });

    test('loadPrefs reads onboardingComplete true from store', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({
        'onboardingComplete': true,
      });

      final settings = SettingsProvider();
      await settings.loadPrefs();

      expect(settings.onboardingComplete, isTrue);
    });

    test('loadPrefs reads analyticsEnabled true from store', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({
        'analyticsEnabled': true,
      });

      final settings = SettingsProvider();
      await settings.loadPrefs();

      expect(settings.analyticsEnabled, isTrue);
    });
  });

  // completeOnboarding
  group('SettingsProvider.completeOnboarding', () {
    test('sets onboardingComplete to true', () async {
      final settings = SettingsProvider();
      expect(settings.onboardingComplete, isFalse);

      await settings.completeOnboarding();

      expect(settings.onboardingComplete, isTrue);
    });

    test('notifies listeners', () async {
      final settings = SettingsProvider();
      int notifyCount = 0;
      settings.addListener(() => notifyCount++);

      await settings.completeOnboarding();

      expect(notifyCount, 1);
    });

    test('persists to store so a reloaded provider sees it', () async {
      final settings = SettingsProvider();
      await settings.completeOnboarding();

      final reloaded = SettingsProvider();
      await reloaded.loadPrefs();

      expect(reloaded.onboardingComplete, isTrue);
    });
  });

  group('SettingsProvider analytics persistence', () {
    test('persists analytics opt-in so a reloaded provider sees it', () async {
      final settings = SettingsProvider();
      settings.setAnalyticsEnabled(true);
      await Future<void>.delayed(Duration.zero);

      final reloaded = SettingsProvider();
      await reloaded.loadPrefs();

      expect(reloaded.analyticsEnabled, isTrue);
    });
  });
}
