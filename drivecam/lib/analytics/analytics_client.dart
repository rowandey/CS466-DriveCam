// Thin Amplitude adapter that keeps the rest of the app isolated from the SDK.
// The app can swap this out for a no-op implementation on unsupported builds
// or when the user has not given explicit consent.
import 'package:amplitude_flutter/amplitude.dart';
import 'package:amplitude_flutter/configuration.dart';
import 'package:amplitude_flutter/constants.dart';
import 'package:amplitude_flutter/events/base_event.dart';
import 'package:amplitude_flutter/events/identify.dart';
import 'package:amplitude_flutter/tracking_options.dart';
import 'package:flutter/foundation.dart';

abstract class AnalyticsClient {
  bool get isConfigured;

  Future<void> initialize();

  Future<void> setOptOut(bool enabled);

  Future<void> track(
    String eventType, {
    Map<String, dynamic>? eventProperties,
  });

  Future<void> setUserProperties(Map<String, dynamic> properties);

  Future<void> flush();
}

class NoopAnalyticsClient implements AnalyticsClient {
  const NoopAnalyticsClient();

  @override
  bool get isConfigured => false;

  @override
  Future<void> flush() async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<void> setOptOut(bool enabled) async {}

  @override
  Future<void> setUserProperties(Map<String, dynamic> properties) async {}

  @override
  Future<void> track(
    String eventType, {
    Map<String, dynamic>? eventProperties,
  }) async {}
}

class AmplitudeAnalyticsClient implements AnalyticsClient {
  AmplitudeAnalyticsClient(this.apiKey);

  final String apiKey;
  Amplitude? _amplitude;
  bool _initialized = false;

  @override
  bool get isConfigured => apiKey.trim().isNotEmpty;

  @override
  Future<void> initialize() async {
    if (_initialized || !isConfigured) return;

    final config = Configuration(
      apiKey: apiKey,
      serverZone: ServerZone.us,
      flushQueueSize: 30,
      flushIntervalMillis: 15000,
      minTimeBetweenSessionsMillis: 300000,
      enableCoppaControl: true,
      trackingOptions: TrackingOptions(
        ipAddress: false,
        city: false,
        region: false,
        dma: false,
        country: false,
        carrier: false,
        deviceModel: false,
        deviceManufacturer: false,
        deviceBrand: false,
        latLag: false,
        adid: false,
        appSetId: false,
        apiLevel: false,
        idfv: false,
      ),
      logLevel: kDebugMode ? LogLevel.debug : LogLevel.warn,
    );

    _amplitude = Amplitude(config);
    _initialized = true;
  }

  @override
  Future<void> flush() async {
    if (!_initialized) return;
    await _amplitude!.flush();
  }

  @override
  Future<void> setOptOut(bool enabled) async {
    if (!_initialized) return;
    await _amplitude!.setOptOut(enabled);
  }

  @override
  Future<void> setUserProperties(Map<String, dynamic> properties) async {
    if (!_initialized) return;
    final identify = Identify();
    for (final entry in properties.entries) {
      identify.set(entry.key, entry.value);
    }
    await _amplitude!.identify(identify);
  }

  @override
  Future<void> track(
    String eventType, {
    Map<String, dynamic>? eventProperties,
  }) async {
    if (!_initialized) return;
    await _amplitude!.track(
      BaseEvent(eventType, eventProperties: eventProperties),
    );
  }
}
