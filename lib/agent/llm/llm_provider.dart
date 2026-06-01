// lib/agent/llm/llm_provider.dart
//
// LLMProvider — abstract interface + built-in implementations.
//
// The framework is provider-agnostic: any LLM (OpenAI, Gemini, Ollama,
// local Llama, mock) can be plugged in by implementing [LLMProvider].
//
// Bundled implementations:
//   • [MockLLMProvider]   — deterministic rule-based mock for testing
//   • [HttpLLMProvider]   — thin HTTP wrapper for any OpenAI-compatible API
//   • [EchoLLMProvider]   — echoes the prompt back (useful for debugging)

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:consciousness_sim/utils/logger.dart';

// ─────────────────────────────────────────────
// LLMMessage
// ─────────────────────────────────────────────

/// A single message in an LLM conversation.
class LLMMessage {
  const LLMMessage({required this.role, required this.content});

  /// Role identifier: 'system', 'user', or 'assistant'.
  final String role;

  /// The text content of this message.
  final String content;

  Map<String, String> toJson() => {'role': role, 'content': content};

  @override
  String toString() => '[$role]: ${_trunc(content)}';

  String _trunc(String s, [int n = 80]) =>
      s.length > n ? '${s.substring(0, n - 3)}...' : s;
}

// ─────────────────────────────────────────────
// LLMRequest
// ─────────────────────────────────────────────

/// A fully-assembled request to send to an [LLMProvider].
class LLMRequest {
  const LLMRequest({
    required this.messages,
    this.maxTokens = 1024,
    this.temperature = 0.7,
    this.stopSequences = const [],
    this.model,
  });

  final List<LLMMessage> messages;
  final int maxTokens;

  /// Sampling temperature (0.0 = deterministic, 1.0 = creative).
  final double temperature;

  final List<String> stopSequences;

  /// Optional model override (e.g. 'gpt-4o', 'llama3').
  final String? model;

  @override
  String toString() =>
      'LLMRequest(messages: ${messages.length}, '
      'maxTokens: $maxTokens, temp: $temperature)';
}

// ─────────────────────────────────────────────
// LLMResponse
// ─────────────────────────────────────────────

/// The response returned by an [LLMProvider].
class LLMResponse {
  const LLMResponse({
    required this.text,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.model,
    this.finishReason,
  });

  /// The generated text.
  final String text;

  /// Tokens consumed by the prompt (approximated for non-OpenAI providers).
  final int promptTokens;

  /// Tokens in the completion.
  final int completionTokens;

  /// Model that generated this response.
  final String? model;

  /// Why generation stopped ('stop', 'length', 'tool_calls', etc.).
  final String? finishReason;

  /// Total tokens used.
  int get totalTokens => promptTokens + completionTokens;

  @override
  String toString() =>
      'LLMResponse(tokens: $totalTokens, '
      'finish: $finishReason, '
      'text: "${_trunc(text)}")';

  String _trunc(String s, [int n = 80]) =>
      s.length > n ? '${s.substring(0, n - 3)}...' : s;
}

// ─────────────────────────────────────────────
// LLMProvider (abstract)
// ─────────────────────────────────────────────

/// Abstract interface for any large-language-model back-end.
///
/// ### Implementing a custom provider
/// ```dart
/// class MyProvider implements LLMProvider {
///   @override
///   String get name => 'my-llm';
///
///   @override
///   Future<LLMResponse> complete(LLMRequest request) async {
///     // call your model
///   }
/// }
/// ```
abstract class LLMProvider {
  const LLMProvider();

  /// Human-readable name of this provider/model.
  String get name;

  /// Sends [request] to the LLM and returns its response.
  Future<LLMResponse> complete(LLMRequest request);

  /// Whether this provider supports streaming.
  bool get supportsStreaming => false;

  /// Stream of tokens (only valid when [supportsStreaming] is true).
  Stream<String> stream(LLMRequest request) async* {
    final response = await complete(request);
    yield response.text;
  }
}

// ─────────────────────────────────────────────
// EchoLLMProvider
// ─────────────────────────────────────────────

/// Echoes the last user message back verbatim.
///
/// Useful for pipeline smoke-testing and debugging prompt construction.
class EchoLLMProvider extends LLMProvider {
  const EchoLLMProvider();

  @override
  String get name => 'echo';

