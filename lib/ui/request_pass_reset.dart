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
import 'package:dr/theme/auth_tokens.dart';
import 'package:dr/ui/auth_layout.dart';
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

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _submit() =>
      widget.resetPass(_usernameController.text, _emailController.text);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AuthLayout(
      title: l10n.text('login.forgotPassword'),
      showAppBar: true,
      children: [
        AuthFieldFrame(
          child: TextField(
            autofillHints: const [AutofillHints.username],
            controller: _usernameController,
            autocorrect: false,
            scrollPadding: AuthTokens.fieldScrollPadding,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(labelText: l10n.text('login.username')),
          ),
        ),
        AuthLayout.fieldGap,
        AuthFieldFrame(
          child: TextField(
            autofillHints: const [AutofillHints.email],
            keyboardType: TextInputType.emailAddress,
            controller: _emailController,
            autocorrect: false,
            scrollPadding: AuthTokens.fieldScrollPadding,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(labelText: l10n.text('login.newEmail')),
          ),
        ),
        AuthLayout.sectionGap,
        if (widget.message != null) ...[
          AuthMessage(l10n.translateAuthServerText(widget.message!),
              isError: widget.failure, isStatus: !widget.failure),
          AuthLayout.fieldGap,
        ],
        AuthPrimaryButton(
          label: l10n.text('login.requestPasswordReset'),
          onPressed: _submit,
        ),
      ],
    );
  }
}
