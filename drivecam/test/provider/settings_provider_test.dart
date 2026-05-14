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

  // videoBitrateForSettings
  // These tests verify the bitrate lookup table used for storage estimation.
  // The exact values matter: bytes = bitrate × seconds ÷ 8 is used by
  // RecordingProvider to predict how much storage each segment will consume.
  group('SettingsProvider.videoBitrateForSettings', () {
    test('480p at 15fps returns 1 Mbps', () {
      expect(SettingsProvider.videoBitrateForSettings('480p', '15 fps'), 1000000);
    });

    test('480p at 30fps returns 2 Mbps', () {
      expect(SettingsProvider.videoBitrateForSettings('480p', '30 fps'), 2000000);
    });

    test('480p at 60fps returns 3.5 Mbps', () {
      expect(SettingsProvider.videoBitrateForSettings('480p', '60 fps'), 3500000);
    });

    test('720p at 15fps returns 3 Mbps', () {
      expect(SettingsProvider.videoBitrateForSettings('720p', '15 fps'), 3000000);
    });

    test('720p at 30fps returns 5 Mbps', () {
      expect(SettingsProvider.videoBitrateForSettings('720p', '30 fps'), 5000000);
    });

    test('720p at 60fps returns 8 Mbps', () {
      expect(SettingsProvider.videoBitrateForSettings('720p', '60 fps'), 8000000);
    });

    test('1080p at 15fps returns 6 Mbps', () {
      expect(SettingsProvider.videoBitrateForSettings('1080p', '15 fps'), 6000000);
    });

    test('1080p at 30fps returns 10 Mbps', () {
      expect(SettingsProvider.videoBitrateForSettings('1080p', '30 fps'), 10000000);
    });

    test('1080p at 60fps returns 16 Mbps', () {
      expect(SettingsProvider.videoBitrateForSettings('1080p', '60 fps'), 16000000);
    });

    test('4K at 15fps returns 20 Mbps', () {
      expect(SettingsProvider.videoBitrateForSettings('4K', '15 fps'), 20000000);
    });

    test('4K at 30fps returns 35 Mbps', () {
      expect(SettingsProvider.videoBitrateForSettings('4K', '30 fps'), 35000000);
    });

    test('4K at 60fps returns 50 Mbps', () {
      expect(SettingsProvider.videoBitrateForSettings('4K', '60 fps'), 50000000);
    });

    test('unknown quality falls back to 5 Mbps', () {
      expect(SettingsProvider.videoBitrateForSettings('unknown', '30 fps'), 5000000);
    });

    // Sanity-check the storage math inline: bytes = bitrate × seconds ÷ 8.
    // 1080p/30fps = 10 Mbps → 1 hour = 3600s → 10,000,000 × 3600 ÷ 8 = 4.5 GB.
    test('1080p/30fps × 1 hour ÷ 8 equals 4.5 GB', () {
      final bitrate = SettingsProvider.videoBitrateForSettings('1080p', '30 fps');
      final bytes = bitrate * 3600 ~/ 8;
      expect(bytes, 4500000000);
    });
  });

  // footageLimitToSeconds
  // These values are read by RecordingProvider._evictOldestIfNeeded to enforce
  // the rolling-buffer time limit. Every option must map to the correct seconds
  // or eviction will fire at the wrong time.
  group('SettingsProvider.footageLimitToSeconds', () {
    test('maps "30min" to 1800 seconds', () {
      expect(SettingsProvider.footageLimitToSeconds('30min'), 1800);
    });

    test('maps "1h" to 3600 seconds', () {
      expect(SettingsProvider.footageLimitToSeconds('1h'), 3600);
    });

    test('maps "1.5h" to 5400 seconds', () {
      expect(SettingsProvider.footageLimitToSeconds('1.5h'), 5400);
    });

    test('maps "2h" to 7200 seconds', () {
      expect(SettingsProvider.footageLimitToSeconds('2h'), 7200);
    });

    test('maps "3h" to 10800 seconds', () {
      expect(SettingsProvider.footageLimitToSeconds('3h'), 10800);
    });

    test('maps "4h" to 14400 seconds', () {
      expect(SettingsProvider.footageLimitToSeconds('4h'), 14400);
    });

    test('maps "5h" to 18000 seconds', () {
      expect(SettingsProvider.footageLimitToSeconds('5h'), 18000);
    });

    test('maps "6h" to 21600 seconds', () {
      expect(SettingsProvider.footageLimitToSeconds('6h'), 21600);
    });

    test('unknown value falls back to 7200 seconds (2h)', () {
      expect(SettingsProvider.footageLimitToSeconds('unknown'), 7200);
    });
  });

  // storageLimitToBytes
  // Uses binary gigabytes (1 GB = 1024^3 bytes) to match how platforms report
  // storage. These values feed RecordingProvider._evictOldestIfNeeded alongside
  // footageLimitToSeconds — whichever limit is hit first drives eviction.
  group('SettingsProvider.storageLimitToBytes', () {
    const gb = 1024 * 1024 * 1024;

    test('maps "1GB" to 1 × 1024^3 bytes', () {
      expect(SettingsProvider.storageLimitToBytes('1GB'), 1 * gb);
    });

    test('maps "2GB" to 2 × 1024^3 bytes', () {
      expect(SettingsProvider.storageLimitToBytes('2GB'), 2 * gb);
    });

    test('maps "4GB" to 4 × 1024^3 bytes', () {
      expect(SettingsProvider.storageLimitToBytes('4GB'), 4 * gb);
    });

    test('maps "8GB" to 8 × 1024^3 bytes', () {
      expect(SettingsProvider.storageLimitToBytes('8GB'), 8 * gb);
    });

    test('maps "12GB" to 12 × 1024^3 bytes', () {
      expect(SettingsProvider.storageLimitToBytes('12GB'), 12 * gb);
    });

    test('maps "16GB" to 16 × 1024^3 bytes', () {
      expect(SettingsProvider.storageLimitToBytes('16GB'), 16 * gb);
    });

    test('maps "32GB" to 32 × 1024^3 bytes', () {
      expect(SettingsProvider.storageLimitToBytes('32GB'), 32 * gb);
    });

    test('maps "64GB" to 64 × 1024^3 bytes', () {
      expect(SettingsProvider.storageLimitToBytes('64GB'), 64 * gb);
    });

    test('unknown value falls back to 4 × 1024^3 bytes (4GB)', () {
      expect(SettingsProvider.storageLimitToBytes('unknown'), 4 * gb);
    });
  });

  // clipStorageLimitToBytes
  // Uses binary gigabytes (1 GB = 1024^3 bytes) to match platform storage
  // reporting. These values drive _enforceClipStorageLimit in ClipProvider —
  // a wrong mapping would allow clips to consume more or less space than the
  // user configured.
  group('SettingsProvider.clipStorageLimitToBytes', () {
    const gb = 1024 * 1024 * 1024;

    test('maps "1GB" to 1 × 1024^3 bytes', () {
      expect(SettingsProvider.clipStorageLimitToBytes('1GB'), 1 * gb);
    });

    test('maps "2GB" to 2 × 1024^3 bytes', () {
      expect(SettingsProvider.clipStorageLimitToBytes('2GB'), 2 * gb);
    });

    test('maps "4GB" to 4 × 1024^3 bytes', () {
      expect(SettingsProvider.clipStorageLimitToBytes('4GB'), 4 * gb);
    });

    test('maps "6GB" to 6 × 1024^3 bytes', () {
      expect(SettingsProvider.clipStorageLimitToBytes('6GB'), 6 * gb);
    });

    test('maps "8GB" to 8 × 1024^3 bytes', () {
      expect(SettingsProvider.clipStorageLimitToBytes('8GB'), 8 * gb);
    });

    test('unknown value falls back to 2 × 1024^3 bytes (2GB default)', () {
      expect(SettingsProvider.clipStorageLimitToBytes('unknown'), 2 * gb);
    });

    // Verify binary vs decimal distinction: 1 GB must be 1,073,741,824 bytes
    // (1024^3), not 1,000,000,000 bytes (10^9). Using the wrong base would
    // allow ~7 % more clips than the user chose before eviction fires.
    test('uses binary gigabytes, not decimal', () {
      expect(SettingsProvider.clipStorageLimitToBytes('1GB'), 1073741824);
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
}