  @override
  Future<LLMResponse> complete(LLMRequest request) async {
    final last = request.messages.lastWhere(
      (m) => m.role == 'user',
      orElse: () => const LLMMessage(role: 'user', content: '(empty)'),
    );
    return LLMResponse(
      text: last.content,
      promptTokens: last.content.length ~/ 4,
      completionTokens: last.content.length ~/ 4,
      model: name,
      finishReason: 'echo',
    );
  }
}

// ─────────────────────────────────────────────
// MockLLMProvider
// ─────────────────────────────────────────────

/// Deterministic mock LLM for unit tests.
///
/// Responds based on keyword matching in the prompt:
///   - Detects JSON tool-call intent and returns structured JSON.
///   - Detects "complete" / "done" keywords and returns completion signal.
///   - Falls back to a canned reasoning response.
///
/// You can also supply a [responseQueue] to return pre-canned strings in
/// order — useful for scripting multi-step test scenarios.
class MockLLMProvider extends LLMProvider {
  /// Creates a [MockLLMProvider].
  ///
  /// - [responses] (alias for [responseQueue]) — ordered list of canned
  ///   response strings served one per call, then cycled.
  /// - [responseQueue] — same as [responses]; [responses] takes precedence
  ///   when both are supplied.
  /// - [name] — optional display name (defaults to `'mock'`).
  /// - [defaultResponse] — fallback string when the queue is exhausted and
  ///   no keyword heuristic matches.
  MockLLMProvider({
    List<String>? responses,
    List<String>? responseQueue,
    String? name,
    this.defaultResponse,
  })  : _responses = List<String>.unmodifiable(
            (responses ?? responseQueue) ?? const <String>[]),
        _name = name ?? 'mock';

  /// Immutable original response list — used for cycling once exhausted.
  final List<String> _responses;
  final String _name;

  /// Optional fixed response to return when the queue is exhausted and no
  /// responses were provided.
  final String? defaultResponse;

  int _callCount = 0;
  int _responseIndex = 0;

  /// Total number of times [complete] has been called.
  int get callCount => _callCount;

  @override
  String get name => _name;

  @override
  Future<LLMResponse> complete(LLMRequest request) async {
    _callCount++;
    await Future<void>.delayed(const Duration(milliseconds: 10)); // simulate latency

    // If a response list was provided, serve from it in order then cycle.
    if (_responses.isNotEmpty) {
      final text = _responses[_responseIndex % _responses.length];
      _responseIndex++;
      return LLMResponse(
        text: text,
        model: name,
        finishReason: 'stop',
        promptTokens: 100,
        completionTokens: 50,
      );
    }

    final prompt = request.messages.map((m) => m.content).join('\n').toLowerCase();

    // Heuristic: if prompt contains explicit tool request keywords
    if (prompt.contains('search') || prompt.contains('web')) {
      return _toolResponse('search_web', {'query': _extractQuery(prompt, 'search')});
    }
    if (prompt.contains('calculate') || prompt.contains('compute')) {
      return _toolResponse('calculate', {'expression': '2 + 2'});
    }
    if (prompt.contains('read_file') || prompt.contains('read file')) {
      return _toolResponse('read_file', {'path': 'data.txt'});
    }
    if (prompt.contains('write_file') || prompt.contains('write file')) {
      return _toolResponse('write_file', {'path': 'output.txt', 'content': 'result'});
    }
    if (prompt.contains('call_api') || prompt.contains('api call')) {
      return _toolResponse('call_api', {'url': 'https://example.com/api'});
    }

    // Detect completion
    if (prompt.contains('goal achieved') ||
        prompt.contains('task complete') ||
        prompt.contains('done')) {
      return LLMResponse(
        text: '{"action":"complete","reason":"Goal has been achieved based on available information."}',
        model: name,
        finishReason: 'stop',
        promptTokens: 120,
        completionTokens: 30,
      );
    }

    // Default reasoning response
    final fallback = defaultResponse ??
        '{"action":"think","thought":"I need to gather more information to accomplish this goal. '
        'Let me analyse the current context and determine the best next step."}';

    return LLMResponse(
      text: fallback,
      model: name,
      finishReason: 'stop',
      promptTokens: 100,
      completionTokens: 40,
    );
  }

