// Copyright (C) 2026 Tobias Bucci
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:dr/i18n/app_localizations.dart';
import 'package:flutter/material.dart';

/// A shared, route-local presentation for sign-in and password recovery.
class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.showAppBar = false,
    this.allowBack = true,
    this.loading = false,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final bool showAppBar, allowBack, loading;

  static const fieldGap = SizedBox(height: 18);
  static const sectionGap = SizedBox(height: 28);
  static const radius = BorderRadius.all(Radius.circular(20));

  ThemeData _authTheme(ThemeData base) {
    final colors = base.colorScheme.copyWith(
      surface: base.brightness == Brightness.light
          ? Colors.white
          : base.colorScheme.surface,
      surfaceContainerLow: base.brightness == Brightness.light
          ? const Color(0xFFF4F6F9)
          : base.colorScheme.surfaceContainerLow,
    );
    final border = OutlineInputBorder(
      borderRadius: radius,
      borderSide:
          BorderSide(color: colors.outlineVariant.withValues(alpha: 0.65)),
    );
    return base.copyWith(
      colorScheme: colors,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Color.alphaBlend(
            colors.onSurface.withValues(alpha: 0.018), colors.surface),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        floatingLabelStyle:
            base.textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
        labelStyle:
            base.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        border: border,
        enabledBorder: border,
        disabledBorder: border.copyWith(
            borderSide: BorderSide(
                color: colors.outlineVariant.withValues(alpha: 0.35))),
        focusedBorder: border.copyWith(
            borderSide: BorderSide(color: colors.primary, width: 1.5)),
        errorBorder:
            border.copyWith(borderSide: BorderSide(color: colors.error)),
        focusedErrorBorder: border.copyWith(
            borderSide: BorderSide(color: colors.error, width: 1.5)),
        errorMaxLines: 4,
        suffixIconColor: colors.onSurfaceVariant,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          elevation: 0,
          minimumSize: const Size(0, 56),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          shape: const RoundedSuperellipseBorder(borderRadius: radius),
          textStyle:
              base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(16)),
          textStyle:
              base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w500),
        ),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        shape:
            RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(28)),
      ),
    );
  }

  Widget _form(BuildContext context, {required bool wide}) {
    final theme = Theme.of(context);
    return Material(
      type: MaterialType.transparency,
      child: FocusTraversalGroup(
        child: AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!wide) ...[
                const _AuthBrand(),
                const SizedBox(height: 28),
              ],
              Semantics(
                header: true,
                child: Text(title,
                    textAlign: wide ? TextAlign.start : TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700, letterSpacing: -0.8)),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(subtitle!,
                    textAlign: wide ? TextAlign.start : TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.5)),
              ],
              const SizedBox(height: 32),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final theme = _authTheme(base);
    final colors = theme.colorScheme;
    return Theme(
      data: theme,
      child: Builder(
          builder: (context) => Scaffold(
                backgroundColor: colors.surface,
                appBar: showAppBar && allowBack
                    ? AppBar(
                        backgroundColor: colors.surface,
                        scrolledUnderElevation: 0,
                        shape: const Border(),
                      )
                    : null,
                body: Stack(
                  children: [
                    SafeArea(
                      child: LayoutBuilder(builder: (context, constraints) {
                        // At large text scales, keep a single column so both the brand
                        // and the form can wrap naturally rather than competing for width.
                        final wide = constraints.maxWidth >= 1000 &&
                            MediaQuery.textScalerOf(context).scale(1) <= 1.4;
                        final compact = constraints.maxHeight < 700;
                        return ColoredBox(
                          color: wide
                              ? colors.surfaceContainerLow
                              : colors.surface,
                          child: SingleChildScrollView(
                            key: const ValueKey('auth-scroll'),
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                  minHeight: constraints.maxHeight),
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: constraints.maxWidth < 360
                                        ? 20
                                        : wide
                                            ? 48
                                            : 28,
                                    vertical: compact ? 24 : 40),
                                child: Center(
                                  child: wide
                                      ? ConstrainedBox(
                                          constraints: const BoxConstraints(
                                              maxWidth: 1040),
                                          child: Row(
                                            children: [
                                              const Expanded(
                                                  child: Padding(
                                                padding:
                                                    EdgeInsets.only(right: 64),
                                                child:
                                                    _AuthBrand(expanded: true),
                                              )),
                                              Container(
                                                width: 520,
                                                padding:
                                                    const EdgeInsets.all(40),
                                                decoration: ShapeDecoration(
                                                  color: colors.surface,
                                                  shape:
                                                      RoundedSuperellipseBorder(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      36)),
                                                  shadows: [
                                                    BoxShadow(
                                                        color: colors.shadow
                                                            .withValues(
                                                                alpha: theme.brightness ==
                                                                        Brightness
                                                                            .dark
                                                                    ? 0.12
                                                                    : 0.035),
                                                        blurRadius: 48,
                                                        offset:
                                                            const Offset(0, 16))
                                                  ],
                                                ),
                                                child:
                                                    _form(context, wide: true),
                                              ),
                                            ],
                                          ),
                                        )
                                      : ConstrainedBox(
                                          constraints: const BoxConstraints(
                                              maxWidth: 448),
                                          child: _form(context, wide: false),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    if (loading)
                      LinearProgressIndicator(
                          semanticsLabel: context.l10n.text('login.loading')),
                  ],
                ),
              )),
    );
  }
}

class _AuthBrand extends StatelessWidget {
  const _AuthBrand({this.expanded = false});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final logo = Container(
      width: expanded ? 88 : 52,
      height: expanded ? 88 : 52,
      padding: EdgeInsets.all(expanded ? 14 : 8),
      decoration: ShapeDecoration(
        color: colors.surface,
        shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(expanded ? 28 : 18),
            side: BorderSide(
                color: colors.outlineVariant.withValues(alpha: 0.45))),
      ),
      child: ClipRSuperellipse(
        borderRadius: BorderRadius.circular(expanded ? 16 : 10),
        child: Image.asset('assets/Icon-App-512x512.png',
            excludeFromSemantics: true),
      ),
    );
    final title = Text(context.l10n.text('login.appTitle'),
        style: expanded
            ? theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w700, letterSpacing: -1.4, height: 1.12)
            : theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600));
    if (expanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          logo,
          const SizedBox(height: 28),
          title,
          const SizedBox(height: 20),
          Text(context.l10n.text('login.brandMessage'),
              style: theme.textTheme.titleLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.5,
                  fontWeight: FontWeight.w400)),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        logo,
        const SizedBox(width: 12),
        Flexible(child: title),
      ],
    );
  }
}

