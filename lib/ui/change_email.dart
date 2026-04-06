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

class ChangeEmail extends StatefulWidget {
  final ChangeEmailCallback changeEmail;

  const ChangeEmail({super.key, required this.changeEmail});
  @override
  _ChangeEmailState createState() => _ChangeEmailState();
}

typedef ChangeEmailCallback = void Function(String pass, String email);

class _ChangeEmailState extends State<ChangeEmail> {
  final _passController = TextEditingController(),
      _emailController = TextEditingController();
  @override
  Widget build(BuildContext context) {
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
