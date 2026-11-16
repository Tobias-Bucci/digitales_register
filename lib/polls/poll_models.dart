import 'package:flutter/foundation.dart';

/// Poll types this app can show (issue #131). The server may run others; for
/// those the announcement stays a plain announcement with its web link.
/// `contract/check-client-sync.sh` of the server compares this list.
const knownServerPollTypes = <String>{
  'single_choice',
};

const _questionMaxChars = 120;
const _labelMaxChars = 200;
const _optionIdMaxChars = 36;
const _minOptions = 2;
const _maxOptions = 10;

final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
final _optionId = RegExp(r'^[A-Za-z0-9_-]{1,36}$');
final _timestamp = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$');

bool _isUnsafe(int rune) =>
    rune < 0x20 ||
    (rune >= 0x7F && rune <= 0x9F) ||
    rune == 0x200E ||
    rune == 0x200F ||
    (rune >= 0x202A && rune <= 0x202E) ||
    (rune >= 0x2066 && rune <= 0x2069);

/// One line of plain text, safe to show. Markup stays literal text.
String _clean(String value, int maxChars) {
  final text = String.fromCharCodes(
    value.replaceAll(RegExp(r'\s+'), ' ').runes.where((r) => !_isUnsafe(r)),
  ).trim();
  final runes = text.runes;
  return runes.length <= maxChars
      ? text
      : String.fromCharCodes(runes.take(maxChars)).trimRight();
}

DateTime? _time(Object? value) {
  if (value is! String || !_timestamp.hasMatch(value)) return null;
  return DateTime.tryParse(value)?.toUtc();
}

String _formatTime(DateTime value) =>
    '${value.toUtc().toIso8601String().split('.').first.replaceAll('Z', '')}Z';

@immutable
class ServerPollOption {
  const ServerPollOption({required this.id, required this.label});

  final String id;
  final String label;

  Map<String, Object?> toJson() => {'id': id, 'label': label};
}

/// The `poll` object of an announcement, of a type this app knows.
@immutable
class ServerPoll {
  const ServerPoll({
    required this.id,
    required this.type,
    required this.question,
    required this.options,
    required this.opensAt,
    required this.closesAt,
    required this.showResults,
  });

  /// Lower-case UUID of the poll, not of the announcement.
  final String id;
  final String type;
  final String question;
  final List<ServerPollOption> options;
  final DateTime opensAt;
  final DateTime closesAt;

  /// Whether voters may see the result.
  final bool showResults;

  bool isClosedAt(DateTime now) => !closesAt.isAfter(now);

  ServerPollOption? option(String? id) {
    for (final option in options) {
      if (option.id == id) return option;
    }
    return null;
  }

  /// Null for anything this app cannot show safely: a missing or broken
  /// field, an unknown [type], duplicate options. The announcement then
  /// stays a plain announcement with its web link. Unknown fields are
  /// ignored.
  static ServerPoll? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final type = json['type'];
    final question = json['question'];
    final options = json['options'];
    final showResults = json['show_results'];
    if (id is! String || !_uuid.hasMatch(id)) return null;
    if (type is! String || !knownServerPollTypes.contains(type)) return null;
    if (question is! String || showResults is! bool) return null;
    if (options is! List ||
        options.length < _minOptions ||
        options.length > _maxOptions) {
      return null;
    }
    final parsed = <ServerPollOption>[];
    final ids = <String>{};
    for (final option in options) {
      if (option is! Map) return null;
      final optionId = option['id'];
      final label = option['label'];
      if (optionId is! String ||
          optionId.length > _optionIdMaxChars ||
          !_optionId.hasMatch(optionId) ||
          label is! String) {
        return null;
      }
      final cleanLabel = _clean(label, _labelMaxChars);
      if (cleanLabel.isEmpty || !ids.add(optionId)) return null;
      parsed.add(ServerPollOption(id: optionId, label: cleanLabel));
    }
    final cleanQuestion = _clean(question, _questionMaxChars);
    final opensAt = _time(json['opens_at']);
    final closesAt = _time(json['closes_at']);
    if (cleanQuestion.isEmpty || opensAt == null || closesAt == null) {
      return null;
    }
    return ServerPoll(
      id: id.toLowerCase(),
      type: type,
      question: cleanQuestion,
      options: List.unmodifiable(parsed),
      opensAt: opensAt,
      closesAt: closesAt,
      showResults: showResults,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'type': type,
        'question': question,
        'options': [for (final option in options) option.toJson()],
        'opens_at': _formatTime(opensAt),
        'closes_at': _formatTime(closesAt),
        'show_results': showResults,
      };
}

/// Aggregated counts. Votes per device, not per person.
@immutable
class ServerPollResults {
  const ServerPollResults({required this.totalVotes, required this.votes});

  final int totalVotes;

  /// Votes per option id.
  final Map<String, int> votes;

  int votesFor(String optionId) => votes[optionId] ?? 0;

  /// Whole percent of [optionId]. Zero votes give zero, never NaN.
  int percentFor(String optionId) =>
      totalVotes <= 0 ? 0 : (votesFor(optionId) * 100 / totalVotes).round();

  static ServerPollResults? tryParse(Object? json) {
    if (json is! Map) return null;
    final total = json['total_votes'];
    final options = json['options'];
    if (total is! int || total < 0 || options is! List) return null;
    final votes = <String, int>{};
    for (final option in options) {
      if (option is! Map) return null;
      final id = option['id'];
      final count = option['votes'];
      if (id is! String || count is! int || count < 0) return null;
      votes[id] = count;
    }
    return ServerPollResults(totalVotes: total, votes: Map.unmodifiable(votes));
  }
}

/// `GET /api/v1/polls/{id}`.
@immutable
class ServerPollState {
  const ServerPollState({
    required this.poll,
    required this.open,
    required this.results,
  });

  final ServerPoll poll;

  /// Only `open` accepts votes; any other status means "cannot vote".
  final bool open;
  final ServerPollResults? results;

  static ServerPollState? tryParse(Object? json) {
    if (json is! Map || json['schema_version'] != 1) return null;
    final poll = ServerPoll.tryParse(json['poll']);
    final status = json['status'];
    if (poll == null || status is! String) return null;
    return ServerPollState(
      poll: poll,
      open: status == 'open',
      results: ServerPollResults.tryParse(json['results']),
    );
  }
}
