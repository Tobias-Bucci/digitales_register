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
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

class BuiltReduxGenerator extends Generator {
  @override
  Future<String> generate(LibraryReader library, BuildStep buildStep) async {
    final result = StringBuffer();
    var hasWrittenHeaders = false;
    for (final element in library.allElements) {
      if (_isReduxActions(element) && element is ClassElement) {
        if (!hasWrittenHeaders) {
          hasWrittenHeaders = true;
          result.writeln(_lintIgnores);
        }
        log.info('Generating action classes for ${element.name}');
        result.writeln(_generateActions(element));
      }
    }

    return result.toString();
  }
}

const _lintIgnores = """
// ignore_for_file: avoid_classes_with_only_static_members
// ignore_for_file: overridden_fields
// ignore_for_file: type_annotate_public_apis
""";

ActionsClass _actionsClassFromElement(ClassElement element) => ActionsClass(
      element.displayName,
      _actionsFromElement(element).toSet(),
      _composedActionClasses(element).toSet(),
      _actionsClassFromInheritedElements(element).toSet(),
    );

Iterable<ComposedActionClass> _composedActionClasses(ClassElement element) =>
    element.fields.where((f) => _isReduxActions(f.type.element!)).map(
          (f) => ComposedActionClass(
            f.displayName,
            f.type.element!.displayName,
          ),
        );

Iterable<Action> _actionsFromElement(ClassElement element) => element.fields
    .where(_isActionDispatcher)
    .map((field) => _fieldElementToAction(element, field));

Iterable<ActionsClass> _actionsClassFromInheritedElements(
        ClassElement element) =>
    element.allSupertypes
        .map((s) => s.element)
        .whereType<ClassElement>()
        .where(_isReduxActions)
        .map(_actionsClassFromElement);

Action _fieldElementToAction(ClassElement element, FieldElement field) =>
    Action('${element.displayName}-${field.displayName}', field.displayName,
        _fieldType(element, field));

// hack to return the generics for the action
// this is used so action whose payloads are of generated types
// will not result in dynamic
String _fieldType(ClassElement element, FieldElement field) {
  final type = field.type.getDisplayString(withNullability: true);
  if (type == "VoidActionDispatcher") {
    return "void";
  }
  return _getGenerics(type);
}

String _getGenerics(String type) {
  final start = type.indexOf('<');
  final end = type.lastIndexOf('>');
  if (start < 0 || end <= start) {
    return 'dynamic';
  }
  return type.substring(start + 1, end);
}

bool _isReduxActions(Element element) =>
    element is ClassElement && _hasSuperType(element, 'ReduxActions');

bool _isActionDispatcher(FieldElement element) =>
    element.type.getDisplayString(withNullability: false) ==
        'VoidActionDispatcher' ||
    element.type
        .getDisplayString(withNullability: false)
        .startsWith('ActionDispatcher<');

bool _hasSuperType(ClassElement classElement, String type) =>
    classElement.allSupertypes
        .any((interfaceType) => interfaceType.name == type) &&
    !classElement.displayName.startsWith('_\$');

String _generateActions(ClassElement element) {
  final actionClass = _actionsClassFromElement(element);
  return _generateDispatchersIfNeeded(element, actionClass) +
      _actionNamesClassTemplate(actionClass);
}

String _generateDispatchersIfNeeded(
        ClassElement element, ActionsClass actionsClass) =>
    element.constructors.length > 1
        ? _actionDispatcherClassTemplate(actionsClass)
        : '';

/*

  Action Dispatcher

*/

String _actionDispatcherClassTemplate(ActionsClass actionsClass) => '''
  class _\$${actionsClass.className} extends ${actionsClass.className}{
    factory _\$${actionsClass.className}() => _\$${actionsClass.className}._();
    _\$${actionsClass.className}._() : super._();

    ${_allActionDispatcherFieldsTemplate(actionsClass)}
    ${_allComposedActionClassesFieldsTemplate(actionsClass)}

    @override
    void setDispatcher(Dispatcher dispatcher) {
      ${_allActionDispatcherSetDispatchersTemplate(actionsClass)}
      ${_allComposedActionClassesSetDispatchersTemplate(actionsClass)}
    }
  }
''';

String _allActionDispatcherFieldsTemplate(ActionsClass actionsClass) =>
    actionsClass.allActions.fold(
        '', (comb, next) => '$comb\n${_actionDispatcherFieldTemplate(next)}');

String _allComposedActionClassesFieldsTemplate(ActionsClass actionsClass) =>
    actionsClass.allComposed.fold('',
        (comb, next) => '$comb\n${_composedActionClassesFieldTemplate(next)}');

String _actionDispatcherFieldTemplate(Action action) => action.type == "void"
    ? 'final ${action.fieldName} = VoidActionDispatcher(\'${action.actionName}\');'
    : 'final ${action.fieldName} = ActionDispatcher<${action.type}>(\'${action.actionName}\');';

String _composedActionClassesFieldTemplate(
        ComposedActionClass composedActionClass) =>
    'final ${composedActionClass.fieldName} = ${composedActionClass.type}();';

String _allActionDispatcherSetDispatchersTemplate(ActionsClass actionsClass) =>
    actionsClass.allActions.fold(
        '', (comb, next) => '$comb\n${_setDispatcheTemplate(next.fieldName)}');

String _allComposedActionClassesSetDispatchersTemplate(
        ActionsClass actionsClass) =>
    actionsClass.allComposed.fold(
        '', (comb, next) => '$comb\n${_setDispatcheTemplate(next.fieldName)}');

String _setDispatcheTemplate(String fieldName) =>
    '${fieldName}.setDispatcher(dispatcher);';

// /*

//   Action Names

// */

String _actionNamesClassTemplate(ActionsClass actionsClass) => '''
  class ${actionsClass.className}Names {
    ${_allActionNamesFieldsTemplate(actionsClass)}
  }
''';

String _allActionNamesFieldsTemplate(ActionsClass actionsClass) =>
    actionsClass.allActions
        .fold('', (comb, next) => '$comb\n${_actionNameTemplate(next)}');

String _actionNameTemplate(Action action) =>
    'static final ${action.fieldName} = ActionName<${action.type}>(\'${action.actionName}\');';

class ActionsClass {
  final String className;
  final Set<Action> actions;
  final Set<ComposedActionClass> composed;
  final Set<ActionsClass> inherited;
  ActionsClass(this.className, this.actions, this.composed, this.inherited);
  Set<Action> get allActions => Set<Action>.from(
        actions.toList()
          ..addAll(inherited.map((ac) => ac.actions).expand((a) => a)),
      );
  Set<ComposedActionClass> get allComposed => Set<ComposedActionClass>.from(
        composed.toList()
          ..addAll(inherited.map((ac) => ac.composed).expand((c) => c)),
      );

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ActionsClass && className == other.className;
  }

  @override
  int get hashCode => className.hashCode;
}

class Action {
  final String actionName;
  final String fieldName;
  final String type;
  Action(this.actionName, this.fieldName, this.type);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Action && fieldName == other.fieldName;
  }

  @override
  int get hashCode => fieldName.hashCode;
}

class ComposedActionClass {
  final String fieldName;
  final String type;
  ComposedActionClass(this.fieldName, this.type);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Action && fieldName == other.fieldName;
  }

  @override
  int get hashCode => fieldName.hashCode;
}
