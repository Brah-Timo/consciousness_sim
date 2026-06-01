// lib/agent/llm/llm_core.dart
//
// LLMCore — the reasoning brain of the autonomous agent.
//
// Responsibilities:
//   1. Prompt building     — assemble system + user messages from AgentContext
//   2. Memory summarising  — compress agent memory into a short paragraph
//   3. Context compressing — truncate oversized context windows gracefully
//   4. Response parsing    — convert raw LLM text into typed AgentDecision
//   5. Reasoning           — public API: reason(context) → AgentDecision

import 'dart:convert';

import 'package:consciousness_sim/agent/agent_models.dart';
import 'package:consciousness_sim/agent/llm/llm_provider.dart';
import 'package:consciousness_sim/agent/memory/agent_memory_store.dart';
import 'package:consciousness_sim/utils/logger.dart';

// ─────────────────────────────────────────────
// LLMCoreConfig
// ─────────────────────────────────────────────

/// Tuning parameters for [LLMCore].
class LLMCoreConfig {
  const LLMCoreConfig({
    this.maxContextTokens = 3000,
    this.maxMemoryEntries = 8,
    this.maxObservations = 6,
    this.maxWorkspaceConcepts = 10,
    this.temperature = 0.7,
    this.maxResponseTokens = 512,
    this.systemPersona = _defaultPersona,
  });

  /// Hard limit on approximate tokens sent per request.
  final int maxContextTokens;

  /// Maximum number of memory snippets included in the prompt.
  final int maxMemoryEntries;

  /// Maximum number of recent observations included.
  final int maxObservations;

  /// Maximum number of workspace concepts listed.
  final int maxWorkspaceConcepts;

  /// LLM sampling temperature.
  final double temperature;

  /// Maximum tokens the LLM should generate.
  final int maxResponseTokens;

  /// System-level persona / instruction.
  final String systemPersona;

  static const String _defaultPersona =
      'You are an autonomous cognitive agent with access to tools, memory, '
      'and a planning system. You reason step-by-step to accomplish goals. '
      'Always respond with valid JSON matching the action schema.';
}

// ─────────────────────────────────────────────
// LLMCore
// ─────────────────────────────────────────────

/// Orchestrates all LLM interactions for the agent.
///
/// ### Usage
/// ```dart
/// final core = LLMCore(
///   provider: HttpLLMProvider(apiKey: '...', model: 'gpt-4o'),
///   memory: store,
/// );
///
/// final decision = await core.reason(context);
/// // decision.type == AgentDecisionType.useTool
/// // decision.toolName == 'search_web'
/// ```
///
/// ### Response schema the LLM must follow
/// The system prompt instructs the LLM to return one of:
/// ```json
/// {"action":"use_tool","tool":"<name>","input":{...},"thought":"..."}
/// {"action":"think","thought":"..."}
/// {"action":"complete","reason":"..."}
/// {"action":"replan","reason":"..."}
/// {"action":"error","message":"..."}
/// ```
class LLMCore {
  LLMCore({
    required LLMProvider provider,
    required AgentMemoryStore memory,
    LLMCoreConfig? config,
    ConsciousnessLogger? logger,
  })  : _provider = provider,
        _memory = memory,
        _config = config ?? const LLMCoreConfig(),
        _logger = logger ?? ConsciousnessLogger('LLMCore');

  final LLMProvider _provider;
  final AgentMemoryStore _memory;
  final LLMCoreConfig _config;
  final ConsciousnessLogger _logger;

  // ── Token-usage tracking ───────────────────
  int _totalPromptTokens = 0;
  int _totalCompletionTokens = 0;
  int _reasoningCalls = 0;

  int get totalPromptTokens => _totalPromptTokens;
  int get totalCompletionTokens => _totalCompletionTokens;
  int get reasoningCalls => _reasoningCalls;

  /// Exposes the underlying [LLMProvider] for direct use by subsystems
  /// (e.g. [PlanningEngine] uses it to make planning-specific requests).
  LLMProvider get provider => _provider;

  // ── PUBLIC API ──────────────────────────────

  /// Core reasoning call.
  ///
  /// Builds a full prompt from [context], calls the LLM, parses the response
  /// into an [AgentDecision] and returns it.
  ///
  /// Throws [LLMCoreException] on unrecoverable parsing or provider errors.
  Future<AgentDecision> reason(AgentContext context) async {
    _reasoningCalls++;
    _logger.info(
        'Reasoning call #$_reasoningCalls for goal '
        '"${_trunc(context.goal.description)}" '
        '(iter: ${context.iterationNumber})');

    final messages = _buildMessages(context);

    final request = LLMRequest(
      messages: messages,
      maxTokens: _config.maxResponseTokens,
      temperature: _config.temperature,
    );

    LLMResponse response;
    try {
      response = await _provider.complete(request);
    } catch (e, st) {
      _logger.error('LLM provider error', e, st);
      return AgentDecision(
        type: AgentDecisionType.error,
        thought: 'LLM provider error: $e',
        rawResponse: e.toString(),
      );
    }

    _totalPromptTokens += response.promptTokens;
    _totalCompletionTokens += response.completionTokens;

    _logger.debug(
        'LLM response (${response.totalTokens} tokens): '
        '"${_trunc(response.text)}"');

    final decision = _parseResponse(response.text);
    _logger.info(
        'Decision: ${decision.type.name}'
        '${decision.toolName != null ? " → ${decision.toolName}" : ""}');

    return decision;
  }

