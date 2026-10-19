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
import 'package:dr/analytics_service.dart';
import 'package:dr/container/login_page.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/ui/auth_layout.dart';
import 'package:dr/ui/autocomplete_options.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fuzzy/fuzzy.dart';
import 'package:tuple/tuple.dart';
import 'package:url_launcher/url_launcher.dart';

typedef LoginCallback = void Function(String user, String pass, String url);
typedef ChangePassCallback = void Function(
    String user, String oldPass, String newPass, String url);
typedef SetSafeModeCallback = void Function(bool safeMode);
typedef SelectAccountCallback = void Function(int index);
typedef RemoveAccountCallback = void Function(int index);

class LoginPageContent extends StatefulWidget {
  final LoginPageViewModel vm;
  final LoginCallback onLogin;
  final ChangePassCallback onChangePass;
  final SetSafeModeCallback setSaveNoPass;
  final VoidCallback onReload;
  final void Function(String url) onRequestPassReset;
  final SelectAccountCallback onSelectAccount;
  final RemoveAccountCallback onRemoveAccount;

  const LoginPageContent({
    super.key,
    required this.vm,
    required this.onLogin,
    required this.setSaveNoPass,
    required this.onReload,
    required this.onChangePass,
    required this.onRequestPassReset,
    required this.onSelectAccount,
    required this.onRemoveAccount,
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
    _schoolFocusNode.addListener(_onSchoolFocusChanged);
    super.initState();
  }

  void _onSchoolFocusChanged() => setState(() {});

  @override
  void dispose() {
    _schoolFocusNode.removeListener(_onSchoolFocusChanged);
    _schoolFocusNode.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _newPassword1Controller.dispose();
    _newPassword2Controller.dispose();
    _schoolController.dispose();
    _urlController.dispose();
    super.dispose();
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

  void _submit() {
    if (widget.vm.loading || !newPasswordsMatch) return;
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
          _usernameController.text, _passwordController.text, submitUrl);
      AnalyticsService.logCustomEvent('login_attempt');
    }
  }

  void _checkPasswords(String _) => setState(() {
        newPasswordsMatch =
            _newPassword1Controller.text == _newPassword2Controller.text;
      });

