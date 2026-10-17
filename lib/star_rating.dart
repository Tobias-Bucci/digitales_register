import 'dart:convert';

/// Accept only nonnegative whole values. Never round or truncate a rating.
int? parseStarCount(Object? value) {
  final num? number = value is num
      ? value
      : value is String
          ? num.tryParse(value.trim())
          : null;
  if (number == null ||
      !number.isFinite ||
      number < 0 ||
      number > 9007199254740991 ||
      number != number.roundToDouble()) {
    return null;
  }
  return number.toInt();
}

int? parseStarScale(Object? value) {
  final count = parseStarCount(value);
  return count == null || count == 0 ? null : count;
}

/// Competence lists may also be JSON encoded, as supported by the API parsers.
List<Object?> parseCompetenceList(Object? value) {
  Object? decoded = value;
  if (value is String) {
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      return const [];
    }
  }
  return decoded is List ? List<Object?>.from(decoded) : const [];
}

/// Preserve support for individually JSON-encoded competence objects too.
Map parseCompetenceMap(Object? value) {
  Object? decoded = value;
  if (value is String) {
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      return const {};
    }
  }
  return decoded is Map ? decoded : const {};
}
