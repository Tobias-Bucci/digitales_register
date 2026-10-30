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
}
