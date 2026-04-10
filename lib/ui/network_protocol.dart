// Copyright (C) 2021 Michael Debertol
//
// This file is part of digitales_register.
//
// digitales_register is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// digitales_register is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with digitales_register.  If not, see <http://www.gnu.org/licenses/>.

import 'dart:convert';

import 'package:dr/app_state.dart';
import 'package:dr/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NetworkProtocol extends StatelessWidget {
  final List<NetworkProtocolItem> items;

  const NetworkProtocol({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lan_outlined,
                size: 52,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                'Noch keine Anfragen vorhanden',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Sobald die App Anfragen sendet, erscheinen sie hier mit Parametern und Antwort.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        return _Item(
          item: items[index],
          index: items.length - index,
        );
      },
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.item,
    required this.index,
  });

  final NetworkProtocolItem item;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final addressInfo = _splitAddress(item.address);
    final preview = _contentPreview(item.response) ?? _contentPreview(item.parameters);
    final hasParameters = item.parameters.trim().isNotEmpty;
    final hasResponse = item.response.trim().isNotEmpty;

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _showProtocolDetails(context, item),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$index',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          addressInfo.path,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (addressInfo.host.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            addressInfo.host,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoChip(
                    icon: Icons.tune_rounded,
                    label: hasParameters ? 'Parameter' : 'Keine Parameter',
                  ),
                  _InfoChip(
                    icon: Icons.reply_all_rounded,
                    label: hasResponse ? 'Antwort' : 'Keine Antwort',
                  ),
                  _InfoChip(
                    icon: Icons.notes_rounded,
                    label: '${_contentLength(item.parameters) + _contentLength(item.response)} Zeichen',
                  ),
                ],
              ),
              if (preview != null) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    preview,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}

class _ProtocolSection extends StatelessWidget {
  const _ProtocolSection({
    required this.title,
    required this.content,
    required this.icon,
  });

  final String title;
  final String? content;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formattedContent = _formatProtocolContent(content, title);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 8, 10),
            child: Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Kopieren',
                  icon: const Icon(Icons.content_copy_rounded),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: formattedContent));
                    showSnackBar('In die Zwischenablage kopiert');
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SizedBox(
            width: double.infinity,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(14),
              child: SelectableText(
                formattedContent,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  height: 1.45,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void _showProtocolDetails(BuildContext context, NetworkProtocolItem item) {
  final addressInfo = _splitAddress(item.address);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.88,
        maxChildSize: 0.96,
        minChildSize: 0.55,
        builder: (context, controller) {
          return ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text(
                addressInfo.path,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (addressInfo.host.isNotEmpty) ...[
                const SizedBox(height: 6),
                SelectableText(
                  addressInfo.fullAddress,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoChip(
                    icon: Icons.link_rounded,
                    label: addressInfo.host.isEmpty ? 'Anfrage' : addressInfo.host,
                  ),
                  _InfoChip(
                    icon: Icons.tune_rounded,
                    label: '${_contentLength(item.parameters)} Zeichen Parameter',
                  ),
                  _InfoChip(
                    icon: Icons.reply_rounded,
                    label: '${_contentLength(item.response)} Zeichen Antwort',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _ProtocolSection(
                title: 'Parameter',
                content: item.parameters,
                icon: Icons.tune_rounded,
              ),
              const SizedBox(height: 12),
              _ProtocolSection(
                title: 'Antwort',
                content: item.response,
                icon: Icons.reply_all_rounded,
              ),
            ],
          );
        },
      );
    },
  );
}

({String host, String path, String fullAddress}) _splitAddress(String address) {
  final uri = Uri.tryParse(address);
  if (uri == null) {
    return (
      host: '',
      path: address,
      fullAddress: address,
    );
  }

  final path = [
    if (uri.path.isNotEmpty) uri.path,
    if (uri.hasQuery) '?${uri.query}',
  ].join();

  return (
    host: uri.host,
    path: path.isEmpty ? address : path,
    fullAddress: address,
  );
}

String _formatProtocolContent(String? content, String title) {
  final value = content?.trim();
  if (value == null || value.isEmpty) {
    return 'Keine $title';
  }

  try {
    final decoded = json.decode(value);
    return const JsonEncoder.withIndent('  ').convert(decoded);
  } catch (_) {
    return value;
  }
}

String? _contentPreview(String? content) {
  final value = content?.trim();
  if (value == null || value.isEmpty) {
    return null;
  }

  final formatted = _formatProtocolContent(value, '');
  final preview = formatted.replaceAll('\n', ' ').trim();
  if (preview.isEmpty) {
    return null;
  }
  return preview;
}

int _contentLength(String? content) {
  return content?.trim().length ?? 0;
}
