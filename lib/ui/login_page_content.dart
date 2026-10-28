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

import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:dr/analytics_service.dart';
import 'package:dr/container/login_page.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/theme/auth_tokens.dart';
import 'package:dr/ui/auth_layout.dart';
import 'package:dr/util.dart';
import 'package:flutter/foundation.dart';
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

class _LoginPageContentState extends State<LoginPageContent>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _defaultAddress = ".digitalesregister.it";

  late final _usernameController = TextEditingController(),
      _passwordController = TextEditingController(),
      _newPassword1Controller = TextEditingController(),
      _newPassword2Controller = TextEditingController(),
      _schoolController = TextEditingController(),
      _urlController = TextEditingController.fromValue(
        TextEditingValue(
          text: _defaultAddress,
          selection: TextSelection.fromPosition(const TextPosition(offset: 0)),
        ),
      );
  final _schoolFocusNode = FocusNode(), _addressFocusNode = FocusNode();
  late final _shake =
      AnimationController(vsync: this, duration: AuthMotion.shake);
  late bool safeMode;
  bool newPasswordsMatch = true;
  bool _customSchoolSelected = false;

  /// The address is only shown for schools that are not in the list.
  bool _addressVisible = false;
  String? _lastOtherSchoolLabel;

  /// Only the button listens to this, so typing does not rebuild the form.
  final _submittable = ValueNotifier(false);

  /// The school field's decoration and the manual-address link follow the
  /// text and focus through this instead of rebuilding the whole form.
  late final _schoolListenable =
      Listenable.merge([_schoolController, _schoolFocusNode]);

  /// A context inside the autocomplete's actions, to reset its highlight.
  BuildContext? _schoolFieldContext;

  /// Whether the suggestions may show. Only typing (or tapping the field
  /// with a query in it) opens them; losing focus closes them, and coming
  /// back with Tab or Next does not reopen them on its own.
  final _suggestionsOpen = ValueNotifier(false);

  /// Set while Next / Enter picks a suggestion (it moves focus itself).
  bool _submittingSchool = false;
  double _lastKeyboardInset = 0;

  /// On phones, while the school search has too little room above the
  /// keyboard, the header folds away instead of the page scrolling.
  bool _headerCollapsed = false;
  Timer? _headerTimer;
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
        _addressVisible = true;
      }
    }
    for (final controller in [
      _usernameController,
      _passwordController,
      _newPassword1Controller,
    ]) {
      controller.addListener(_updateSubmittable);
    }
    super.initState();
    _updateSubmittable();
    _schoolFocusNode.addListener(_onSchoolFocus);
    WidgetsBinding.instance.addObserver(this);
  }

  void _onSchoolFocus() {
    if (_schoolFocusNode.hasFocus) {
      _scheduleHeaderCheck();
    } else {
      _suggestionsOpen.value = false;
      _setHeaderCollapsed(false);
    }
  }

  bool get _phone => AuthLayout.isPhone(Theme.of(context).platform);

  /// Closing the keyboard (e.g. with Back) leaves the field focused on
  /// Android; treat it as leaving the school search.
  @override
  void didChangeMetrics() {
    final inset = _keyboardInset;
    if (_lastKeyboardInset > 0 &&
        inset == 0 &&
        _phone &&
        _schoolFocusNode.hasFocus) {
      _schoolFocusNode.unfocus();
    }
    _lastKeyboardInset = inset;
    if (inset == 0) {
      _setHeaderCollapsed(false);
    } else {
      _scheduleHeaderCheck();
    }
  }

  /// The keyboard's height in logical pixels (view insets are physical).
  double get _keyboardInset {
    final view = View.of(context);
    return view.viewInsets.bottom / view.devicePixelRatio;
  }

  /// Decides about the header once the keyboard has stopped moving, so the
  /// fold never runs on top of the keyboard's own animation.
  void _scheduleHeaderCheck() {
    _headerTimer?.cancel();
    _headerTimer = Timer(const Duration(milliseconds: 80), _checkHeaderSpace);
  }

  /// Folds the header away when, with the keyboard up, fewer than four
  /// suggestion rows would fit below the school field. Stays folded until
  /// the field loses focus or the keyboard closes.
  void _checkHeaderSpace() {
    if (!mounted ||
        !_phone ||
        _headerCollapsed ||
        !_schoolFocusNode.hasFocus ||
        _keyboardInset == 0) {
      return;
    }
    final field = _schoolFieldContext?.findRenderObject() as RenderBox?;
    if (field == null || !field.attached) return;
    final space = _SchoolOptionsState.spaceBelow(field,
        screenHeight: MediaQuery.sizeOf(context).height,
        obstructed: _keyboardInset);
    if (space < _SchoolOptionsState.heightFor(4)) _setHeaderCollapsed(true);
  }

  void _setHeaderCollapsed(bool collapsed) {
    if (collapsed == _headerCollapsed || !mounted) return;
    setState(() => _headerCollapsed = collapsed);
    // Unfolding pushes the fields down: once it has finished, a field the
    // keyboard now covers is scrolled just into view.
    if (!collapsed && _keyboardInset > 0) {
      _headerTimer?.cancel();
      _headerTimer = Timer(
          AuthMotion.move(context, AuthMotion.base), authRevealFocusedField);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      if (_schoolFocusNode.hasFocus) _schoolFocusNode.unfocus();
    }
  }

  void _updateSubmittable() => _submittable.value = _canSubmit;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _headerTimer?.cancel();
    _schoolFocusNode.removeListener(_onSchoolFocus);
    _schoolFocusNode.dispose();
    _submittable.dispose();
    _suggestionsOpen.dispose();
    _addressFocusNode.dispose();
    _shake.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _newPassword1Controller.dispose();
    _newPassword2Controller.dispose();
    _schoolController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(LoginPageContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateSubmittable();
    final error = widget.vm.error;
    final hasError = error?.isNotEmpty == true;
    final failedAttempt =
        oldWidget.vm.loading && !widget.vm.loading && hasError;
    if (failedAttempt || (hasError && error != oldWidget.vm.error)) {
      final platform = Theme.of(context).platform;
      if (platform == TargetPlatform.iOS ||
          platform == TargetPlatform.android) {
        HapticFeedback.mediumImpact();
      }
    }
    // Like macOS: the form shakes once per rejected attempt, never for
    // connection problems.
    if (failedAttempt &&
        !widget.vm.noInternet &&
        !AuthMotion.reduced(context)) {
      _shake.forward(from: 0);
    }
  }

  /// Three decaying oscillations of up to [AuthMotion.shakeAmplitude],
  /// applied to each part of the form so it moves as one group.
  Widget _shaken(Widget child) => AnimatedBuilder(
        animation: _shake,
        child: child,
        builder: (context, child) {
          final t = _shake.value;
          final dx = AuthMotion.shakeAmplitude *
              math.sin(t * 3 * 2 * math.pi) *
              (1 - t);
          return Transform.translate(offset: Offset(dx, 0), child: child);
        },
      );

  /// Desktop focuses the school search once the entrance has settled.
  /// Phones wait for a tap so the keyboard does not cover the screen.
  void _onEntered() {
    if (widget.vm.changePass || _schoolController.text.isNotEmpty) return;
    const desktop = {
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.macOS,
    };
    if (!desktop.contains(Theme.of(context).platform)) return;
    final focused = FocusManager.instance.primaryFocus;
    if (focused == null || focused is FocusScopeNode) {
      _schoolFocusNode.requestFocus();
    }
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

  /// Username and password are required; a password change also needs two
  /// matching new passwords.
  bool get _canSubmit =>
      !widget.vm.loading &&
      _usernameController.text.trim().isNotEmpty &&
      _passwordController.text.isNotEmpty &&
      (!widget.vm.changePass ||
          (_newPassword1Controller.text.isNotEmpty && newPasswordsMatch));

  void _submit() {
    if (!_canSubmit) return;
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      HapticFeedback.lightImpact();
    }
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

  void _checkPasswords(String _) {
    final match = _newPassword1Controller.text == _newPassword2Controller.text;
    if (match != newPasswordsMatch) setState(() => newPasswordsMatch = match);
    _updateSubmittable();
  }

  void _selectSchool(String option, String otherSchool) {
    _suggestionsOpen.value = false;
    final custom = option == otherSchool;
    setState(() {
      if (custom) {
        _useCustomAddress();
      } else {
        selectedPresetServer = Tuple2(option, widget.vm.servers[option]);
        _customSchoolSelected = false;
        _addressVisible = false;
        _urlController.text = selectedPresetServer!.item2!;
      }
    });
    // Hand focus on (the keyboard stays up) instead of dropping it, which
    // also cancelled the move a Next key press had already started: to the
    // address once it has appeared, or to the username. Next / Enter move
    // focus on by themselves, so only a tapped suggestion needs it here.
    if (custom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _addressFocusNode.requestFocus();
      });
    } else if (!_submittingSchool) {
      _schoolFocusNode.nextFocus();
    }
  }

  void _onSchoolChanged(String value) {
    _suggestionsOpen.value = value.trim().isNotEmpty;
    final server = widget.vm.servers[value];
    final preset = server == null ? null : Tuple2(value, server);
    // Most keystrokes change neither the matched school nor the custom
    // flag; those only update the field (via [_schoolListenable]).
    if (preset == selectedPresetServer && !_customSchoolSelected) return;
    setState(() {
      _customSchoolSelected = false;
      selectedPresetServer = preset;
      if (preset != null) {
        _addressVisible = false;
        _urlController.text = preset.item2;
      }
    });
  }

  /// New suggestions start at the best match, also for Enter.
  void _resetSchoolHighlight() {
    final context = _schoolFieldContext;
    if (context != null && context.mounted) {
      Actions.maybeInvoke(context, const AutocompleteFirstOptionIntent());
    }
  }

  /// Same as picking "Andere Schule": reveal an empty address.
  void _useCustomAddress() {
    selectedPresetServer = null;
    _customSchoolSelected = true;
    _addressVisible = true;
    _urlController.text = _defaultAddress;
    _urlController.selection =
        TextSelection.fromPosition(const TextPosition(offset: 0));
  }

  void _enterAddressManually() {
    setState(() {
      _schoolController.text = context.l10n.text('login.otherSchool');
      _useCustomAddress();
    });
    _addressFocusNode.requestFocus();
  }

  String? _schoolError(AppLocalizations l10n) {
    final notFound = !_schoolFocusNode.hasFocus &&
        !_customSchoolSelected &&
        !equalsIgnoreCase(
            _schoolController.text, l10n.text('login.otherSchool')) &&
        _schoolController.text.isNotEmpty &&
        selectedPresetServer == null;
    return notFound ? l10n.text('login.schoolNotFound') : null;
  }

  Future<bool> _confirmRemoval(BuildContext context, int index) async {
    final l10n = context.l10n;
    final tokens = AuthTokens.of(context);
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
            style: FilledButton.styleFrom(
                backgroundColor: tokens.destructiveFill,
                foregroundColor: tokens.onAccent),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.text('login.removeAccount')),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _sendFeedback() async {
    await launchUrl(Uri.https(
      'docs.google.com',
      '/forms/d/e/1FAIpQLSdvhDufKHMVh4FzAUj5FiaGUjc8ma1DbD3NkRRHdWr4eE16hg/viewform',
      <String, String>{'usp': 'pp_url', 'entry.804572866': appVersion},
    ));
  }

  Widget _schoolField(AppLocalizations l10n) {
    final otherSchool = l10n.text('login.otherSchool');
    return LayoutBuilder(
      builder: (context, constraints) => RawAutocomplete<String>(
        focusNode: _schoolFocusNode,
        textEditingController: _schoolController,
        optionsViewBuilder: (context, onSelected, options) => _SchoolOptions(
          options: options,
          onSelected: onSelected,
          width: constraints.maxWidth,
          open: _suggestionsOpen,
          expectKeyboard: _phone,
          field: () => _schoolFieldContext?.findRenderObject() as RenderBox?,
          onOptionsChanged: _resetSchoolHighlight,
        ),
        fieldViewBuilder:
            (context, textEditingController, focusNode, onFieldSubmitted) {
          final preset = selectedPresetServer?.item2;
          return ListenableBuilder(
            listenable: _schoolListenable,
            builder: (context, _) {
              // fieldViewBuilder gets the autocomplete's own context, which
              // sits above its actions; this one is inside them.
              _schoolFieldContext = context;
              final error = _schoolError(l10n);
              return AuthFieldFrame(
                hasError: error != null,
                enabled: !widget.vm.loading,
                child: TextFormField(
                  controller: textEditingController,
                  focusNode: focusNode,
                  // Enter / Next only picks a suggestion the user can see.
                  onFieldSubmitted: (String value) {
                    if (!_suggestionsOpen.value) return;
                    _submittingSchool = true;
                    onFieldSubmitted();
                    _submittingSchool = false;
                  },
                  onTap: () => _suggestionsOpen.value =
                      textEditingController.text.trim().isNotEmpty,
                  // Phones keep a field focused when tapping elsewhere; for
                  // the school search that would leave the list open. The
                  // list itself counts as inside (same tap region group).
                  onTapOutside: (_) => focusNode.unfocus(),
                  enabled: !widget.vm.loading,
                  textInputAction: TextInputAction.next,
                  scrollPadding: AuthTokens.fieldScrollPadding,
                  autocorrect: false,
                  onChanged: _onSchoolChanged,
                  decoration: InputDecoration(
                    labelText: l10n.text('login.school'),
                    helperText:
                        preset == null ? null : Uri.tryParse(preset)?.host,
                    suffixIcon: const ExcludeSemantics(
                        child: Icon(Icons.search_rounded, size: 20)),
                    errorText: error,
                  ),
                ),
              );
            },
          );
        },
        optionsBuilder: (textEditingValue) {
          if (textEditingValue.text.trim().length < 3) {
            return [];
          }
          if (widget.vm.servers.containsKey(textEditingValue.text)) {
            return [textEditingValue.text];
          }
          return [
            ...Fuzzy(
              widget.vm.servers.keys.toList(),
              options: FuzzyOptions<String>(
                maxPatternLength: 256,
                tokenize: true,
              ),
            ).search(textEditingValue.text).take(15).map((e) => e.item),
            otherSchool,
          ];
        },
        onSelected: (option) => _selectSchool(option, otherSchool),
      ),
    );
  }

  List<Widget> _schoolSection(AppLocalizations l10n) {
    return [
      _shaken(_schoolField(l10n)),
      ListenableBuilder(
        listenable: _schoolListenable,
        // Offered next to "Schule nicht gefunden", once the search is closed.
        builder: (context, child) => AuthReveal(
          visible: !_addressVisible &&
              !_schoolFocusNode.hasFocus &&
              _schoolController.text.trim().isNotEmpty &&
              selectedPresetServer == null,
          child: child!,
        ),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: AuthLink(
            label: l10n.text('login.enterAddressManually'),
            onPressed: widget.vm.loading ? null : _enterAddressManually,
          ),
        ),
      ),
      AuthReveal(
        visible: _addressVisible,
        child: Padding(
          padding: EdgeInsets.only(top: AuthSpacingScope.of(context).field),
          child: _shaken(AuthFieldFrame(
            enabled: !widget.vm.loading,
            child: TextField(
              decoration:
                  InputDecoration(labelText: l10n.text('login.address')),
              controller: _urlController,
              focusNode: _addressFocusNode,
              enabled: !widget.vm.loading,
              keyboardType: TextInputType.url,
              autofillHints: const [AutofillHints.url],
              textInputAction: TextInputAction.next,
              scrollPadding: AuthTokens.fieldScrollPadding,
              autocorrect: false,
            ),
          )),
        ),
      ),
      AuthLayout.fieldGap,
    ];
  }

  List<Widget> _newPasswordSection(AppLocalizations l10n) => [
        AuthLayout.sectionGap,
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
          errorText:
              newPasswordsMatch ? null : l10n.text('login.passwordsDoNotMatch'),
          onChanged: _checkPasswords,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
        ),
      ];

  String? _errorMessage(AppLocalizations l10n) {
    if (widget.vm.error?.isNotEmpty != true) return null;
    return widget.vm.noInternet
        ? l10n.text('login.noConnectionHint', args: {
            'url': widget.vm.url ?? '',
            'otherSchool': l10n.text('login.otherSchool'),
          })
        : l10n.translateAuthServerText(widget.vm.error!);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final changePass = widget.vm.changePass;
    final error = _errorMessage(l10n);
    return PopScope<void>(
      canPop: changePass && !widget.vm.mustChangePass,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || (changePass && !widget.vm.mustChangePass)) {
          return;
        }
        await SystemNavigator.pop();
      },
      child: AuthLayout(
        title: l10n
            .text(changePass ? 'login.changePasswordTitle' : 'login.welcome'),
        subtitle: changePass ? null : l10n.text('login.signInHint'),
        showAppBar: changePass,
        allowBack: !widget.vm.mustChangePass,
        onEntered: _onEntered,
        // A first run (no saved accounts) should fit without scrolling.
        fitToScreen: !changePass && widget.vm.otherAccounts.isEmpty,
        collapseHeader: _headerCollapsed,
        children: [
          if (!changePass) ..._schoolSection(l10n),
          _shaken(AuthFieldFrame(
            enabled: !widget.vm.loading,
            child: TextField(
              autofillHints:
                  widget.vm.loading ? null : [AutofillHints.username],
              decoration:
                  InputDecoration(labelText: l10n.text('login.username')),
              controller: _usernameController,
              enabled: !widget.vm.loading,
              textInputAction: TextInputAction.next,
              scrollPadding: AuthTokens.fieldScrollPadding,
              autocorrect: false,
              enableSuggestions: false,
            ),
          )),
          AuthLayout.fieldGap,
          _shaken(AuthPasswordField(
            controller: _passwordController,
            label:
                l10n.text(changePass ? 'login.oldPassword' : 'login.password'),
            enabled: !widget.vm.loading,
            textInputAction:
                changePass ? TextInputAction.next : TextInputAction.done,
            onSubmitted: changePass ? null : (_) => _submit(),
          )),
          if (changePass) ..._newPasswordSection(l10n),
          const AuthGap.small(),
          _StayLoggedIn(
            value: !safeMode,
            onChanged: widget.vm.loading
                ? null
                : (value) => setState(() => safeMode = !value),
          ),
          const AuthGap.button(),
          AuthReveal(
            visible: error != null,
            duration: AuthMotion.error,
            fadeDelay: const Duration(milliseconds: 80),
            child: Padding(
              padding: const EdgeInsets.only(bottom: AuthTokens.space2),
              child: AuthMessage(error ?? '', isError: true),
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _submittable,
            builder: (context, submittable, _) => AuthPrimaryButton(
              label: l10n
                  .text(changePass ? 'login.changePassword' : 'login.login'),
              loadingLabel: l10n.text('login.loading'),
              loading: widget.vm.loading,
              onPressed: submittable ? _submit : null,
            ),
          ),
          const AuthGap.small(),
          Center(
            child: AuthLink(
              label: l10n.text('login.forgotPassword'),
              onPressed: () => widget.onRequestPassReset(url),
            ),
          ),
          if (!changePass) ...[
            if (widget.vm.otherAccounts.isNotEmpty) ...[
              const AuthGap.footer(),
              _AccountList(
                accounts: widget.vm.otherAccounts,
                loading: widget.vm.loading,
                onSelect: widget.onSelectAccount,
                confirmRemove: (index) => _confirmRemoval(context, index),
                onRemove: widget.onRemoveAccount,
              ),
            ],
            const AuthGap.footer(),
            _Footer(onFeedback: _sendFeedback),
          ],
        ],
      ),
    );
  }
}