  /// Summarises the agent's memory into a short paragraph.
  ///
  /// Used by the prompt builder to include relevant past experiences.
  String summariseMemory(AgentContext context) {
    final memories = _memory.retrieve(
      context.goal.description,
      maxResults: _config.maxMemoryEntries,
      filterGoalId: context.goal.id,
    );

    if (memories.isEmpty) {
      // Broaden search if no goal-specific memories
      final broad = _memory.retrieve(
        context.goal.description,
        maxResults: _config.maxMemoryEntries,
      );
      if (broad.isEmpty) return '(No relevant memories.)';
      return broad.map((m) => '• [${m.type.name}] ${m.content}').join('\n');
    }

    return memories.map((m) => '• [${m.type.name}] ${m.content}').join('\n');
  }

  /// Compresses [text] to at most [maxChars] characters by truncating the
  /// middle section and inserting an ellipsis.
  ///
  /// Preserves the beginning (context) and end (most recent data) of the text.
  String compressContext(String text, {int maxChars = 2000}) {
    if (text.length <= maxChars) return text;
    final keep = maxChars ~/ 2 - 20;
    return '${text.substring(0, keep)}\n…[compressed]…\n'
        '${text.substring(text.length - keep)}';
  }

  /// Builds a complete prompt as a list of [LLMMessage]s from [context].
  List<LLMMessage> buildPrompt(AgentContext context) => _buildMessages(context);

  // ── Private: Prompt Building ────────────────

  List<LLMMessage> _buildMessages(AgentContext context) {
    final system = _buildSystemMessage();
    final user = _buildUserMessage(context);
    return [
      LLMMessage(role: 'system', content: system),
      LLMMessage(role: 'user', content: user),
    ];
  }

  String _buildSystemMessage() => '''
${_config.systemPersona}

## Response Schema
Always reply with a SINGLE valid JSON object. No markdown fences. No extra text.

Choose one of these action types:

1. Use a tool:
{"action":"use_tool","tool":"<tool_name>","input":{<key>:<value>,...},"thought":"<why>"}

2. Think (reasoning step, no tool needed):
{"action":"think","thought":"<your reasoning>"}

3. Complete the goal:
{"action":"complete","reason":"<why the goal is achieved>"}

4. Request re-plan (current plan is no longer valid):
{"action":"replan","reason":"<why the plan must change>"}

5. Signal unrecoverable error:
{"action":"error","message":"<description>"}

## Available Tools
search_web    — search the internet for information
calculate     — evaluate a mathematical expression
read_file     — read the contents of a local file
write_file    — write content to a local file
call_api      — make an HTTP request to an external API
schedule_task — schedule a future task or reminder
''';

  String _buildUserMessage(AgentContext context) {
    final goal = context.goal;
    final buf = StringBuffer();

    // ── Workspace ──────────────────────────────
    buf.writeln('## Active Workspace');
    if (context.workspaceConcepts.isEmpty) {
      buf.writeln('(empty)');
    } else {
      final shown = context.workspaceConcepts.take(_config.maxWorkspaceConcepts);
      for (final c in shown) {
        buf.writeln('• $c');
      }
    }
    buf.writeln();

    // ── Memory ────────────────────────────────
    buf.writeln('## Relevant Memory');
    if (context.retrievedMemories.isEmpty) {
      buf.writeln(summariseMemory(context));
    } else {
      final shown = context.retrievedMemories.take(_config.maxMemoryEntries);
      for (final m in shown) {
        buf.writeln('• $m');
      }
    }
    buf.writeln();

    // ── Recent Observations ───────────────────
    if (context.recentObservations.isNotEmpty) {
      buf.writeln('## Recent Observations');
      final shown = context.recentObservations.take(_config.maxObservations);
      for (final o in shown) {
        buf.writeln('• [${o.source}] ${o.content}');
      }
      buf.writeln();
    }

    // ── Active Tasks ──────────────────────────
    if (context.activeTasks.isNotEmpty) {
      buf.writeln('## Current Plan');
      for (final t in context.activeTasks) {
        final status = t.status.name.toUpperCase();
        buf.writeln('• [$status] ${t.description}');
        if (t.result != null && t.result!.output != null) {
          buf.writeln('  Result: ${_trunc(t.result!.output.toString(), 120)}');
        }
      }
      buf.writeln();
    }

    // ── Goal ──────────────────────────────────
    buf.writeln('## Goal (iteration ${context.iterationNumber})');
    buf.writeln(goal.description);
    if (goal.successCriteria.isNotEmpty) {
      buf.writeln('Success when:');
      for (final c in goal.successCriteria) {
        buf.writeln('  ✓ $c');
      }
    }
    buf.writeln();
    buf.writeln('Decide the best next action. Reply with JSON only.');

    final text = buf.toString();
    // Compress if too large
    final approxTokens = text.length ~/ 4;
    if (approxTokens > _config.maxContextTokens) {
      return compressContext(text, maxChars: _config.maxContextTokens * 4);
    }
    return text;
  }

