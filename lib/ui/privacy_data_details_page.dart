import 'package:dr/analytics_service.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class PrivacyDataDetailsPage extends StatelessWidget {
  const PrivacyDataDetailsPage({super.key});

  static const sections = <String, IconData>{
    'notice': Icons.policy_outlined,
    'choice': Icons.tune,
    'required': Icons.lock_outline,
    'local': Icons.storage_outlined,
    'basis': Icons.check_circle_outline,
    'crashes': Icons.bug_report_outlined,
    'automatic': Icons.devices_outlined,
    'context': Icons.info_outline,
    'logs': Icons.list_alt,
    'excluded': Icons.shield_outlined,
    'analyticsExcluded': Icons.shield_outlined,
    'analytics': Icons.analytics_outlined,
    'identity': Icons.key_outlined,
    'school': Icons.school_outlined,
    'academic': Icons.analytics_outlined,
    'analyticsAutomatic': Icons.devices_outlined,
    'age': Icons.person_outline,
    'revocation': Icons.stop_circle_outlined,
    'control': Icons.settings_outlined,
    'limits': Icons.cloud_outlined,
    'retention': Icons.history,
    'recipients': Icons.public,
    'rights': Icons.gavel_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
        title: Text(l10n.text('privacyDetails.title')),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final section in sections.entries)
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(section.value, color: theme.colorScheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Text(
                                  l10n.text(
                                      'privacyDetails.${section.key}.title'),
                                  style: theme.textTheme.titleMedium)),
                        ]),
                        const SizedBox(height: 12),
                        Text(l10n.text('privacyDetails.${section.key}.body'),
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(height: 1.5)),
                      ],
                    ),
                  ),
                ),
              ListTile(
                  leading: const Icon(Icons.email_outlined),
                  title: const Text('buccitobias774@gmail.com'),
                  subtitle: Text(l10n.text('privacyDetails.contact')),
                  onTap: () => launchUrl(
                      Uri(scheme: 'mailto', path: 'buccitobias774@gmail.com'),
                      mode: LaunchMode.externalApplication)),
              ListTile(
                  leading: const Icon(Icons.open_in_new),
                  title: Text(l10n.text('privacyDetails.firebase')),
                  onTap: () {
                    AnalyticsService.product.event('external_action',
                        {'action_type': 'open_privacy_policy'});
                    launchUrl(
                        Uri.parse(
                            'https://firebase.google.com/support/privacy'),
                        mode: LaunchMode.externalApplication);
                  }),
            ],
          ),
        ),
      ),
    );
  }
}
