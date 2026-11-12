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

import 'package:dr/container/network_protocol_container.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/ui/glass_page.dart';
import 'package:flutter/material.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

class NetworkProtocolPage extends StatelessWidget {
  const NetworkProtocolPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (ResponsiveNavigationScope.isActive(context)) {
      return GlassPage(
        header: GlassPageHeader(
          surfaceKey: const Key('network-protocol-app-header'),
          title: context.l10n.text('settings.advanced.networkProtocol'),
          floatingMaxWidth:
              glassHeaderFloatingWidth(MediaQuery.sizeOf(context).width),
        ),
        body: NetworkProtocolContainer(),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.text('settings.advanced.networkProtocol')),
        centerTitle: false,
      ),
      body: NetworkProtocolContainer(),
    );
  }
}