class _StayLoggedIn extends StatelessWidget {
  const _StayLoggedIn({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = AuthTokens.of(context);
    final text = Theme.of(context).textTheme;
    // The whole row toggles and highlights; the adaptive switch keeps its
    // native animation and is the row's keyboard focus target.
    return MergeSemantics(
      child: AuthPressable(
        focusable: false,
        outset: 12,
        borderRadius: AuthTokens.radius,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l10n.text('login.stayLoggedIn'),
                          style: text.bodyLarge?.copyWith(
                              fontSize: 16,
                              color: onChanged == null
                                  ? tokens.secondaryText
                                  : tokens.primaryText)),
                      const SizedBox(height: 2),
                      Text(l10n.text('login.stayLoggedIn.subtitle'),
                          style: text.bodySmall?.copyWith(
                              fontSize: 13,
                              height: 1.35,
                              color: tokens.secondaryText)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AuthTokens.space2),
              Transform.scale(
                scale: 0.85,
                alignment: AlignmentDirectional.centerEnd,
                child: Switch.adaptive(
                  value: value,
                  onChanged: onChanged,
                  activeTrackColor: tokens.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// School suggestions below the search field.
///
/// The list scrolls on its own: its scroll notifications are absorbed so the
/// page's drag-to-dismiss-keyboard never sees them (that used to unfocus the
/// field and close the list mid-drag). Each new query starts at the top with
/// the best match highlighted. It overlays the fields below and is as tall
/// as the room between the field and the keyboard (never moving the page),
/// and it fades in and scales up from 98 % at the field's top edge each
/// time it opens.
class _SchoolOptions extends StatefulWidget {
  const _SchoolOptions({
    required this.options,
    required this.onSelected,
    required this.width,
    required this.open,
    required this.expectKeyboard,
    required this.field,
    required this.onOptionsChanged,
  });

  final Iterable<String> options;
  final AutocompleteOnSelected<String> onSelected;
  final double width;

  /// Whether the list may show at all (see `_suggestionsOpen`).
  final ValueListenable<bool> open;

  /// Phones: the keyboard is (about to be) up while the list shows.
  final bool expectKeyboard;

  /// The school field's render box, which the list hangs below.
  final ValueGetter<RenderBox?> field;

  /// Called when a new query produced new suggestions.
  final VoidCallback onOptionsChanged;

  @override
  State<_SchoolOptions> createState() => _SchoolOptionsState();
}

class _SchoolOptionsState extends State<_SchoolOptions>
    with SingleTickerProviderStateMixin {
  static const _rowHeight = 44.0, _gap = AuthTokens.space1;

  /// The list's vertical padding.
  static const _listPadding = 12.0;
  static final _maxHeight = heightFor(6);

  /// At least three rows whenever the screen has room for them.
  static final _usefulHeight = heightFor(3);

  /// The list height that shows [rows] rows.
  static double heightFor(int rows) => rows * _rowHeight + _listPadding;

  /// The room for the list below [field]: from the field's bottom (plus the
  /// gap above the list) down to the [obstructed] part of the screen
  /// (keyboard or navigation bar), less an 8 px margin.
  static double spaceBelow(RenderBox field,
      {required double screenHeight, required double obstructed}) {
    final fieldBottom = field.localToGlobal(Offset(0, field.size.height)).dy;
    return screenHeight - obstructed - fieldBottom - _gap - AuthTokens.space1;
  }

  final _scroll = ScrollController();
  late final AnimationController _appear;
  late final CurvedAnimation _curve;
  late final Animation<double> _scale;
  int? _revealedHighlight;

  @override
  void initState() {
    super.initState();
    _appear = AnimationController(vsync: this, duration: AuthMotion.overlay);
    _curve = CurvedAnimation(parent: _appear, curve: AuthMotion.decelerate);
    _scale = Tween(begin: 0.98, end: 1.0).animate(_curve);
    widget.open.addListener(_onOpenChanged);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => widget.onOptionsChanged());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _appear.duration = AuthMotion.fade(context, AuthMotion.overlay);
    if (_appear.isDismissed && widget.open.value) _appear.forward();
  }

  void _onOpenChanged() {
    if (widget.open.value) {
      _appear.forward(from: 0);
    } else {
      _appear.value = 0;
    }
  }

  @override
  void didUpdateWidget(_SchoolOptions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.open != widget.open) {
      oldWidget.open.removeListener(_onOpenChanged);
      widget.open.addListener(_onOpenChanged);
    }
    if (const IterableEquality<String>()
        .equals(oldWidget.options, widget.options)) {
      return;
    }
    // A new query: back to the first result.
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _revealedHighlight = null;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => widget.onOptionsChanged());
  }

  @override
  void dispose() {
    widget.open.removeListener(_onOpenChanged);
    _curve.dispose();
    _appear.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Keeps a row moved to with the arrow keys in view, scrolling only this
  /// list (never the page) and only as far as needed.
  void _reveal(BuildContext row, int index) {
    if (_revealedHighlight == index) return;
    final previous = _revealedHighlight;
    _revealedHighlight = index;
    if (previous == null) return; // the first result is already in view
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final object = row.mounted ? row.findRenderObject() : null;
      if (object == null || !_scroll.hasClients) return;
      _scroll.position.ensureVisible(
        object,
        alignmentPolicy: index > previous
            ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
            : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AuthTokens.of(context);
    final text = Theme.of(context).textTheme;
    final reduced = AuthMotion.reduced(context);
    // The keyboard's final height from the moment it starts opening, so the
    // list does not first size itself for a half-open keyboard.
    // Keyboard (at its full height from the moment it starts opening) or
    // navigation bar. Rebuilds whenever it changes.
    final obstructed =
        authObstructedBottom(context, expectingKeyboard: widget.expectKeyboard);
    final screenHeight = MediaQuery.sizeOf(context).height;
    // Touch shows no highlight; keyboard and mouse users see the current one.
    final showHighlight =
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final highlighted = AutocompleteHighlightedOption.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: widget.open,
      builder: (context, open, _) {
        if (!open) return const SizedBox.shrink();
        // Laid out after the field each frame (the constraints change when
        // the field moves), so the field's position here is current.
        return LayoutBuilder(builder: (context, constraints) {
          double measure() {
            final field = widget.field();
            return field != null && field.attached
                ? _SchoolOptionsState.spaceBelow(field,
                    screenHeight: screenHeight, obstructed: obstructed)
                : constraints.maxHeight - _gap - AuthTokens.space1;
          }

          final available = measure();
          // The page may still place the field during this frame (e.g. at
          // the end of the header fold): measure again once it is settled.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && (measure() - available).abs() > 0.5) {
              setState(() {});
            }
          });
          // Never under the keyboard; three rows or more when they fit.
          final maxHeight = available >= _usefulHeight
              ? math.min(available, _maxHeight)
              : math.max(available, 0.0);
          return Align(
            alignment: AlignmentDirectional.topStart,
            child: Padding(
              padding: const EdgeInsets.only(top: _gap),
              child: FadeTransition(
                opacity: _curve,
                child: ScaleTransition(
                  scale: reduced ? kAlwaysCompleteAnimation : _scale,
                  alignment: Alignment.topCenter,
                  child: RepaintBoundary(
                    child: Material(
                      color: tokens.fieldFill,
                      elevation: 12,
                      shadowColor: Colors.black.withValues(alpha: 0.35),
                      shape: RoundedSuperellipseBorder(
                        borderRadius: AuthTokens.radius,
                        side: BorderSide(color: tokens.hairline),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                            maxHeight: maxHeight, maxWidth: widget.width),
                        // Swallow the list's scrolling so the page never
                        // treats it as its own drag.
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (_) => true,
                          child: ListView.builder(
                            controller: _scroll,
                            physics: const ClampingScrollPhysics(),
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            shrinkWrap: true,
                            itemCount: widget.options.length,
                            itemBuilder: (context, index) {
                              final option = widget.options.elementAt(index);
                              final isHighlighted = index == highlighted;
                              if (isHighlighted) _reveal(context, index);
                              // Options never take focus from the field.
                              return AuthPressable(
                                focusable: false,
                                highlighted: showHighlight && isHighlighted,
                                onTap: () => widget.onSelected(option),
                                child: Container(
                                  constraints:
                                      const BoxConstraints(minHeight: 44),
                                  alignment: AlignmentDirectional.centerStart,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: AuthTokens.space2,
                                      vertical: 10),
                                  child: Text(option,
                                      style: text.bodyLarge?.copyWith(
                                          fontSize: 16,
                                          color: tokens.primaryText)),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        });
      },
    );
  }
}

/// Saved accounts as one rounded group with hairline separators. Long lists
/// collapse to the first few rows; removed rows fade and fold away after
/// the confirmation.
class _AccountList extends StatefulWidget {
  const _AccountList({
    required this.accounts,
    required this.loading,
    required this.onSelect,
    required this.confirmRemove,
    required this.onRemove,
  });

  final List<String> accounts;
  final bool loading;
  final ValueChanged<int> onSelect, onRemove;
  final Future<bool> Function(int index) confirmRemove;

  @override
  State<_AccountList> createState() => _AccountListState();
}

class _AccountListState extends State<_AccountList> {
  static const _collapsedCount = 3;
  bool _expanded = false;
  int? _removing, _selected;

  @override
  void didUpdateWidget(_AccountList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The removed row stays folded until the list without it arrives.
    if (!const ListEquality<String>()
        .equals(oldWidget.accounts, widget.accounts)) {
      _removing = null;
    }
    if (!widget.loading) _selected = null;
  }

  Future<void> _remove(int index) async {
    if (await widget.confirmRemove(index) && mounted) {
      setState(() => _removing = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = AuthTokens.of(context);
    final text = Theme.of(context).textTheme;
    final count = widget.accounts.length;
    final collapsible = count > _collapsedCount + 1;
    final shown = collapsible && !_expanded ? _collapsedCount : count;
    final seen = <String, int>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(
              left: AuthTokens.space2, bottom: AuthTokens.space1),
          child: Semantics(
            header: true,
            child: Text(l10n.text('login.otherAccounts'),
                style: text.bodySmall
                    ?.copyWith(fontSize: 13, color: tokens.secondaryText)),
          ),
        ),
        _GlidingSize(
          child: RepaintBoundary(
              child: Material(
            color: tokens.groupFill,
            shape: const RoundedSuperellipseBorder(
                borderRadius: AuthTokens.radius),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var index = 0; index < shown; index++)
                  _buildRow(index, seen),
              ],
            ),
          )),
        ),
        if (collapsible)
          Center(
            child: AuthLink(
              label: _expanded
                  ? l10n.text('login.showFewerAccounts')
                  : l10n.text('login.showMoreAccounts',
                      args: {'count': '${count - _collapsedCount}'}),
              onPressed: () => setState(() => _expanded = !_expanded),
            ),
          ),
      ],
    );
  }

  Widget _buildRow(int index, Map<String, int> seen) {
    final tokens = AuthTokens.of(context);
    final name = widget.accounts[index];
    final occurrence = seen[name] = (seen[name] ?? -1) + 1;
    Widget row = _AccountRow(
      name: name,
      loading: widget.loading && _selected == index,
      onTap: () {
        setState(() => _selected = index);
        widget.onSelect(index);
      },
      onRemove: () => _remove(index),
    );
    if (index > 0) {
      row = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(
              height: 1,
              thickness: 1,
              indent: AuthTokens.space2 + 36 + 12,
              color: tokens.hairline),
          row,
        ],
      );
    }
    // Rows revealed by "show more" fade in one after another.
    if (index >= _collapsedCount && _expanded) {
      row = _StaggeredFadeIn(order: index - _collapsedCount, child: row);
    }
    return AuthReveal(
      // Keyed by account so a removal never hands one row's state to the next.
      key: ValueKey('account-$name-$occurrence'),
      visible: _removing != index,
      duration: AuthMotion.exit,
      fadeDelay: Duration.zero,
      offset: 0,
      onHidden: () => widget.onRemove(index),
      child: row,
    );
  }
}

/// Animates height changes, or just applies them with reduced motion
/// (a zero-length [AnimatedSize] trips a layout assertion).
class _GlidingSize extends StatelessWidget {
  const _GlidingSize({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AuthMotion.reduced(context)
      ? child
      : AnimatedSize(
          duration: AuthMotion.base,
          curve: AuthMotion.decelerate,
          alignment: Alignment.topCenter,
          child: child,
        );
}

/// Fades a row in once, [order] × 30 ms after the rows before it.
class _StaggeredFadeIn extends StatefulWidget {
  const _StaggeredFadeIn({required this.order, required this.child});

  final int order;
  final Widget child;

  @override
  State<_StaggeredFadeIn> createState() => _StaggeredFadeInState();
}

class _StaggeredFadeInState extends State<_StaggeredFadeIn>
    with SingleTickerProviderStateMixin {
  static const _step = 30;
  late final AnimationController _controller;
  late final CurvedAnimation _opacity;

  @override
  void initState() {
    super.initState();
    final total = AuthMotion.base.inMilliseconds + _step * widget.order;
    _controller = AnimationController(
        vsync: this, duration: Duration(milliseconds: total));
    _opacity = CurvedAnimation(
        parent: _controller,
        curve: Interval(_step * widget.order / total, 1,
            curve: AuthMotion.standard));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_controller.isDismissed) return;
    if (AuthMotion.reduced(context)) {
      _controller.duration = AuthMotion.reducedFade;
    }
    _controller.forward();
  }

  @override
  void dispose() {
    _opacity.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
      opacity: _opacity, alwaysIncludeSemantics: true, child: widget.child);
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.name,
    required this.loading,
    required this.onTap,
    required this.onRemove,
  });

  final String name;
  final bool loading;
  final VoidCallback onTap, onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = AuthTokens.of(context);
    final text = Theme.of(context).textTheme;
    final initial =
        name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    return AuthPressable(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
              start: AuthTokens.space2, end: 4),
          child: Row(
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: tokens.avatarFill, shape: BoxShape.circle),
                  child: Text(initial,
                      style: text.titleSmall?.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: tokens.secondaryText)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyLarge
                          ?.copyWith(fontSize: 16, color: tokens.primaryText)),
                ),
              ),
              // Signing in with this account shows the same spinner as the
              // main button in place of the remove action.
              AnimatedSwitcher(
                duration:
                    AuthMotion.fade(context, const Duration(milliseconds: 200)),
                child: loading
                    ? SizedBox.square(
                        key: const ValueKey('loading'),
                        dimension: 48,
                        child: Center(
                          child: RepaintBoundary(
                            child: SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: tokens.accent),
                            ),
                          ),
                        ),
                      )
                    : IconButton(
                        key: const ValueKey('remove'),
                        tooltip: context.l10n.text('login.removeAccount'),
                        onPressed: onRemove,
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.onFeedback});

  final VoidCallback onFeedback;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = AuthTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.text('login.demoHint'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 13, height: 1.4, color: tokens.secondaryText)),
        Center(
          child: AuthLink(
              label: l10n.text('login.feedback'), onPressed: onFeedback),
        ),
      ],
    );
  }
}