  // ── Private: Response Parsing ──────────────

  /// Parses the raw LLM text into a typed [AgentDecision].
  ///
  /// Robust to:
  ///   - Markdown code fences (```json ... ```)
  ///   - Leading/trailing whitespace
  ///   - Partial JSON (tries to extract first `{...}` block)
  AgentDecision _parseResponse(String raw) {
    final cleaned = _extractJson(raw);
    if (cleaned == null) {
      _logger.warning('Could not extract JSON from LLM response: "${_trunc(raw)}"');
      return AgentDecision(
        type: AgentDecisionType.think,
        thought: raw.trim(),
        rawResponse: raw,
        confidence: 0.4,
      );
    }

    Map<String, dynamic> json;
    try {
      json = jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (e) {
      _logger.warning('JSON parse error: $e — raw: "${_trunc(cleaned)}"');
      return AgentDecision(
        type: AgentDecisionType.think,
        thought: raw.trim(),
        rawResponse: raw,
        confidence: 0.3,
      );
    }

    final action = (json['action'] as String? ?? '').toLowerCase();

    switch (action) {
      case 'use_tool':
        final tool = json['tool'] as String?;
        if (tool == null || tool.isEmpty) {
          return AgentDecision.think(
            'LLM requested tool but provided no name. Thought: ${json['thought'] ?? ""}',
            confidence: 0.5,
          );
        }
        final input = (json['input'] as Map<String, dynamic>?) ?? {};
        return AgentDecision.useTool(
          tool,
          input,
          thought: json['thought'] as String?,
          confidence: (json['confidence'] as num?)?.toDouble() ?? 0.9,
        );

      case 'think':
        return AgentDecision.think(
          (json['thought'] as String?) ?? raw,
          confidence: (json['confidence'] as num?)?.toDouble() ?? 0.8,
        );

      case 'complete':
        return AgentDecision.complete(
          (json['reason'] as String?) ?? 'Goal achieved.',
          confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
        );

      case 'replan':
        return AgentDecision.replan(
          (json['reason'] as String?) ?? 'Plan needs revision.',
        );

      case 'error':
        return AgentDecision(
          type: AgentDecisionType.error,
          thought: (json['message'] as String?) ?? 'Unknown error.',
          rawResponse: raw,
        );

      default:
        _logger.warning('Unknown action "$action" in LLM response');
        return AgentDecision(
          type: AgentDecisionType.think,
          thought: raw.trim(),
          rawResponse: raw,
          confidence: 0.4,
        );
    }
  }

  /// Extracts the first valid `{...}` JSON object from [text].
  String? _extractJson(String text) {
    // Strip markdown fences
    var cleaned = text
        .replaceAll(RegExp(r'```json\s*'), '')
        .replaceAll(RegExp(r'```\s*'), '')
        .trim();

    // Find first { ... }
    final start = cleaned.indexOf('{');
    if (start == -1) return null;

    var depth = 0;
    for (var i = start; i < cleaned.length; i++) {
      if (cleaned[i] == '{') depth++;
      if (cleaned[i] == '}') {
        depth--;
        if (depth == 0) return cleaned.substring(start, i + 1);
      }
    }
    return null;
  }

  String _trunc(String s, [int n = 80]) =>
      s.length > n ? '${s.substring(0, n - 3)}...' : s;

  @override
  String toString() =>
      'LLMCore(provider: ${_provider.name}, '
      'calls: $_reasoningCalls, '
      'tokens: ${_totalPromptTokens}p/${_totalCompletionTokens}c)';
}

// ─────────────────────────────────────────────
// LLMCoreException
// ─────────────────────────────────────────────

/// Thrown by [LLMCore] when a prompt cannot be assembled or a response
/// cannot be parsed.
class LLMCoreException implements Exception {
  const LLMCoreException(this.message);
  final String message;

  @override
  String toString() => 'LLMCoreException: $message';
}
