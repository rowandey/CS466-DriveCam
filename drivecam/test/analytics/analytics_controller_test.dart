// Tests for the analytics controller.
// These tests focus on consent handling and the anonymous event pipeline so we
// can verify the app only tracks after the user opts in.

import 'package:drivecam/analytics/analytics_client.dart';
import 'package:drivecam/analytics/analytics_controller.dart';
import 'package:drivecam/provider/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AnalyticsController consent handling', () {
    test('keeps analytics opted out until the user opts in', () async {
      final client = _FakeAnalyticsClient();
      final controller = AnalyticsController(client);
      final settings = _buildSettings();

      await controller.initialize(consentGranted: false, settings: settings);

      controller.trackSettingChanged(
        settings: settings,
        settingName: 'quality',
        value: settings.quality,
      );

      expect(client.initializeCalls, 1);
      expect(client.optOutHistory, [true]);
      expect(client.trackedEvents, isEmpty);

      controller.dispose();
    });

    test('syncs properties and tracks once consent is granted', () async {
      final client = _FakeAnalyticsClient();
      final controller = AnalyticsController(client);
      final settings = _buildSettings();
      settings.analyticsEnabled = true;

      await controller.initialize(consentGranted: false, settings: settings);
      await controller.setConsent(true, settings: settings);

      controller.trackRecordingStarted(
        quality: settings.quality,
        framerate: settings.framerate,
        audioEnabled: settings.audioEnabled,
      );

      expect(client.optOutHistory, [true, false]);
      expect(client.userProperties, isNotEmpty);
      expect(client.userProperties.last['analytics_opt_in'], isTrue);
      expect(
        client.trackedEvents.map((event) => event.$1),
        contains('analytics_opted_in'),
      );
      expect(
        client.trackedEvents.map((event) => event.$1),
        contains('recording_started'),
      );

      controller.dispose();
    });

    test('stops future tracking after opt-out', () async {
      final client = _FakeAnalyticsClient();
      final controller = AnalyticsController(client);
      final settings = _buildSettings();
      settings.analyticsEnabled = true;

      await controller.initialize(consentGranted: false, settings: settings);
      await controller.setConsent(true, settings: settings);
      await controller.setConsent(false, settings: settings);

      final trackedBefore = client.trackedEvents.length;
      controller.trackClipSaved(
        durationSeconds: 30,
        triggerType: 'manual',
        fromLiveRecording: true,
      );

      expect(client.optOutHistory, [true, false, true]);
      expect(client.trackedEvents.length, trackedBefore);

      controller.dispose();
    });
  });
}

class _FakeAnalyticsClient implements AnalyticsClient {
  int initializeCalls = 0;
  final List<bool> optOutHistory = [];
  final List<(String, Map<String, dynamic>?)> trackedEvents = [];
  final List<Map<String, dynamic>> userProperties = [];
  int flushCalls = 0;

  @override
  bool get isConfigured => true;

  @override
  Future<void> flush() async {
    flushCalls++;
  }

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  Future<void> setOptOut(bool enabled) async {
    optOutHistory.add(enabled);
  }

  @override
  Future<void> setUserProperties(Map<String, dynamic> properties) async {
    userProperties.add(Map<String, dynamic>.from(properties));
  }

  @override
  Future<void> track(
    String eventType, {
    Map<String, dynamic>? eventProperties,
  }) async {
    trackedEvents.add((eventType, eventProperties));
  }
}

// Builds a lightweight settings object for analytics tests.
SettingsProvider _buildSettings() {
  final settings = SettingsProvider();
  settings.framerate = '30 fps';
  settings.quality = '720p';
  settings.audioEnabled = true;
  settings.footageLimit = '2h';
  settings.storageLimit = '4GB';
  settings.preDurationLength = '30s';
  settings.postDurationLength = '30s';
  settings.clipStorageLimit = '2GB';
  return settings;
}