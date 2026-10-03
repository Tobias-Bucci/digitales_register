import 'package:dr/i18n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutAppDialog extends StatelessWidget {
  const AboutAppDialog({super.key, required this.version});

  final String version;

  Widget _link(BuildContext context, String title, String url,
          {String? subtitle}) =>
      ListTile(
        dense: true,
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: const Icon(Icons.open_in_new, size: 18),
        onTap: () =>
            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final displayVersion = version.startsWith('v') ? version : 'v$version';
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        key: const Key('about-dialog-panel'),
        constraints: BoxConstraints(
            maxWidth: 440, maxHeight: MediaQuery.sizeOf(context).height - 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 12, 16),
              child: Row(children: [
                ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child:
                        Image.asset('assets/index.png', width: 48, height: 48)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.text('settings.about.appName'),
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(displayVersion,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant)),
                    ],
                  ),
                ),
                IconButton(
                    tooltip: l10n.text('dialog.close'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close)),
              ]),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n.text('settings.about.summary'),
                        style:
                            theme.textTheme.bodyMedium?.copyWith(height: 1.45)),
                    const SizedBox(height: 8),
                    Text(l10n.text('settings.about.independent'),
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant, height: 1.4)),
                    const SizedBox(height: 20),
                    Material(
                      color: colors.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: colors.outlineVariant)),
                      clipBehavior: Clip.antiAlias,
                      child: Column(children: [
                        _link(context, 'digitalesregister.it',
                            'https://digitalesregister.it',
                            subtitle: l10n
                                .text('settings.about.officialSourcesTitle')),
                        Divider(height: 1, color: colors.outlineVariant),
                        ExpansionTile(
                          tilePadding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          childrenPadding: const EdgeInsets.only(bottom: 12),
                          shape: const Border(),
                          collapsedShape: const Border(),
                          title: Text(l10n.text('settings.about.project')),
                          subtitle: Text('Tobias Bucci · GPLv3',
                              style: theme.textTheme.bodySmall),
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(l10n.text('settings.about.copyright'),
                                      style: theme.textTheme.bodySmall),
                                  const SizedBox(height: 12),
                                  Text(l10n.text('settings.about.disclaimer'),
                                      style: theme.textTheme.bodySmall),
                                  const SizedBox(height: 12),
                                  Text(l10n.text('settings.about.gpl'),
                                      style: theme.textTheme.bodySmall),
                                  const SizedBox(height: 8),
                                  Text(l10n.text('settings.about.warranty'),
                                      style: theme.textTheme.bodySmall),
                                ],
                              ),
                            ),
                            _link(
                                context,
                                l10n.text('settings.advanced.sourceFork'),
                                'https://github.com/Tobias-Bucci/digitales_register'),
                            _link(
                                context,
                                l10n.text('settings.advanced.sourceOriginal'),
                                'https://github.com/miDeb/digitales_register'),
                            _link(context, 'GNU GPLv3',
                                'https://www.gnu.org/licenses/gpl-3.0.html'),
                            ListTile(
                              dense: true,
                              title:
                                  Text(l10n.text('settings.advanced.licenses')),
                              trailing:
                                  const Icon(Icons.chevron_right, size: 18),
                              onTap: () => showLicensePage(
                                  context: context,
                                  applicationName:
                                      l10n.text('settings.about.appName'),
                                  applicationVersion: version),
                            ),
                          ],
                        ),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
