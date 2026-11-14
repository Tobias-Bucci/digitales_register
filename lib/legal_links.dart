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

import 'package:url_launcher/url_launcher.dart';

/// The app's privacy policy (GitHub Pages). The store listings link the same
/// addresses, so they must keep working.
const privacyPolicyUrl =
    'https://tobias-bucci.github.io/privacy-policy-digitales_register/';

/// How to delete the account and the data, for the stores' deletion links.
const deleteAccountUrl =
    'https://tobias-bucci.github.io/privacy-policy-digitales_register/delete-account.html';

/// Opens [url] outside the app: in the external browser, or in a new tab of
/// the web app.
Future<bool> openLegalLink(String url) => launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