class AuthMessage extends StatelessWidget {
  const AuthMessage(this.text,
      {super.key, this.isError = false, this.isStatus = false});

  final String text;
  final bool isError, isStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground =
        isError ? colors.onErrorContainer : colors.onSurfaceVariant;
    return Semantics(
      liveRegion: isError || isStatus,
      child: Container(
        decoration: BoxDecoration(
          color: isError ? colors.errorContainer : colors.surfaceContainerLow,
          borderRadius: AuthLayout.radius,
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
                isError
                    ? Icons.error_outline
                    : isStatus
                        ? Icons.check_circle_outline
                        : Icons.info_outline,
                size: 20,
                color: foreground),
            const SizedBox(width: 12),
            Expanded(
                child: Text(text,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: foreground))),
          ],
        ),
      ),
    );
  }
}

class AuthPasswordField extends StatefulWidget {
  const AuthPasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.enabled = true,
    this.isNewPassword = false,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction = TextInputAction.next,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled, isNewPassword;
  final String? errorText;
  final ValueChanged<String>? onChanged, onSubmitted;
  final TextInputAction textInputAction;

  @override
  State<AuthPasswordField> createState() => _AuthPasswordFieldState();
}

class _AuthPasswordFieldState extends State<AuthPasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      enabled: widget.enabled,
      obscureText: _obscured,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: widget.enabled
          ? [
              if (widget.isNewPassword)
                AutofillHints.newPassword
              else
                AutofillHints.password,
            ]
          : null,
      textInputAction: widget.textInputAction,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        errorText: widget.errorText,
        suffixIcon: IconButton(
          tooltip: context.l10n
              .text(_obscured ? 'login.showPassword' : 'login.hidePassword'),
          onPressed: widget.enabled
              ? () => setState(() => _obscured = !_obscured)
              : null,
          icon: Icon(_obscured
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined),
        ),
      ),
    );
  }
}