  LLMResponse _toolResponse(String tool, Map<String, dynamic> input) =>
      LLMResponse(
        text: jsonEncode({'action': 'use_tool', 'tool': tool, 'input': input}),
        model: name,
        finishReason: 'stop',
        promptTokens: 100,
        completionTokens: 30,
      );

  String _extractQuery(String prompt, String keyword) {
    final idx = prompt.indexOf(keyword);
    if (idx == -1) return 'general query';
    final sub = prompt.substring(idx + keyword.length).trim();
    return sub.split(RegExp(r'[\n,;.]')).first.trim().isNotEmpty
        ? sub.split(RegExp(r'[\n,;.]')).first.trim()
        : 'general query';
  }
}

// ─────────────────────────────────────────────
// HttpLLMProvider
// ─────────────────────────────────────────────

/// OpenAI-compatible HTTP provider.
///
/// Works with any API that follows the `/v1/chat/completions` spec:
/// OpenAI, Azure OpenAI, Ollama (with --api openai), LM Studio,
/// Together AI, Groq, etc.
///
/// ### Example
/// ```dart
/// final provider = HttpLLMProvider(
///   apiKey: Platform.environment['OPENAI_API_KEY']!,
///   model: 'gpt-4o',
/// );
/// ```
class HttpLLMProvider extends LLMProvider {
  HttpLLMProvider({
    required this.apiKey,
    this.model = 'gpt-4o-mini',
    this.baseUrl = 'https://api.openai.com/v1',
    this.organizationId,
    http.Client? client,
    ConsciousnessLogger? logger,
  })  : _client = client ?? http.Client(),
        _logger = logger ?? ConsciousnessLogger('HttpLLMProvider');

  /// API authentication key.
  final String apiKey;

  /// Model identifier passed in the request body.
  final String model;

  /// Base URL of the OpenAI-compatible endpoint.
  final String baseUrl;

  /// Optional organization header (OpenAI only).
  final String? organizationId;

  final http.Client _client;
  final ConsciousnessLogger _logger;

  @override
  String get name => 'http/$model';

  @override
  Future<LLMResponse> complete(LLMRequest request) async {
    final url = Uri.parse('$baseUrl/chat/completions');

    final body = jsonEncode({
      'model': request.model ?? model,
      'messages': request.messages.map((m) => m.toJson()).toList(),
      'max_tokens': request.maxTokens,
      'temperature': request.temperature,
      if (request.stopSequences.isNotEmpty) 'stop': request.stopSequences,
    });

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
      if (organizationId != null) 'OpenAI-Organization': organizationId!,
    };

    _logger.debug('POST $url (model: ${request.model ?? model})');

    try {
      final response = await _client
          .post(url, headers: headers, body: body)
          .timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) {
        throw LLMProviderException(
          'HTTP ${response.statusCode}: ${response.body}',
          statusCode: response.statusCode,
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = json['choices'] as List<dynamic>;
      if (choices.isEmpty) {
        throw const LLMProviderException('No choices returned by LLM');
      }

      final choice = choices.first as Map<String, dynamic>;
      final message = choice['message'] as Map<String, dynamic>;
      final text = message['content'] as String? ?? '';
      final usage = json['usage'] as Map<String, dynamic>? ?? {};

      return LLMResponse(
        text: text,
        promptTokens: (usage['prompt_tokens'] as int?) ?? 0,
        completionTokens: (usage['completion_tokens'] as int?) ?? 0,
        model: json['model'] as String? ?? model,
        finishReason: choice['finish_reason'] as String?,
      );
    } on LLMProviderException {
      rethrow;
    } catch (e, st) {
      _logger.error('LLM request failed', e, st);
      throw LLMProviderException('Network error: $e');
    }
  }

  /// Disposes the underlying HTTP client.
  void dispose() => _client.close();
}

// ─────────────────────────────────────────────
// LLMProviderException
// ─────────────────────────────────────────────

/// Thrown when an [LLMProvider] encounters an unrecoverable error.
class LLMProviderException implements Exception {
  const LLMProviderException(this.message, {this.statusCode});

  final String message;

  /// HTTP status code, if the error came from an HTTP provider.
  final int? statusCode;

  @override
  String toString() =>
      'LLMProviderException: $message'
      '${statusCode != null ? " (HTTP $statusCode)" : ""}';
}
