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

import 'package:collection/collection.dart';
import 'package:dr/container/login_page.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/ui/animated_linear_progress_indicator.dart';
import 'package:dr/ui/autocomplete_options.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fuzzy/fuzzy.dart';
import 'package:tuple/tuple.dart';
import 'package:url_launcher/url_launcher.dart';

typedef LoginCallback = void Function(String user, String pass, String url);
typedef ChangePassCallback =
    void Function(String user, String oldPass, String newPass, String url);
typedef SetSafeModeCallback = void Function(bool safeMode);
typedef SelectAccountCallback = void Function(int index);

class LoginPageContent extends StatefulWidget {
  final LoginPageViewModel vm;
  final LoginCallback onLogin;
  final ChangePassCallback onChangePass;
  final SetSafeModeCallback setSaveNoPass;
  final VoidCallback onReload;
  final void Function(String url) onRequestPassReset;
  final SelectAccountCallback onSelectAccount;

  const LoginPageContent({
    super.key,
    required this.vm,
    required this.onLogin,
    required this.setSaveNoPass,
    required this.onReload,
    required this.onChangePass,
    required this.onRequestPassReset,
    required this.onSelectAccount,
  });

  @override
  _LoginPageContentState createState() => _LoginPageContentState();
}

class _LoginPageContentState extends State<LoginPageContent> {
  late final _usernameController = TextEditingController(),
      _passwordController = TextEditingController(),
      _newPassword1Controller = TextEditingController(),
      _newPassword2Controller = TextEditingController(),
      _schoolController = TextEditingController(),
      _urlController = TextEditingController.fromValue(
        TextEditingValue(
          text: ".digitalesregister.it",
          selection: TextSelection.fromPosition(const TextPosition(offset: 0)),
        ),
      );
  final _schoolFocusNode = FocusNode();
  late bool safeMode;
  bool newPasswordsMatch = true;
  bool _customSchoolSelected = false;
  String? _lastOtherSchoolLabel;
  Tuple2<String, String?>? selectedPresetServer;
  @override
  void initState() {
    safeMode = widget.vm.safeMode;
    if (widget.vm.username != null) {
      _usernameController.text = widget.vm.username!;
    }
    if (widget.vm.url != null) {
      _urlController.text = widget.vm.url!;
      final school = widget.vm.servers.entries.firstWhereOrNull(
        (entry) =>
            Uri.parse(entry.value).host == Uri.parse(widget.vm.url!).host,
      );
      if (school != null) {
        selectedPresetServer = Tuple2(school.key, school.value);
        _schoolController.text = school.key;
      } else {
        _customSchoolSelected = true;
      }
    }
    _schoolFocusNode.addListener(() {
      setState(() {
        // We manually check hasFocus
      });
    });
    super.initState();
  }

  String get url => selectedPresetServer?.item2 ?? _urlController.text;

  String _submitUrl() {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final school = _schoolController.text.trim();
    if (username == 'demo' && password == 'demo' && school.isEmpty) {
      return '';
    }
    return url;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final localizedOtherSchool = context.l10n.text('login.otherSchool');
    if (_customSchoolSelected) {
      final currentValue = _schoolController.text.trim();
      if (currentValue.isEmpty ||
          (_lastOtherSchoolLabel != null &&
              currentValue == _lastOtherSchoolLabel)) {
        _schoolController.text = localizedOtherSchool;
      }
    }
    _lastOtherSchoolLabel = localizedOtherSchool;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final naturalBlue = theme.colorScheme.primary;
    final naturalBlueBg = Color.alphaBlend(
      naturalBlue.withValues(alpha: isDark ? 0.24 : 0.14),
      theme.colorScheme.surface,
    );
    final pageBackground = isDark
        ? const Color(0xFF1B2026)
        : theme.colorScheme.surface;
    final loginTheme = theme.copyWith(
      colorScheme: theme.colorScheme.copyWith(
        primary: naturalBlue,
        secondary: naturalBlue,
        tertiary: naturalBlue,
        error: naturalBlue,
        onError: Colors.white,
        errorContainer: naturalBlueBg,
        onErrorContainer: theme.colorScheme.onSurface,
      ),
    );

    InputDecoration fieldDecoration(
      String label, {
      String? errorText,
      IconData? icon,
    }) {
      return InputDecoration(
        labelText: label,
        errorText: errorText,
        prefixIcon: icon == null ? null : Icon(icon, color: naturalBlue),
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
          borderSide: BorderSide(color: naturalBlue, width: 1.6),
        ),
      );
    }