  Future<void> _removeAccount(BuildContext context, int index) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.text('login.removeAccount.title')),
        content: Text(l10n.text('login.removeAccount.body', args: {
          'account': widget.vm.otherAccounts[index],
        })),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.text('privacyConsent.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.text('login.removeAccount')),
          ),
        ],
      ),
    );
    if (confirmed == true) widget.onRemoveAccount(index);
  }

  Widget _savedAccounts(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(l10n.text('login.otherAccounts'),
              style: theme.textTheme.titleSmall),
        ),
        const SizedBox(height: 8),
        for (var index = 0; index < widget.vm.otherAccounts.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: AuthLayout.radius,
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                contentPadding: const EdgeInsets.only(left: 16, right: 4),
                minVerticalPadding: 12,
                leading: Icon(Icons.account_circle_outlined,
                    color: theme.colorScheme.onSurfaceVariant),
                title: Text(widget.vm.otherAccounts[index]),
                onTap: () => widget.onSelectAccount(index),
                trailing: IconButton(
                  tooltip: l10n.text('login.removeAccount'),
                  onPressed: () => _removeAccount(context, index),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return PopScope<void>(
      canPop: widget.vm.changePass && !widget.vm.mustChangePass,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || (widget.vm.changePass && !widget.vm.mustChangePass)) {
          return;
        }
        await SystemNavigator.pop();
      },
      child: AuthLayout(
        title: l10n.text(
            widget.vm.changePass ? 'login.changePasswordTitle' : 'login.login'),
        showAppBar: widget.vm.changePass,
        allowBack: !widget.vm.mustChangePass,
        loading: widget.vm.loading,
        children: [
          if (!widget.vm.changePass) ...[
            LayoutBuilder(
              builder: (context, constraints) {
                return RawAutocomplete<String>(
                  focusNode: _schoolFocusNode,
                  textEditingController: _schoolController,
                  optionsViewBuilder: (context, onSelected, options) {
                    return AutocompleteOptions(
                      displayStringForOption:
                          RawAutocomplete.defaultStringForOption,
                      onSelected: onSelected,
                      options: options,
                      maxOptionsHeight: 220,
                      width: constraints.maxWidth,
                      borderRadius: AuthLayout.radius,
                    );
                  },
                  fieldViewBuilder: (
                    context,
                    textEditingController,
                    focusNode,
                    onFieldSubmitted,
                  ) {
                    return TextFormField(
                      controller: textEditingController,
                      focusNode: focusNode,
                      onFieldSubmitted: (String value) {
                        onFieldSubmitted();
                      },
                      autofocus: _schoolController.text.isEmpty,
                      enabled: !widget.vm.loading,
                      textInputAction: TextInputAction.next,
                      onChanged: (value) {
                        setState(() {
                          if (widget.vm.servers[value] == null) {
                            selectedPresetServer = null;
                            _customSchoolSelected = false;
                          } else {
                            selectedPresetServer = Tuple2(
                              value,
                              widget.vm.servers[value],
                            );
                            _customSchoolSelected = false;
                            _urlController.text = selectedPresetServer!.item2!;
                          }
                        });
                      },
                      decoration: InputDecoration(
                        labelText: l10n.text('login.school'),
                        suffixIcon: const Icon(Icons.search_rounded),
                        errorText: !_schoolFocusNode.hasFocus &&
                                !_customSchoolSelected &&
                                !equalsIgnoreCase(
                                  _schoolController.text,
                                  l10n.text(
                                    'login.otherSchool',
                                  ),
                                ) &&
                                _schoolController.text.isNotEmpty &&
                                selectedPresetServer == null
                            ? l10n.text(
                                'login.schoolNotFound',
                              )
                            : null,
                      ),
                    );
                  },
                  optionsBuilder: (textEditingValue) {
                    if (textEditingValue.text.trim().length < 3) {
                      return [];
                    }
                    if (widget.vm.servers.containsKey(
                      textEditingValue.text,
                    )) {
                      return [textEditingValue.text];
                    }
                    return [
                      ...Fuzzy(
                        widget.vm.servers.keys.toList(),
                        options: FuzzyOptions<String>(
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
                        _urlController.text = ".digitalesregister.it";
                        _urlController.selection = TextSelection.fromPosition(
                          const TextPosition(
                            offset: 0,
                          ),
                        );
                      } else {
                        _customSchoolSelected = false;
                        _urlController.text = selectedPresetServer!.item2!;
                      }
                    });
                  },
                );
              },
            ),
            AuthLayout.fieldGap,
            TextField(
              decoration:
                  InputDecoration(labelText: l10n.text('login.address')),
              controller: _urlController,
              enabled: !widget.vm.loading,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              autocorrect: false,
            ),
            AuthLayout.sectionGap,
          ],
          TextField(
            autofillHints: widget.vm.loading ? null : [AutofillHints.username],
            decoration: InputDecoration(labelText: l10n.text('login.username')),
            controller: _usernameController,
            enabled: !widget.vm.loading,
            textInputAction: TextInputAction.next,
            autocorrect: false,
          ),
          AuthLayout.fieldGap,
          AuthPasswordField(
            controller: _passwordController,
            label: l10n.text(
                widget.vm.changePass ? 'login.oldPassword' : 'login.password'),
            enabled: !widget.vm.loading,
            textInputAction: widget.vm.changePass
                ? TextInputAction.next
                : TextInputAction.done,
            onSubmitted: widget.vm.changePass ? null : (_) => _submit(),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => widget.onRequestPassReset(url),
              child: Text(l10n.text('login.forgotPassword')),
            ),
          ),
          if (widget.vm.changePass) ...[
            if (widget.vm.mustChangePass) ...[
              AuthMessage(l10n.text('login.mustChangePassword')),
              AuthLayout.fieldGap,
            ],
            AuthMessage(l10n.text('login.newPasswordRequirements')),
            AuthLayout.sectionGap,
            AuthPasswordField(
              controller: _newPassword1Controller,
              label: l10n.text('login.newPassword'),
              isNewPassword: true,
              enabled: !widget.vm.loading,
              onChanged: _checkPasswords,
            ),
            AuthLayout.fieldGap,
            AuthPasswordField(
              controller: _newPassword2Controller,
              label: l10n.text('login.repeatPassword'),
              isNewPassword: true,
              enabled: !widget.vm.loading,
              errorText: newPasswordsMatch
                  ? null
                  : l10n.text('login.passwordsDoNotMatch'),
              onChanged: _checkPasswords,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
            AuthLayout.fieldGap,
          ],
          SwitchListTile.adaptive(
            title: Text(l10n.text('login.stayLoggedIn'),
                style: theme.textTheme.bodyLarge),
            subtitle: Text(l10n.text('settings.keepLoggedIn.subtitle')),
            contentPadding: EdgeInsets.zero,
            value: !safeMode,
            onChanged: widget.vm.loading
                ? null
                : (value) => setState(() => safeMode = !value),
          ),
          AuthLayout.fieldGap,
          if (widget.vm.error?.isNotEmpty == true) ...[
            AuthMessage(
              widget.vm.noInternet
                  ? l10n.text('login.noConnectionHint', args: {
                      'url': widget.vm.url ?? '',
                      'otherSchool': l10n.text('login.otherSchool'),
                    })
                  : l10n.translateAuthServerText(widget.vm.error!),
              isError: true,
            ),
            AuthLayout.fieldGap,
          ],
          ElevatedButton.icon(
            onPressed: widget.vm.loading || !newPasswordsMatch ? null : _submit,
            icon: widget.vm.loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(widget.vm.changePass
                    ? Icons.key_rounded
                    : Icons.arrow_forward_rounded),
            label: Text(l10n.text(widget.vm.loading
                ? 'login.loading'
                : widget.vm.changePass
                    ? 'login.changePassword'
                    : 'login.login')),
          ),
          if (!widget.vm.changePass) ...[
            if (widget.vm.otherAccounts.isNotEmpty) ...[
              AuthLayout.sectionGap,
              Builder(builder: _savedAccounts),
            ],
            AuthLayout.sectionGap,
            Text(l10n.text('login.demoHint'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: () async {
                  await launchUrl(Uri.https(
                    'docs.google.com',
                    '/forms/d/e/1FAIpQLSdvhDufKHMVh4FzAUj5FiaGUjc8ma1DbD3NkRRHdWr4eE16hg/viewform',
                    <String, String>{
                      'usp': 'pp_url',
                      'entry.804572866': appVersion
                    },
                  ));
                },
                icon: const Icon(Icons.feedback_outlined, size: 18),
                label: Text(l10n.text('login.feedback')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
