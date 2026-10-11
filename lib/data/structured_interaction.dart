import 'dart:convert';

import 'models.dart';

/// A question embedded in a clarification request.
///
/// Studio's current clarification contract is a single string question. Some
/// agents put a Python-style list of questions in that string, so this model
/// deliberately accepts both the official shape and that compatibility form.
class StructuredQuestion {
  const StructuredQuestion({
    required this.id,
    required this.question,
    required this.choices,
    required this.multiSelect,
  });

  final String id;
  final String question;
  final List<StructuredChoice> choices;
  final bool multiSelect;

  bool get isOpen => choices.isEmpty;
}

class StructuredChoice {
  const StructuredChoice({
    required this.value,
    required this.label,
    required this.recommended,
  });

  final String value;
  final String label;
  final bool recommended;
}

class StructuredQuestionSet {
  const StructuredQuestionSet(this.questions);

  final List<StructuredQuestion> questions;

  bool get isEmpty => questions.isEmpty;

  /// Returns the wire-compatible response string for clarify.respond.
  ///
  /// The server currently accepts a string, so the structured answers are
  /// encoded as JSON inside that field. This preserves all qids and supports
  /// multi-select without changing the existing Socket.IO contract.
  String encodeResponses(Map<String, dynamic> answers) => jsonEncode({
    'responses': [
      for (final question in questions)
        if (answers.containsKey(question.id))
          {
            'qid': question.id,
            if (question.multiSelect)
              'answers': asList(answers[question.id]).map(text).toList()
            else
              'answer': text(answers[question.id]),
          },
    ],
  });

  static StructuredQuestionSet? parse(dynamic value) {
    final raw = _decodeQuestionList(value);
    if (raw == null || raw.isEmpty) return null;
    final questions = <StructuredQuestion>[];
    for (final item in raw) {
      final map = asMap(item);
      final id = text(map['qid'] ?? map['id']).trim();
      final question = text(map['question']).trim();
      if (id.isEmpty || question.isEmpty) return null;
      final values = asList(map['choices']);
      final offered = asList(map['choices_offered']);
      final choices = <StructuredChoice>[];
      for (var index = 0; index < values.length; index++) {
        final value = text(values[index]).trim();
        if (value.isEmpty) continue;
        final offeredLabel = index < offered.length
            ? text(offered[index]).trim()
            : value;
        final label = offeredLabel.isEmpty ? value : offeredLabel;
        choices.add(
          StructuredChoice(
            value: value,
            label: _cleanRecommendation(label),
            recommended: _isRecommended(value) || _isRecommended(label),
          ),
        );
      }
      questions.add(
        StructuredQuestion(
          id: id,
          question: question,
          choices: List.unmodifiable(choices),
          multiSelect: flag(map['multi_select'] ?? map['multiSelect']),
        ),
      );
    }
    return StructuredQuestionSet(List.unmodifiable(questions));
  }
}

List<dynamic>? _decodeQuestionList(dynamic value) {
  if (value is List) return value;
  if (value is Map) {
    final nested = value['questions'] ?? value['items'];
    return _decodeQuestionList(nested);
  }
  if (value is! String) return null;
  final source = value.trim();
  if (source.isEmpty || !source.startsWith('[')) return null;
  try {
    final decoded = jsonDecode(source);
    if (decoded is List) return decoded;
  } on FormatException {
    // The agent may have emitted Python repr syntax. Parse that small literal
    // subset instead of doing unsafe string replacements.
  }
  try {
    final decoded = _PythonLiteralParser(source).parse();
    return decoded is List ? decoded : null;
  } on FormatException {
    return null;
  }
}

bool _isRecommended(String value) => RegExp(
  r'\(recommended\)|\(推荐\)|（recommended）|（推荐）',
  caseSensitive: false,
).hasMatch(value);

String _cleanRecommendation(String value) => value
    .replaceAll(RegExp(r'\s*\(recommended\)', caseSensitive: false), '')
    .replaceAll(RegExp(r'\s*\(推荐\)'), '')
    .replaceAll(RegExp(r'\s*（recommended）', caseSensitive: false), '')
    .replaceAll(RegExp(r'\s*（推荐）'), '')
    .trim();

/// Parser for the list/dict/string/bool/None subset used by Python repr.
class _PythonLiteralParser {
  _PythonLiteralParser(this.source);
  final String source;
  var index = 0;

  dynamic parse() {
    final value = _value();
    _space();
    if (index != source.length) throw const FormatException('trailing input');
    return value;
  }

  dynamic _value() {
    _space();
    if (index >= source.length) throw const FormatException('missing value');
    return switch (source[index]) {
      '[' => _list(),
      '{' => _map(),
      '\'' || '"' => _string(),
      _ => _atom(),
    };
  }

  List<dynamic> _list() {
    index++;
    final result = <dynamic>[];
    _space();
    if (_take(']')) return result;
    while (true) {
      result.add(_value());
      _space();
      if (_take(']')) return result;
      if (!_take(',')) throw const FormatException('expected comma');
      _space();
      if (_take(']')) return result;
    }
  }

  Map<String, dynamic> _map() {
    index++;
    final result = <String, dynamic>{};
    _space();
    if (_take('}')) return result;
    while (true) {
      final key = _value();
      if (key is! String) throw const FormatException('map key');
      _space();
      if (!_take(':')) throw const FormatException('expected colon');
      result[key] = _value();
      _space();
      if (_take('}')) return result;
      if (!_take(',')) throw const FormatException('expected comma');
      _space();
      if (_take('}')) return result;
    }
  }

  String _string() {
    final quote = source[index++];
    final result = StringBuffer();
    while (index < source.length) {
      final char = source[index++];
      if (char == quote) return result.toString();
      if (char != '\\') {
        result.write(char);
        continue;
      }
      if (index >= source.length) throw const FormatException('escape');
      final escaped = source[index++];
      result.write(switch (escaped) {
        'n' => '\n',
        'r' => '\r',
        't' => '\t',
        'b' => '\b',
        'f' => '\f',
        '\\' => '\\',
        '\'' => '\'',
        '"' => '"',
        _ => escaped,
      });
    }
    throw const FormatException('unterminated string');
  }

  dynamic _atom() {
    final start = index;
    while (index < source.length && !' ,]}\n\r\t'.contains(source[index])) {
      index++;
    }
    final atom = source.substring(start, index);
    return switch (atom) {
      'None' || 'null' => null,
      'True' || 'true' => true,
      'False' || 'false' => false,
      _ => num.tryParse(atom) ?? (throw const FormatException('atom')),
    };
  }

  void _space() {
    while (index < source.length && ' \n\r\t'.contains(source[index])) {
      index++;
    }
  }

  bool _take(String char) {
    if (index < source.length && source[index] == char) {
      index++;
      return true;
    }
    return false;
  }
}
