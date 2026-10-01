// Copyright (C) 2021 Michael Debertol
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

import 'package:url_launcher/url_launcher.dart';

class Donate extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final darkMode = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
        appBar: AppBar(title: Text(context.l10n.text('donate.title'))),
        body: ListView(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 25.0, left: 10, right: 10),
              child: Card(
                clipBehavior: Clip.hardEdge,
                elevation: 10,
                child: ListTile(
                    title: Text(context.l10n.text('donate.coffee')),
                    subtitle: Text(context.l10n.text('donate.coffeeAmount')),
                    leading: Image.asset(darkMode
                        ? "assets/coffee-white.png"
                        : "assets/coffee-black.png"),
                    onTap: () {
                      launchUrl(
                        Uri.parse(
                          "https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=YBGW9QXH8UM3Q&source=url",
                        ),
                      );
                    }),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 15.0, left: 10, right: 10),
              child: Card(
                clipBehavior: Clip.hardEdge,
                elevation: 10,
                child: ListTile(
                    title: Text(context.l10n.text('donate.patron')),
                    subtitle: Text(context.l10n.text('donate.patronAmount')),
                    leading: Image.asset(darkMode
                        ? "assets/goenner-white.png"
                        : "assets/goenner-black.png"),
                    onTap: () {
                      launchUrl(
                        Uri.parse(
                          "https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=DFBK2QCD7EF6C&source=url",
                        ),
                      );
                    }),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 15.0, left: 10, right: 10),
              child: Card(
                clipBehavior: Clip.hardEdge,
                elevation: 10,
                child: ListTile(
                    title: Text(context.l10n.text('donate.friend')),
                    subtitle: Text(context.l10n.text('donate.friendAmount')),
                    leading: Image.asset(darkMode
                        ? "assets/herz-white.png"
                        : "assets/herz-black.png"),
                    onTap: () {
                      launchUrl(
                        Uri.parse(
                          "https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=5ZCCEN697H3W4&source=url",
                        ),
                      );
                    }),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 15.0, left: 10, right: 10),
              child: Card(
                clipBehavior: Clip.hardEdge,
                elevation: 10,
                child: ListTile(
                    title: Text(context.l10n.text('donate.custom')),
                    subtitle: Text(context.l10n.text('donate.website')),
                    leading: Image.asset(darkMode
                        ? "assets/Sparschwein-white.png"
                        : "assets/Sparschwein-black.png"),
                    onTap: () {
                      launchUrl(
                        Uri.parse(
                          "https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=6Z2Q5BDH9GLWS&source=url",
                        ),
                      );
                    }),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 45.0, left: 28, bottom: 10),
              child: Text(
                context.l10n.text('donate.secure'),
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700]),
              ),
            ),
            Row(
              children: <Widget>[
                GestureDetector(
                  onTap: () {
                    launchUrl(
                      Uri.parse(
                        'https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=FQTWZSRWSUXKN&source=url',
                      ),
                    );
                  },
                  child: Image.asset(
                    'assets/paypal.png', // On click should redirect to an URL
                    width: 180.0,
                    height: 60.0,
                    //Image.asset("assets/paypal.png", height: 60, width: 180,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 40.0, left: 10, right: 10),
              child: Card(
                clipBehavior: Clip.hardEdge,
                elevation: 10,
                child: ListTile(
                    title: Text(context.l10n.text('donate.thanks')),
                    subtitle: Text(context.l10n.text('donate.thanksBody')),
                    leading: Image.asset(darkMode
                        ? "assets/herz-white.png"
                        : "assets/herz-black.png"),
                    onTap: () {
                      launchUrl(
                        Uri.parse(
                          "https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=FQTWZSRWSUXKN&source=url",
                        ),
                      );
                    }),
              ),
            ),
          ],
        ));
  }
}
