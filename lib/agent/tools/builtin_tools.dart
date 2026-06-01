// lib/agent/tools/builtin_tools.dart
//
// Built-in tool implementations.
//
// All tools follow a fail-safe contract: they catch their own exceptions
// and return ToolResult.failure() rather than throwing.
//
// Tools included:
//   • SearchWebTool      — HTTP GET to a search-API endpoint (or mock)
//   • CalculateTool      — safe expression evaluator (no dart:mirrors)
//   • ReadFileTool       — reads a local text file
//   • WriteFileTool      — writes content to a local file
//   • CallApiTool        — HTTP GET/POST to an arbitrary URL
//   • ScheduleTaskTool   — registers a deferred callback
//   • BuiltinToolset     — convenience factory to register all six at once

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'package:consciousness_sim/agent/tools/tool_interface.dart';
import 'package:consciousness_sim/utils/logger.dart';

// ─────────────────────────────────────────────
// SearchWebTool
// ─────────────────────────────────────────────

/// Performs a web search and returns a summary of the top results.
///
/// In production, wire up a real search API (SerpAPI, Brave Search, DuckDuckGo
/// Instant Answers, etc.).  In testing/offline mode set [mockResults] to
/// return canned answers.
class SearchWebTool extends Tool {
  SearchWebTool({
    this.apiKey,
    this.searchEngineUrl = 'https://api.duckduckgo.com/',
    List<Map<String, String>>? mockResults,
    http.Client? client,
    ConsciousnessLogger? logger,
  })  : _mockResults = mockResults,
        _client = client ?? http.Client(),
        _logger = logger ?? ConsciousnessLogger('SearchWebTool');

  final String? apiKey;
  final String searchEngineUrl;
  final List<Map<String, String>>? _mockResults;
  final http.Client _client;
  final ConsciousnessLogger _logger;

  @override
  String get name => 'search_web';

  @override
  String get description =>
      'Search the internet for information about a topic or question.';

  @override
  Map<String, String> get inputSchema => {
        'query': 'The search query string.',
      };

