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

import 'package:dr/account_scope.dart';
import 'package:dr/school_notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the same school written differently is one server', () {
    expect(
      AccountScope('https://School.DigitalesRegister.it/', 'max'),
      AccountScope('https://school.digitalesregister.it', 'max'),
    );
  });

  test('another school or another user is another scope', () {
    final scope = AccountScope('https://a.example.org', 'max');
    expect(scope, isNot(AccountScope('https://b.example.org', 'max')));
    expect(scope, isNot(AccountScope('https://a.example.org', 'anna')));
  });

  test('user names are compared exactly', () {
    expect(
      AccountScope('https://a.example.org', 'Max'),
      isNot(AccountScope('https://a.example.org', 'max')),
    );
  });

  test('an unknown server or user is a scope of its own', () {
    expect(AccountScope(null, null), AccountScope('', null));
    expect(AccountScope('https://a.example.org', null),
        isNot(AccountScope('https://a.example.org', 'max')));
  });

  test('the text form never contains the user name', () {
    expect(AccountScope('https://a.example.org', 'secret-user').toString(),
        isNot(contains('secret-user')));
  });
  group('fileId', () {
    test('is 32 hex digits and the same for every spelling of the server', () {
      final id = AccountScope('https://School.example.org/', 'max').fileId;
      expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(AccountScope('https://school.example.org', 'max').fileId, id);
    });

    test('differs between users, schools and user name spellings', () {
      final ids = {
        AccountScope('https://a.example.org', 'max').fileId,
        AccountScope('https://a.example.org', 'Max').fileId,
        AccountScope('https://a.example.org', 'anna').fileId,
        AccountScope('https://b.example.org', 'max').fileId,
        AccountScope('https://a.example.org', null).fileId,
        AccountScope.demo().fileId,
      };
      expect(ids, hasLength(6));
    });

    test('does not run server and user together', () {
      // Without separators these two would hash the same text.
      expect(
        AccountScope('https://a.example.org', 'x').fileId,
        isNot(AccountScope('https://a.example.orgx', '').fileId),
      );
    });

    test('is stable: it names folders and keys that outlive an update', () {
      expect(AccountScope('https://school.example.org', 'max').fileId,
          '0e6c61c2f9737d7e3518862a7f1f59a5');
    });

    test('contains neither school nor user name', () {
      final id = AccountScope('https://school.example.org', 'maxmustermann')
          .fileId;
      expect(id, isNot(contains('school')));
      expect(id, isNot(contains('maxmustermann')));
    });

    test('the demo account is not an account of any school', () {
      expect(AccountScope.demo().server, isEmpty);
      expect(AccountScope.demo(), isNot(AccountScope('', 'other')));
      expect(AccountScope.demo(), AccountScope(null, 'demo'));
    });
  });

  test('notification keys tell servers apart exactly like scopes do', () {
    final service = SchoolNotificationService();
    expect(
      service.accountKey('https://School.Example.org/', 'max'),
      service.accountKey('https://school.example.org', 'max'),
    );
    expect(
      service.accountKey('https://school.example.org', 'Max'),
      isNot(service.accountKey('https://school.example.org', 'max')),
    );
    expect(canonicalSchoolServer('https://School.Example.org//'),
        'https://school.example.org');
  });
}
