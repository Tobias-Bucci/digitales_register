// Copyright (C) 2021 Michael Debertol
// Copyright (C) 2026 Tobias Bucci
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

import 'package:dr/i18n/app_localizations.dart';
import 'package:flutter/material.dart';

class RequestPassReset extends StatefulWidget {
  final ResetPass resetPass;
  final bool failure;
  final String? message;

  const RequestPassReset({
    super.key,
    required this.resetPass,
    required this.failure,
    this.message,
  });
  @override
  _RequestPassResetState createState() => _RequestPassResetState();
}

typedef ResetPass = void Function(String username, String email);

class _RequestPassResetState extends State<RequestPassReset> {
  final _usernameController = TextEditingController(),
      _emailController = TextEditingController();

  InputDecoration _fieldDecoration(
    BuildContext context,
    String label,
    IconData icon,
    Color accent,
  ) {
    final theme = Theme.of(context);
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: accent),
      filled: true,
      fillColor: theme.colorScheme.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: theme.dividerColor.withValues(alpha: 0.25),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: theme.dividerColor.withValues(alpha: 0.25),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: accent, width: 1.6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = theme.colorScheme.primary;
    final accentBg = Color.alphaBlend(
      accent.withValues(alpha: isDark ? 0.24 : 0.14),
      theme.colorScheme.surface,
    );
    final pageBackground = isDark
        ? const Color(0xFF1B2026)
        : theme.colorScheme.surface;

    final pageTheme = theme.copyWith(
      colorScheme: theme.colorScheme.copyWith(
        primary: accent,
        secondary: accent,
        tertiary: accent,
        error: accent,
        errorContainer: accentBg,
        onErrorContainer: theme.colorScheme.onSurface,
      ),
    );

    return Theme(
      data: pageTheme,
      child: Scaffold(
        backgroundColor: pageBackground,
        appBar: AppBar(
          title: Text(l10n.text('login.forgotPassword')),
          elevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: theme.colorScheme.onSurface,
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 36, 16, 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Column(
                      children: [
                        Text(
                          l10n.text('login.appTitle'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                            color: isDark
                                ? const Color(0xFFE7EDF3)
                                : const Color(0xFF1A2733),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: 68,
                          height: 3,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Card(
                    elevation: isDark ? 0 : 1,
                    color: theme.colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                      side: BorderSide(
                        color: accent.withValues(alpha: isDark ? 0.28 : 0.16),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      child: AutofillGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            TextField(
                              autofillHints: const [AutofillHints.username],
                              controller: _usernameController,
                              decoration: _fieldDecoration(
                                context,
                                l10n.text('login.username'),
                                Icons.person_outline_rounded,
                                accent,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              autofillHints: const [AutofillHints.email],
                              keyboardType: TextInputType.emailAddress,
                              controller: _emailController,
                              decoration: _fieldDecoration(
                                context,
                                l10n.text('login.newEmail'),
                                Icons.alternate_email_rounded,
                                accent,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () => widget.resetPass(
                                _usernameController.text,
                                _emailController.text,
                              ),
                              icon: const Icon(Icons.send_rounded),
                              label: Text(
                                l10n.text('login.requestPasswordReset'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (widget.message != null)
                    Container(
                      margin: const EdgeInsets.only(top: 14),
                      decoration: BoxDecoration(
                        color: accentBg.withValues(alpha: isDark ? 0.5 : 0.7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        l10n.translateAuthServerText(widget.message!),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
