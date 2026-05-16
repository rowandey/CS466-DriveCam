// Coordinates opt-in analytics behavior, user property syncing, and lifecycle
// flushing while keeping the app code independent from the Amplitude SDK.
import 'dart:async';

import 'package:flutter/material.dart';

import '../provider/settings_provider.dart';
import 'analytics_client.dart';

class AnalyticsController with WidgetsBindingObserver {
  AnalyticsController(this._client);

  final AnalyticsClient _client;
  bool _consentGranted = false;
  bool _registeredObserver = false;

  bool get isConfigured => _client.isConfigured;
  bool get canTrack => _consentGranted && isConfigured;

  Future<void> initialize({
    required bool consentGranted,
    required SettingsProvider settings,
  }) async {
    if (!_registeredObserver) {
      WidgetsBinding.instance.addObserver(this);
      _registeredObserver = true;
    }
    _consentGranted = consentGranted;
    await _client.initialize();
    await _client.setOptOut(!consentGranted);
    if (canTrack) {
      await syncUserProperties(settings);
    }
  }

  Future<void> setConsent(
    bool enabled, {
    required SettingsProvider settings,
  }) async {
    _consentGranted = enabled;
    await _client.setOptOut(!enabled);
    if (!enabled) return;

    await syncUserProperties(settings);
    _track(
      'analytics_opted_in',
      eventProperties: const {'source': 'user_toggle'},
    );
  }

  Future<void> syncUserProperties(SettingsProvider settings) async {
    if (!canTrack) return;
    await _client.setUserProperties({
      'recording_quality': settings.quality,
      'recording_framerate': settings.framerate,
      'recording_audio_enabled': settings.audioEnabled,
      'rolling_footage_limit': settings.footageLimit,
      'footage_storage_limit': settings.storageLimit,
      'clip_pre_duration': settings.preDurationLength,
      'clip_post_duration': settings.postDurationLength,
      'clip_storage_limit': settings.clipStorageLimit,
      'analytics_opt_in': settings.analyticsEnabled,
    });
  }

  void trackSettingChanged({
    required SettingsProvider settings,
    required String settingName,
    required Object value,
  }) {
    _track(
      'setting_changed',
      eventProperties: {
        'setting_name': settingName,
        'setting_value': value,
      },
    );
    unawaited(syncUserProperties(settings));
  }

  void trackRecordingStarted({
    required String quality,
    required String framerate,
    required bool audioEnabled,
  }) {
    _track(
      'recording_started',
      eventProperties: {
        'quality': quality,
        'framerate': framerate,
        'audio_enabled': audioEnabled,
      },
    );
  }

  void trackRecordingStopped({required int durationSeconds}) {
    _track(
      'recording_stopped',
      eventProperties: {'duration_seconds': durationSeconds},
    );
  }

  void trackClipSaved({
    required int durationSeconds,
    required String triggerType,
    required bool fromLiveRecording,
  }) {
    _track(
      'clip_saved',
      eventProperties: {
        'duration_seconds': durationSeconds,
        'trigger_type': triggerType,
        'source': fromLiveRecording ? 'live_recording' : 'saved_recording',
      },
    );
  }

  void dispose() {
    if (_registeredObserver) {
      WidgetsBinding.instance.removeObserver(this);
      _registeredObserver = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!canTrack) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // Flush on background transitions so queued events are sent promptly
      // without blocking the UI thread during normal interaction.
      unawaited(_client.flush());
    }
  }

  void _track(
    String eventType, {
    Map<String, dynamic>? eventProperties,
  }) {
    if (!canTrack) return;
    unawaited(
      _client.track(
        eventType,
        eventProperties: eventProperties,
      ),
    );
  }
}
