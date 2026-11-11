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

import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/ui/profile_new.dart';
import 'package:flutter/material.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

class ChangeEmail extends StatefulWidget {
  final ChangeEmailCallback changeEmail;

  const ChangeEmail({super.key, required this.changeEmail});
  @override
  _ChangeEmailState createState() => _ChangeEmailState();
}

/// Completes once the request has been answered; on success the page has
/// been closed by then.
typedef ChangeEmailCallback = FutureOr<void> Function(
    String pass, String email);

class _ChangeEmailState extends State<ChangeEmail> {
  final _passController = TextEditingController(),
      _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _passController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  /// The new design checks the fields first and shows that it is waiting.
  Future<void> _submit() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await widget.changeEmail(
        _passController.text,
        _emailController.text.trim(),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Below the navigation of the new design.
    if (ResponsiveNavigationScope.isActive(context)) {
      return ChangeEmailNewView(
        formKey: _formKey,
        passController: _passController,
        emailController: _emailController,
        busy: _busy,
        obscurePassword: _obscurePassword,
        onToggleObscure: () =>
            setState(() => _obscurePassword = !_obscurePassword),
        onSubmit: _submit,
      );
    }
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.text('profile.changeEmail')),
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Center(
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              TextField(
                obscureText: true,
                controller: _passController,
                decoration: InputDecoration(
                  labelText: l10n.text('changeEmail.currentPassword'),
                ),
              ),
              TextField(
                keyboardType: TextInputType.emailAddress,
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: l10n.text('changeEmail.newEmail'),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => widget.changeEmail(
                  _passController.text,
                  _emailController.text,
                ),
                child: Text(l10n.text('button.save')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