  @override
  Future<ToolResult> run(Map<String, dynamic> input) async {
    final query = (input['query'] as String? ?? '').trim();
    if (query.isEmpty) {
      return ToolResult.failure(name, 'Input "query" must not be empty.');
    }

    _logger.info('Searching: "$query"');

    // Return mock results if provided (testing / offline)
    if (_mockResults != null) {
      final results = _mockResults!
          .map((r) => '• ${r["title"] ?? ""}: ${r["snippet"] ?? ""}')
          .join('\n');
      return ToolResult.success(name, results,
          metadata: {'query': query, 'source': 'mock'});
    }

    // Real DuckDuckGo Instant Answers (JSON API, no key needed)
    try {
      final uri = Uri.parse(searchEngineUrl).replace(queryParameters: {
        'q': query,
        'format': 'json',
        'no_html': '1',
        'skip_disambig': '1',
      });

      final response = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return ToolResult.failure(
          name,
          'Search API returned HTTP ${response.statusCode}',
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final abstract_ = (json['AbstractText'] as String? ?? '').trim();
      final relatedTopics = (json['RelatedTopics'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .take(3)
          .map((t) => (t['Text'] as String? ?? '').trim())
          .where((t) => t.isNotEmpty)
          .join('\n');

      final output = [
        if (abstract_.isNotEmpty) 'Summary: $abstract_',
        if (relatedTopics.isNotEmpty) 'Related:\n$relatedTopics',
      ].join('\n\n');

      return ToolResult.success(
        name,
        output.isEmpty ? 'No results found for "$query".' : output,
        metadata: {'query': query, 'source': 'duckduckgo'},
      );
    } catch (e) {
      _logger.warning('Search failed: $e');
      return ToolResult.failure(name, 'Search error: $e');
    }
  }
}

// ─────────────────────────────────────────────
// CalculateTool
// ─────────────────────────────────────────────

/// Evaluates a mathematical expression.
///
/// Supports: +, -, *, /, %, ^, parentheses, sqrt(), abs(), floor(), ceil(),
/// pi, e, and standard integer/float literals.
///
/// Does NOT use `dart:mirrors` or `eval` — uses a recursive descent parser
/// so it is safe to run in AOT-compiled Flutter apps.
class CalculateTool extends Tool {
  const CalculateTool();

  @override
  String get name => 'calculate';

  @override
  String get description => 'Evaluate a mathematical expression and return the result.';

  @override
  Map<String, String> get inputSchema => {
        'expression': 'The math expression to evaluate, e.g. "2 * (3 + 4)".',
      };

  @override
  Future<ToolResult> run(Map<String, dynamic> input) async {
    final expr = (input['expression'] as String? ?? '').trim();
    if (expr.isEmpty) {
      return ToolResult.failure(name, 'Expression must not be empty.');
    }

    try {
      final result = _MathParser(expr).parse();
      if (result.isInfinite || result.isNaN) {
        return ToolResult.failure(name,
            'Calculation error: result is ${result.isInfinite ? "Infinity (division by zero?)" : "NaN"}');
      }
      return ToolResult.success(name, result,
          metadata: {'expression': expr});
    } catch (e) {
      return ToolResult.failure(name, 'Calculation error: $e');
    }
  }
}

// ─────────────────────────────────────────────
// ReadFileTool
// ─────────────────────────────────────────────

/// Reads a local file and returns its text content.
class ReadFileTool extends Tool {
  ReadFileTool({this.allowedDirectory, ConsciousnessLogger? logger})
      : _logger = logger ?? ConsciousnessLogger('ReadFileTool');

  /// If set, only files within this directory may be read.
  final String? allowedDirectory;
  final ConsciousnessLogger _logger;

  @override
  String get name => 'read_file';

  @override
  String get description => 'Read the text contents of a local file.';

  @override
  Map<String, String> get inputSchema => {
        'path': 'Absolute or relative path to the file.',
      };

  @override
  Future<ToolResult> run(Map<String, dynamic> input) async {
    final path = (input['path'] as String? ?? '').trim();
    if (path.isEmpty) {
      return ToolResult.failure(name, 'Input "path" must not be empty.');
    }

    // Optional sandboxing
    if (allowedDirectory != null &&
        !path.startsWith(allowedDirectory!)) {
      return ToolResult.failure(
        name,
        'Access denied: path must be within "$allowedDirectory".',
      );
    }

    _logger.info('Reading file: $path');

    try {
      final file = File(path);
      if (!await file.exists()) {
        return ToolResult.failure(name, 'File not found: $path');
      }
      final content = await file.readAsString();
      return ToolResult.success(name, content,
          metadata: {
            'path': path,
            'size_bytes': content.length,
          });
    } catch (e) {
      return ToolResult.failure(name, 'File read error: $e');
    }
  }
}

// ─────────────────────────────────────────────
// WriteFileTool
// ─────────────────────────────────────────────

/// Writes text content to a local file (creates directories if needed).
class WriteFileTool extends Tool {
  WriteFileTool({this.allowedDirectory, ConsciousnessLogger? logger})
      : _logger = logger ?? ConsciousnessLogger('WriteFileTool');

  final String? allowedDirectory;
  final ConsciousnessLogger _logger;

  @override
  String get name => 'write_file';

  @override
  String get description => 'Write text content to a local file (creates parent dirs).';

  @override
  Map<String, String> get inputSchema => {
        'path': 'Absolute or relative path to the file.',
        'content': 'Text content to write.',
      };

  @override
  bool get isIdempotent => false;

  @override
  Future<ToolResult> run(Map<String, dynamic> input) async {
    final path = (input['path'] as String? ?? '').trim();
    final content = (input['content'] as String? ?? '');

    if (path.isEmpty) {
      return ToolResult.failure(name, 'Input "path" must not be empty.');
    }

    if (allowedDirectory != null && !path.startsWith(allowedDirectory!)) {
      return ToolResult.failure(
          name, 'Access denied: path must be within "$allowedDirectory".');
    }

    _logger.info('Writing file: $path (${content.length} chars)');

    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
      return ToolResult.success(name, 'Written ${content.length} bytes to $path',
          metadata: {'path': path, 'bytes': content.length});
    } catch (e) {
      return ToolResult.failure(name, 'File write error: $e');
    }
  }
}

// ─────────────────────────────────────────────
// CallApiTool
// ─────────────────────────────────────────────

/// Makes an HTTP GET or POST request to an external API.
class CallApiTool extends Tool {
  CallApiTool({
    http.Client? client,
    ConsciousnessLogger? logger,
  })  : _client = client ?? http.Client(),
        _logger = logger ?? ConsciousnessLogger('CallApiTool');

  final http.Client _client;
  final ConsciousnessLogger _logger;

  @override
  String get name => 'call_api';

  @override
  String get description =>
      'Make an HTTP GET or POST request to an external API endpoint.';

  @override
  Map<String, String> get inputSchema => {
        'url': 'The fully-qualified URL to call.',
      };

  @override
  Future<ToolResult> run(Map<String, dynamic> input) async {
    final url = (input['url'] as String? ?? '').trim();
    final method =
        ((input['method'] as String?) ?? 'GET').toUpperCase();
    final headers = (input['headers'] as Map<String, dynamic>? ?? {})
        .map((k, v) => MapEntry(k, v.toString()));
    final body = input['body'] as String?;

    if (url.isEmpty) {
      return ToolResult.failure(name, 'Input "url" must not be empty.');
    }

    _logger.info('$method $url');

    try {
      final uri = Uri.parse(url);
      http.Response response;

      if (method == 'POST') {
        response = await _client
            .post(uri,
                headers: {
                  'Content-Type': 'application/json',
                  ...headers,
                },
                body: body)
            .timeout(const Duration(seconds: 15));
      } else {
        response = await _client
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 15));
      }

      if (response.statusCode >= 400) {
        return ToolResult.failure(
          name,
          'API returned HTTP ${response.statusCode}: ${response.body.substring(0, math.min(200, response.body.length))}',
        );
      }

      return ToolResult.success(name, response.body,
          metadata: {
            'url': url,
            'status': response.statusCode,
            'content_type': response.headers['content-type'] ?? '',
          });
    } catch (e) {
      return ToolResult.failure(name, 'API call error: $e');
    }
  }
}

