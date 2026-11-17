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
import 'package:dr/ui/controlled_text_builder.dart';
import 'package:dr/ui/dialog.dart';
import 'package:flutter/material.dart';

/// Asks for the code of the two-factor authentication, again with a hint
/// when [wasWrong]. Completes with null when the user cancels.
Future<String?> showTwoFactorCodeDialog(
  BuildContext context, {
  required bool wasWrong,
}) {
  return showDialog(
    context: context,
    builder: (context) {
      return ControlledTextBuilder(
        builder: (context, textInputController) => InfoDialog(
          title: Text(context.l10n
              .text(wasWrong ? 'login.invalid2FA' : 'login.require2FA')),
          content: TextField(
            controller: textInputController,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.text('privacyConsent.cancel')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(
                context,
                textInputController.value.text,
              ),
              child: Text(context.l10n.text('login.confirm2FA')),
            ),
          ],
        ),
      );
    },
  );
}
