// Build-time analytics configuration values.
// The Amplitude API key is injected at compile time so the app can ship with
// analytics disabled until a real project key is supplied.
const String amplitudeApiKey = String.fromEnvironment(
  'AMPLITUDE_API_KEY',
  defaultValue: 'cf835d24d443ba8e0960b6dc9e428d42',
);