// ─────────────────────────────────────────────
// ScheduleTaskTool
// ─────────────────────────────────────────────

/// Schedules a named task to run after a specified delay.
///
/// The tool stores the scheduled task in memory and fires a callback
/// (if provided) when the delay elapses.  It does NOT create a real OS
/// scheduler entry — use a cron library for persistent scheduling.
class ScheduleTaskTool extends Tool {
  ScheduleTaskTool({
    this.onTaskDue,
    ConsciousnessLogger? logger,
  }) : _logger = logger ?? ConsciousnessLogger('ScheduleTaskTool');

  /// Optional callback fired when a scheduled task becomes due.
  final void Function(String taskName, DateTime dueAt)? onTaskDue;

  final ConsciousnessLogger _logger;
  final Map<String, DateTime> _scheduled = {};

  @override
  String get name => 'schedule_task';

  @override
  String get description =>
      'Schedule a named task to run after a given delay in seconds.';

  @override
  Map<String, String> get inputSchema => {
        'task_name': 'Descriptive name for the task.',
        'delay_seconds': 'Number of seconds to wait before the task fires.',
      };

  @override
  Future<ToolResult> run(Map<String, dynamic> input) async {
    final taskName = (input['task_name'] as String? ?? '').trim();
    final delayS = (input['delay_seconds'] as num?)?.toInt() ?? 0;

    if (taskName.isEmpty) {
      return ToolResult.failure(name, '"task_name" must not be empty.');
    }

    final dueAt = DateTime.now().add(Duration(seconds: delayS));
    _scheduled[taskName] = dueAt;

    _logger.info('Scheduled "$taskName" in ${delayS}s (due: $dueAt)');

    if (delayS >= 0) {
      Future<void>.delayed(Duration(seconds: delayS), () {
        onTaskDue?.call(taskName, dueAt);
        _logger.info('Task due: "$taskName"');
      });
    }

    return ToolResult.success(
      name,
      'Task "$taskName" scheduled for $dueAt (in ${delayS}s).',
      metadata: {'task_name': taskName, 'due_at': dueAt.toIso8601String()},
    );
  }

  /// Returns all currently scheduled tasks.
  Map<String, DateTime> get scheduled => Map.unmodifiable(_scheduled);
}

// ─────────────────────────────────────────────
// BuiltinToolset
// ─────────────────────────────────────────────

/// Convenience class that instantiates and registers all built-in tools.
///
/// ### Usage
/// ```dart
/// final registry = ToolRegistry();
/// BuiltinToolset.registerAll(registry);
/// ```
class BuiltinToolset {
  BuiltinToolset._();

