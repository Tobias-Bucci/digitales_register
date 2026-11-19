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

import 'package:dr/external_links.dart';
import 'package:dr/main.dart' show tr;
import 'package:dr/ui/dialog.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

const _originalProjectLink = 'https://github.com/miDeb/digitales_register';
const _forkProjectLink = 'https://github.com/Tobias-Bucci/digitales_register';

/// Shows the dialog that greets a new user and links both projects.
Future<void> showWelcomeDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const WelcomeDialog(),
  );
}

/// The welcome dialog. It owns the tap recognizers of its links and opens
/// them through [openExternalLink], like every other link of the app (#145).
class WelcomeDialog extends StatefulWidget {
  const WelcomeDialog({super.key});

  @override
  State<WelcomeDialog> createState() => _WelcomeDialogState();
}

class _WelcomeDialogState extends State<WelcomeDialog> {
  final _originalProject = TapGestureRecognizer()
    ..onTap = () => openExternalLink(_originalProjectLink);
  final _forkProject = TapGestureRecognizer()
    ..onTap = () => openExternalLink(_forkProjectLink);

  @override
  void dispose() {
    _originalProject.dispose();
    _forkProject.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final linkStyle = TextStyle(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
    );
    return InfoDialog(
      title: Text(tr('about.welcome.title')),
      content: Text.rich(
        TextSpan(
          text: tr('about.welcome.bodyPrefix'),
          children: [
            TextSpan(
              text: 'github.com/mideb/digitales_register',
              style: linkStyle,
              recognizer: _originalProject,
            ),
            TextSpan(text: tr('about.welcome.bodyMiddle')),
            TextSpan(
              text: 'github.com/Tobias-Bucci/digitales_register',
              style: linkStyle,
              recognizer: _forkProject,
            ),
            TextSpan(text: tr('about.welcome.bodySuffix')),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('common.done')),
        ),
      ],
    );
  }
}
