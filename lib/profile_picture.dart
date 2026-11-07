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

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// The pictures of this session that are known to decode, by their address.
final Map<String, MemoryImage> _pictures = <String, MemoryImage>{};

MemoryImage? cachedProfilePicture(String url) => _pictures[url];

void cacheProfilePicture(String url, MemoryImage picture) {
  _pictures[url] = picture;
}

/// Forgets every picture. A picture belongs to the session that loaded it, and a
/// new one can replace an old one at the same address.
void forgetProfilePictures() {
  for (final picture in _pictures.values) {
    unawaited(picture.evict());
  }
  _pictures.clear();
}

/// Changes when it is worth loading a missing picture again at once.
final ValueNotifier<int> profilePictureRetries = ValueNotifier<int>(0);

/// Sends every avatar that lacks its picture back to the server, as the reason
/// of an earlier failure is gone: the app has signed in or is back online.
void retryProfilePictures() => profilePictureRetries.value++;

String? buildProfilePictureUrl({
  required String? baseUrl,
  required String? picture,
}) {
  final normalizedBaseUrl = baseUrl?.trim();
  final normalizedPicture = picture?.trim();
  if (normalizedBaseUrl == null || normalizedBaseUrl.isEmpty) {
    return null;
  }
  if (normalizedPicture == null || normalizedPicture.isEmpty) {
    return null;
  }

  return '$normalizedBaseUrl/v2/api/profile/picture&pictureUrl='
      '${Uri.encodeQueryComponent(normalizedPicture)}';
}
