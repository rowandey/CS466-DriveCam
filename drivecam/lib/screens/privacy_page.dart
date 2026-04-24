// This file defines the Privacy Page screen shown from the navigation drawer.
// It communicates data handling practices to users in a clear, scannable format.
import 'package:flutter/material.dart';

/// Displays a user-facing privacy summary for DriveCam.
///
/// The page explains what data is collected for app functionality,
/// what data is intentionally not collected, and what data is not shared.
class PrivacyPageScreen extends StatelessWidget {
  const PrivacyPageScreen({super.key});

  /// Builds the Privacy Page UI with grouped sections for transparency.
  ///
  /// Parameters:
  /// - context: Build context used for theme and widget tree access.
  ///
  /// Returns:
  /// - A Scaffold containing the privacy statements.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // A standard AppBar is used here to avoid creating a circular dependency
      // between the drawer widget and this privacy page screen.
      appBar: AppBar(title: const Text('Privacy Page')),
      body: const _PrivacyContent(),
      extendBody: true,
    );
  }
}

/// Renders the written privacy content in sectioned cards.
class _PrivacyContent extends StatelessWidget {
  const _PrivacyContent();

  /// Builds the full scrollable content for collected and non-collected data.
  ///
  /// Parameters:
  /// - context: Build context used to access the current theme.
  ///
  /// Returns:
  /// - A SingleChildScrollView with privacy sections.
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your Privacy Matters',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'DriveCam is designed to keep your driving footage on your device and provide transparency about data handling.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          _PrivacySectionCard(
            title: 'Data Collected',
            icon: Icons.check_circle,
            iconColor: colorScheme.primary,
            bulletPoints: const [
              'Locally saved video recordings and clips you create in the app.',
              'App settings you configure (for example, recording quality preferences).',
              'Temporary runtime/device state needed for camera and recording features.',
            ],
          ),
          const SizedBox(height: 12),
          _PrivacySectionCard(
            title: 'Data Not Collected',
            icon: Icons.cancel,
            iconColor: colorScheme.error,
            bulletPoints: const [
              'No account credentials (there are no user accounts).',
              'No precise location/GPS history collected by this app.',
              'No contact lists, messages, or photos outside files you explicitly manage in DriveCam.',
              'No background behavioral tracking for advertising.',
            ],
          ),
          const SizedBox(height: 12),
          _PrivacySectionCard(
            title: 'Data Not Shared',
            icon: Icons.lock,
            iconColor: colorScheme.secondary,
            bulletPoints: const [
              'Your recordings and clips are not automatically uploaded to a cloud service by DriveCam.',
              'Your data is not sold to third parties.',
              'Your data is not shared with advertisers.',
            ],
          ),
        ],
      ),
    );
  }
}

/// Reusable card used for each privacy section.
class _PrivacySectionCard extends StatelessWidget {
  const _PrivacySectionCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.bulletPoints,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final List<String> bulletPoints;

  /// Builds a styled section card with bullet point statements.
  ///
  /// Parameters:
  /// - context: Build context used for theme styling.
  ///
  /// Returns:
  /// - A Card widget containing section text.
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final point in bulletPoints)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('\u2022 '),
                    Expanded(child: Text(point)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
