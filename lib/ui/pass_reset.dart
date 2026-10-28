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
import 'package:dr/ui/auth_layout.dart';
import 'package:flutter/material.dart';

class PassReset extends StatefulWidget {
  final ResetPass resetPass;
  final bool failure;
  final String? message;
  final VoidCallback onClose;

  const PassReset(
      {super.key,
      required this.resetPass,
      required this.failure,
      this.message,
      required this.onClose});
  @override
  _PassResetState createState() => _PassResetState();
}

typedef ResetPass = void Function(String newPass);

class _PassResetState extends State<PassReset> {
  final _newPass1Controller = TextEditingController(),
      _newPass2Controller = TextEditingController();
  @override
  void initState() {
    _newPass1Controller.addListener(_onPasswordChanged);
    _newPass2Controller.addListener(_onPasswordChanged);
    super.initState();
  }

  void _onPasswordChanged() => setState(() {});

  @override
  void dispose() {
    _newPass1Controller.removeListener(_onPasswordChanged);
    _newPass2Controller.removeListener(_onPasswordChanged);
    _newPass1Controller.dispose();
    _newPass2Controller.dispose();
    super.dispose();
  }

  bool get _passwordsMatch =>
      _newPass1Controller.text == _newPass2Controller.text;

  void _submit() {
    if (_passwordsMatch && (widget.message == null || widget.failure)) {
      widget.resetPass(_newPass1Controller.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) widget.onClose();
      },
      child: AuthLayout(
        title: l10n.text('login.passResetTitle'),
        showAppBar: true,
        children: [
          AuthMessage(l10n.text('login.newPasswordRequirements')),
          AuthLayout.sectionGap,
          AuthPasswordField(
            controller: _newPass1Controller,
            label: l10n.text('login.newPassword'),
            isNewPassword: true,
          ),
          AuthLayout.fieldGap,
          AuthPasswordField(
            controller: _newPass2Controller,
            label: l10n.text('login.repeatPassword'),
            isNewPassword: true,
            errorText:
                _passwordsMatch ? null : l10n.text('login.passwordsDoNotMatch'),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          AuthLayout.sectionGap,
          if (widget.message != null) ...[
            AuthMessage(l10n.translateAuthServerText(widget.message!),
                isError: widget.failure, isStatus: !widget.failure),
            AuthLayout.fieldGap,
          ],
          if (widget.message == null || widget.failure)
            AuthPrimaryButton(
              label: l10n.text('login.passResetAction'),
              onPressed: _passwordsMatch ? _submit : null,
            ),
          if (widget.message != null && !widget.failure)
            AuthPrimaryButton(
              label: l10n.text('common.done'),
              onPressed: widget.onClose,
            ),
        ],
      ),
    );
  }
}