  /// Registers all built-in tools on [registry] with default settings.
  static void registerAll(
    ToolRegistry registry, {
    String? allowedDirectory,
    List<Map<String, String>>? mockSearchResults,
    void Function(String, DateTime)? onTaskScheduled,
    ConsciousnessLogger? logger,
  }) {
    registry.registerAll([
      SearchWebTool(mockResults: mockSearchResults, logger: logger),
      const CalculateTool(),
      ReadFileTool(allowedDirectory: allowedDirectory, logger: logger),
      WriteFileTool(allowedDirectory: allowedDirectory, logger: logger),
      CallApiTool(logger: logger),
      ScheduleTaskTool(onTaskDue: onTaskScheduled, logger: logger),
    ]);
  }
}

// ─────────────────────────────────────────────
// _MathParser (private) — safe expression evaluator
// ─────────────────────────────────────────────

/// Recursive-descent parser for simple arithmetic expressions.
///
/// Grammar:
///   expr   := term (('+' | '-') term)*
///   term   := factor (('*' | '/' | '%') factor)*
///   factor := unary ('^' factor)?
///   unary  := '-' unary | primary
///   primary := NUMBER | 'pi' | 'e' | FUNC '(' expr ')' | '(' expr ')'
class _MathParser {
  _MathParser(String input) : _input = input.replaceAll(' ', '');
  final String _input;
  int _pos = 0;

  double parse() {
    final result = _expr();
    if (_pos != _input.length) {
      throw ArgumentError(
          'Unexpected character "${_input[_pos]}" at position $_pos');
    }
    return result;
  }

  double _expr() {
    var left = _term();
    while (_pos < _input.length &&
        (_input[_pos] == '+' || _input[_pos] == '-')) {
      final op = _input[_pos++];
      final right = _term();
      left = op == '+' ? left + right : left - right;
    }
    return left;
  }

  double _term() {
    var left = _factor();
    while (_pos < _input.length &&
        (_input[_pos] == '*' || _input[_pos] == '/' || _input[_pos] == '%')) {
      final op = _input[_pos++];
      final right = _factor();
      if (op == '*') left *= right;
      else if (op == '/') left /= right;
      else left = left % right;
    }
    return left;
  }

  double _factor() {
    var base = _unary();
    if (_pos < _input.length && _input[_pos] == '^') {
      _pos++;
      final exp = _factor(); // right-associative
      base = math.pow(base, exp).toDouble();
    }
    return base;
  }

  double _unary() {
    if (_pos < _input.length && _input[_pos] == '-') {
      _pos++;
      return -_unary();
    }
    return _primary();
  }

  double _primary() {
    // Parenthesised sub-expression
    if (_pos < _input.length && _input[_pos] == '(') {
      _pos++;
      final val = _expr();
      _expect(')');
      return val;
    }

    // Named constants
    if (_match('pi')) return math.pi;
    if (_match('e')) return math.e;

    // Functions
    if (_matchFunc('sqrt')) return math.sqrt(_funcArg());
    if (_matchFunc('abs')) return _funcArg().abs();
    if (_matchFunc('floor')) return _funcArg().floorToDouble();
    if (_matchFunc('ceil')) return _funcArg().ceilToDouble();
    if (_matchFunc('sin')) return math.sin(_funcArg());
    if (_matchFunc('cos')) return math.cos(_funcArg());
    if (_matchFunc('tan')) return math.tan(_funcArg());
    if (_matchFunc('log')) return math.log(_funcArg());

    // Number
    return _number();
  }

  bool _match(String keyword) {
    if (_input.length >= _pos + keyword.length &&
        _input.substring(_pos, _pos + keyword.length) == keyword) {
      _pos += keyword.length;
      return true;
    }
    return false;
  }

  bool _matchFunc(String funcName) {
    final end = _pos + funcName.length;
    if (_input.length > end &&
        _input.substring(_pos, end) == funcName &&
        _input[end] == '(') {
      _pos = end;
      return true;
    }
    return false;
  }

  double _funcArg() {
    _expect('(');
    final val = _expr();
    _expect(')');
    return val;
  }

  void _expect(String char) {
    if (_pos >= _input.length || _input[_pos] != char) {
      throw ArgumentError('Expected "$char" at position $_pos');
    }
    _pos++;
  }

  double _number() {
    final start = _pos;
    while (_pos < _input.length &&
        (RegExp(r'[0-9.]').hasMatch(_input[_pos]))) {
      _pos++;
    }
    if (_pos == start) {
      throw ArgumentError(
          'Expected number at position $_pos, got '
          '"${_pos < _input.length ? _input[_pos] : "EOF"}"');
    }
    return double.parse(_input.substring(start, _pos));
  }
}