    return Theme(
      data: loginTheme,
      child: PopScope<void>(
        canPop: widget.vm.changePass && !widget.vm.mustChangePass,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop || (widget.vm.changePass && !widget.vm.mustChangePass)) {
            return;
          }
          await SystemNavigator.pop();
        },
        child: Scaffold(
          backgroundColor: pageBackground,
          appBar: widget.vm.changePass
              ? AppBar(
                  elevation: 0,
                  backgroundColor: Colors.transparent,
                  foregroundColor: theme.colorScheme.onSurface,
                  title: Text(l10n.text('login.changePasswordTitle')),
                  automaticallyImplyLeading: !widget.vm.mustChangePass,
                )
              : null,
          body: Stack(
            children: [
              SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        widget.vm.changePass ? 20 : 54,
                        16,
                        24,
                      ),
                      children: <Widget>[
                        if (!widget.vm.changePass)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 18),
                            child: Column(
                              children: [
                                Text(
                                  l10n.text('login.appTitle'),
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(
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
                                    color: naturalBlue.withValues(alpha: 0.85),
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
                              color: naturalBlue.withValues(
                                alpha: isDark ? 0.28 : 0.16,
                              ),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                            child: AutofillGroup(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (!widget.vm.changePass) ...[
                                    LayoutBuilder(
                                      builder: (context, constraints) {
                                        return RawAutocomplete<String>(
                                          focusNode: _schoolFocusNode,
                                          textEditingController:
                                              _schoolController,
                                          optionsViewBuilder:
                                              (context, onSelected, options) {
                                                return AutocompleteOptions(
                                                  displayStringForOption:
                                                      RawAutocomplete
                                                          .defaultStringForOption,
                                                  onSelected: onSelected,
                                                  options: options,
                                                  maxOptionsHeight: 220,
                                                  width: constraints.maxWidth,
                                                );
                                              },
                                          fieldViewBuilder:
                                              (
                                                context,
                                                textEditingController,
                                                focusNode,
                                                onFieldSubmitted,
                                              ) {
                                                return TextFormField(
                                                  controller:
                                                      textEditingController,
                                                  focusNode: focusNode,
                                                  onFieldSubmitted:
                                                      (String value) {
                                                        onFieldSubmitted();
                                                      },
                                                  autofocus: _schoolController
                                                      .text
                                                      .isEmpty,
                                                  enabled: !widget.vm.loading,
                                                  onChanged: (value) {
                                                    setState(() {
                                                      if (widget
                                                              .vm
                                                              .servers[value] ==
                                                          null) {
                                                        selectedPresetServer =
                                                            null;
                                                        _customSchoolSelected =
                                                            false;
                                                      } else {
                                                        selectedPresetServer =
                                                            Tuple2(
                                                              value,
                                                              widget
                                                                  .vm
                                                                  .servers[value],
                                                            );
                                                        _customSchoolSelected =
                                                            false;
                                                        _urlController.text =
                                                            selectedPresetServer!
                                                                .item2!;
                                                      }
                                                    });
                                                  },
                                                  decoration: fieldDecoration(
                                                    l10n.text('login.school'),
                                                    icon: Icons.school_outlined,
                                                    errorText:
                                                        !_schoolFocusNode
                                                                .hasFocus &&
                                                            !_customSchoolSelected &&
                                                            !equalsIgnoreCase(
                                                              _schoolController
                                                                  .text,
                                                              l10n.text(
                                                                'login.otherSchool',
                                                              ),
                                                            ) &&
                                                            _schoolController
                                                                .text
                                                                .isNotEmpty &&
                                                            selectedPresetServer ==
                                                                null
                                                        ? l10n.text(
                                                            'login.schoolNotFound',
                                                          )
                                                        : null,
                                                  ),
                                                );
                                              },
                                          optionsBuilder: (textEditingValue) {
                                            if (textEditingValue.text
                                                    .trim()
                                                    .length <
                                                3) {
                                              return [];
                                            }
                                            if (widget.vm.servers.containsKey(
                                              textEditingValue.text,
                                            )) {
                                              return [textEditingValue.text];
                                            }
                                            return [
                                              ...Fuzzy(
                                                    widget.vm.servers.keys
                                                        .toList(),
                                                    options:
                                                        FuzzyOptions<String>(
                                                          maxPatternLength: 256,
                                                          tokenize: true,
                                                        ),
                                                  )
                                                  .search(textEditingValue.text)
                                                  .take(15)
                                                  .map((e) => e.item),
                                              l10n.text('login.otherSchool'),
                                            ];
                                          },
                                          onSelected: (option) {
                                            _schoolFocusNode.unfocus();
                                            setState(() {
                                              selectedPresetServer = Tuple2(
                                                option,
                                                widget.vm.servers[option],
                                              );
                                              if (option ==
                                                  l10n.text(
                                                    'login.otherSchool',
                                                  )) {
                                                selectedPresetServer = null;
                                                _customSchoolSelected = true;
                                                _urlController.text =
                                                    ".digitalesregister.it";
                                                _urlController.selection =
                                                    TextSelection.fromPosition(
                                                      const TextPosition(
                                                        offset: 0,
                                                      ),
                                                    );
                                              } else {
                                                _customSchoolSelected = false;
                                                _urlController.text =
                                                    selectedPresetServer!
                                                        .item2!;
                                              }
                                            });
                                          },
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    TextField(
                                      decoration: fieldDecoration(
                                        l10n.text('login.address'),
                                        icon: Icons.language_rounded,
                                      ),
                                      controller: _urlController,
                                      enabled: !widget.vm.loading,
                                      keyboardType: TextInputType.url,
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  TextField(
                                    autofillHints: widget.vm.loading
                                        ? null
                                        : [AutofillHints.username],
                                    decoration: fieldDecoration(
                                      l10n.text('login.username'),
                                      icon: Icons.person_outline_rounded,
                                    ),
                                    controller: _usernameController,
                                    enabled: !widget.vm.loading,
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    autofillHints: widget.vm.loading
                                        ? null
                                        : [AutofillHints.password],
                                    decoration: fieldDecoration(
                                      widget.vm.changePass
                                          ? l10n.text('login.oldPassword')
                                          : l10n.text('login.password'),
                                      icon: Icons.lock_outline_rounded,
                                    ),
                                    controller: _passwordController,
                                    obscureText: true,
                                    enabled: !widget.vm.loading,
                                  ),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton(
                                      style: TextButton.styleFrom(
                                        foregroundColor: naturalBlue,
                                      ),
                                      onPressed: () =>
                                          widget.onRequestPassReset(url),
                                      child: Text(
                                        l10n.text('login.forgotPassword'),
                                      ),
                                    ),
                                  ),
                                  if (widget.vm.changePass) ...[
                                    if (widget.vm.mustChangePass)
                                      Container(
                                        decoration: BoxDecoration(
                                          color: naturalBlueBg.withValues(
                                            alpha: 0.35,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        padding: const EdgeInsets.all(12),
                                        child: Text(
                                          l10n.text('login.mustChangePassword'),
                                        ),
                                      ),
                                    const SizedBox(height: 10),
                                    Container(
                                      decoration: BoxDecoration(
                                        color: theme
                                            .colorScheme
                                            .surfaceContainerHighest
                                            .withValues(
                                              alpha: isDark ? 0.35 : 0.55,
                                            ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: const EdgeInsets.all(12),
                                      child: Text(
                                        l10n.text(
                                          'login.newPasswordRequirements',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    TextField(
                                      autofillHints: widget.vm.loading
                                          ? null
                                          : [AutofillHints.newPassword],
                                      decoration: fieldDecoration(
                                        l10n.text('login.newPassword'),
                                        icon:
                                            Icons.enhanced_encryption_outlined,
                                      ),
                                      controller: _newPassword1Controller,
                                      obscureText: true,
                                      enabled: !widget.vm.loading,
                                      onChanged: (_) {
                                        setState(() {
                                          newPasswordsMatch =
                                              _newPassword1Controller.text ==
                                              _newPassword2Controller.text;
                                        });
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    TextField(
                                      autofillHints: widget.vm.loading
                                          ? null
                                          : [AutofillHints.newPassword],
                                      decoration: fieldDecoration(
                                        l10n.text('login.repeatPassword'),
                                        icon: Icons.check_circle_outline,
                                        errorText: newPasswordsMatch
                                            ? null
                                            : l10n.text(
                                                'login.passwordsDoNotMatch',
                                              ),
                                      ),
                                      controller: _newPassword2Controller,
                                      obscureText: true,
                                      enabled: !widget.vm.loading,
                                      onChanged: (_) {
                                        setState(() {
                                          newPasswordsMatch =
                                              _newPassword1Controller.text ==
                                              _newPassword2Controller.text;
                                        });
                                      },
                                    ),
                                  ],
                                  if (!widget.vm.changePass) ...[
                                    const SizedBox(height: 10),
                                    Text(
                                      l10n.text('login.demoHint'),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                  const SizedBox(height: 14),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: naturalBlue,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    onPressed:
                                        widget.vm.loading || !newPasswordsMatch
                                        ? null
                                        : () {
                                            final submitUrl = _submitUrl();
                                            widget.setSaveNoPass(safeMode);
                                            if (widget.vm.changePass) {
                                              widget.onChangePass(
                                                _usernameController.text,
                                                _passwordController.text,
                                                _newPassword1Controller.text,
                                                submitUrl,
                                              );
                                            } else {
                                              widget.onLogin(
                                                _usernameController.value.text,
                                                _passwordController.value.text,
                                                submitUrl,
                                              );
                                            }
                                          },
                                    icon: Icon(
                                      widget.vm.changePass
                                          ? Icons.key_rounded
                                          : Icons.login_rounded,
                                    ),
                                    label: Text(
                                      widget.vm.changePass
                                          ? l10n.text('login.changePassword')
                                          : l10n.text('login.login'),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  SwitchListTile.adaptive(
                                    title: Text(
                                      l10n.text('login.stayLoggedIn'),
                                    ),
                                    subtitle: Text(
                                      l10n.text(
                                        'settings.keepLoggedIn.subtitle',
                                      ),
                                    ),
                                    contentPadding: EdgeInsets.zero,
                                    activeThumbColor: naturalBlue,
                                    activeTrackColor: naturalBlue.withValues(
                                      alpha: 0.42,
                                    ),
                                    value: !safeMode,
                                    onChanged: widget.vm.loading
                                        ? null
                                        : (bool value) {
                                            setState(() {
                                              safeMode = !value;
                                            });
                                          },
                                  ),
                                  if (!widget.vm.changePass)
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton.icon(
                                        style: TextButton.styleFrom(
                                          foregroundColor: naturalBlue,
                                        ),
                                        onPressed: () async {
                                          await launchUrl(
                                            Uri.https(
                                              "docs.google.com",
                                              "forms/d/e/1FAIpQLSe3BLgrC74kUiAnCGSfZ_P0HYXw0yPl3OWVatNTJv8Yh3ZN0A/viewform?usp=sf_link",
                                              <String, String>{
                                                "usp": "pp_url",
                                                "entry.1581750442": appVersion,
                                              },
                                            ),
                                          );
                                        },
                                        icon: const Icon(
                                          Icons.feedback_outlined,
                                        ),
                                        label: Text(
                                          l10n.text('login.feedback'),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (!widget.vm.changePass &&
                            widget.vm.otherAccounts.isNotEmpty)
                          Card(
                            margin: const EdgeInsets.only(top: 14),
                            elevation: 0,
                            color: theme.colorScheme.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                              side: BorderSide(
                                color: theme.dividerColor.withValues(
                                  alpha: 0.2,
                                ),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Column(
                                children: [
                                  ListTile(
                                    title: Text(
                                      l10n.text('login.otherAccounts'),
                                      style: theme.textTheme.titleMedium,
                                    ),
                                  ),
                                  for (
                                    var index = 0;
                                    index < widget.vm.otherAccounts.length;
                                    index++
                                  )
                                    ListTile(
                                      leading: const Icon(Icons.person_outline),
                                      title: Text(
                                        widget.vm.otherAccounts[index],
                                      ),
                                      onTap: () =>
                                          widget.onSelectAccount(index),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        if (widget.vm.error?.isNotEmpty == true)
                          Container(
                            margin: const EdgeInsets.only(top: 14),
                            decoration: BoxDecoration(
                              color: naturalBlueBg.withValues(
                                alpha: isDark ? 0.5 : 0.7,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              widget.vm.noInternet
                                  ? l10n.text(
                                      'login.noConnectionHint',
                                      args: {
                                        'url': widget.vm.url ?? '',
                                        'otherSchool': l10n.text(
                                          'login.otherSchool',
                                        ),
                                      },
                                    )
                                  : l10n.translateAuthServerText(
                                      widget.vm.error!,
                                    ),
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
              AnimatedLinearProgressIndicator(show: widget.vm.loading),
            ],
          ),
        ),
      ),
    );
  }
}
