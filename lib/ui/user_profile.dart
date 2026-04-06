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
import 'package:dr/ui/profile_avatar.dart';
import 'package:flutter/material.dart';

class UserProfile extends StatelessWidget {
  final String name, username, role;
  final String? imageUrl;
  final VoidCallback? onUploadProfilePicture;
  final bool uploadInProgress;
  final bool uploadEnabled;

  const UserProfile({
    super.key,
    required this.name,
    required this.username,
    required this.role,
    this.imageUrl,
    this.onUploadProfilePicture,
    this.uploadInProgress = false,
    this.uploadEnabled = true,
  });
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: <Widget>[
            ProfileAvatar(
              imageUrl: imageUrl,
              size: 104,
            ),
            const SizedBox(height: 16),
            Text(
              name,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text("$username · $role"),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: uploadEnabled && !uploadInProgress
                  ? onUploadProfilePicture
                  : null,
              icon: uploadInProgress
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_rounded),
              label: Text(
                uploadInProgress
                    ? context.t('profile.uploadingPicture')
                    : context.t('profile.uploadPicture'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
