// lib/agent/reflection/self_reflection.dart
//
// SelfReflectionModule — the agent's error-correction and meta-cognition layer.
//
// Responsibilities:
//   1. Analyse the current execution state (DAG + context + recent memory)
//   2. Detect failure patterns, stalled tasks, and reasoning loops
//   3. Produce an actionable insight string stored in agent memory
//   4. Optionally use the LLM for deep reflection (when available)
//   5. Accumulate a history of reflections for long-term learning
//
// The module implements [SelfReflectionStub] so that [AgentLoopController]
// can call it through the stub interface without importing this file directly,
// keeping the dependency graph clean.

import 'dart:math' as math;

import 'package:consciousness_sim/agent/agent_models.dart';
import 'package:consciousness_sim/agent/llm/llm_core.dart';
import 'package:consciousness_sim/agent/llm/llm_provider.dart';
import 'package:consciousness_sim/agent/loop/agent_loop.dart'
    show SelfReflectionStub;
import 'package:consciousness_sim/agent/memory/agent_memory_store.dart';
import 'package:consciousness_sim/agent/planning/planning_engine.dart';
import 'package:consciousness_sim/utils/logger.dart';

// ─────────────────────────────────────────────
// ReflectionRecord
// ─────────────────────────────────────────────

/// A single self-reflection output captured at a specific iteration.
class ReflectionRecord {
  const ReflectionRecord({
    required this.iteration,
    required this.insight,
    required this.severity,
    required this.triggeredBy,
    DateTime? timestamp,
  }) : timestamp = timestamp;

  /// The iteration number when reflection was triggered.
  final int iteration;

  /// The actionable insight produced.
  final String insight;

  /// How serious the issue was (0.0 = minor, 1.0 = critical).
  final double severity;

  /// Which detector triggered this reflection.
  final ReflectionTrigger triggeredBy;

  final DateTime? timestamp;

  @override
  String toString() =>
      'Reflection(iter: $iteration, trigger: ${triggeredBy.name}, '
      'severity: ${severity.toStringAsFixed(2)}, '
      'insight: "${_trunc(insight)}")';

  String _trunc(String s, [int n = 80]) =>
      s.length > n ? '${s.substring(0, n - 3)}...' : s;
}

/// What caused a reflection to be triggered.
enum ReflectionTrigger {
  /// Multiple tasks have failed in the current plan.
  taskFailures,

  /// The plan has made no progress for several iterations.
  stalledProgress,

  /// The same tool keeps being called with the same input (loop detected).
  toolCallLoop,

  /// The agent has been in a pure-thought cycle with no tool calls.
  noToolProgress,

  /// A periodic scheduled reflection (no specific issue detected).
  scheduled,

  /// Triggered by the LLM explicitly requesting reflection.
  llmRequested,
}

// ─────────────────────────────────────────────
// SelfReflectionConfig
// ─────────────────────────────────────────────

/// Tuning parameters for [SelfReflectionModule].
class SelfReflectionConfig {
  const SelfReflectionConfig({
    this.stalledProgressThreshold = 3,
    this.toolLoopWindowSize = 4,
    this.maxFailuresBeforeReflect = 2,
    this.noToolProgressThreshold = 5,
    this.maxHistorySize = 50,
    this.enableLLMReflection = true,
    this.minSeverityToStore = 0.3,
  });

  /// How many iterations with zero task progress before flagging stall.
  final int stalledProgressThreshold;

  /// Window size for detecting repeated tool calls.
  final int toolLoopWindowSize;

  /// How many task failures trigger an urgent reflection.
  final int maxFailuresBeforeReflect;

  /// How many consecutive think-only iterations trigger reflection.
  final int noToolProgressThreshold;

  /// Maximum reflection records to keep in memory.
  final int maxHistorySize;

  /// Whether to use the LLM for generating rich reflections.
  final bool enableLLMReflection;

  /// Minimum severity score to store a reflection in [AgentMemoryStore].
  final double minSeverityToStore;
}

// ─────────────────────────────────────────────
// SelfReflectionModule
// ─────────────────────────────────────────────

/// Performs meta-cognitive analysis of the agent's own reasoning process.
///
/// ### Usage
/// ```dart
/// final reflection = SelfReflectionModule(
///   memory: agentMemory,
///   llm: llmCore,  // optional — enables LLM-powered reflection
/// );
///
/// // Called automatically by AgentLoopController every N iterations
/// final insight = await reflection.reflect(context, dag);
/// if (insight != null) {
///   print('Reflection: $insight');
/// }
/// ```
///
/// ### What it detects
/// - **Stalled progress** — no tasks completed for N iterations
/// - **Tool call loops** — the same tool called repeatedly with the same input
/// - **Cascade failures** — multiple tasks failing in sequence
/// - **Thought spirals** — only `think` decisions, no tool calls, for N iterations
class SelfReflectionModule implements SelfReflectionStub {
  SelfReflectionModule({
    required AgentMemoryStore memory,
    LLMCore? llm,
    SelfReflectionConfig? config,
    ConsciousnessLogger? logger,
  })  : _memory = memory,
        _llm = llm,
        _config = config ?? const SelfReflectionConfig(),
        _logger = logger ?? ConsciousnessLogger('SelfReflection');

  final AgentMemoryStore _memory;
  final LLMCore? _llm;
  final SelfReflectionConfig _config;
  final ConsciousnessLogger _logger;

  // ── Tracking state ─────────────────────────
  final List<ReflectionRecord> _history = [];
  final List<String> _recentToolCalls = []; // rolling window
  int _iterationsSinceProgress = 0;
  int _consecutiveThinkOnlyIterations = 0;
  int _lastSucceededCount = 0;

  // ── PUBLIC API ─────────────────────────────

  /// All reflection records produced so far.
  List<ReflectionRecord> get history =>
      List.unmodifiable(_history);

  /// Number of reflections performed.
  int get reflectionCount => _history.length;

  /// Most recent reflection, or null if none yet.
  ReflectionRecord? get lastReflection =>
      _history.isEmpty ? null : _history.last;

  // ── SelfReflectionStub implementation ──────

  /// Analyses [context] and [dag] and returns an actionable insight, or null.
  ///
  /// This is the primary entry point called by [AgentLoopController].
  @override
  Future<String?> reflect(AgentContext context, ExecutionDAG dag) async {
    _logger.info(
        'Self-reflection triggered at iteration ${context.iterationNumber}');

    // Update rolling trackers
    _updateTrackers(context, dag);

    // Run all detectors in priority order
    final detection = _detect(context, dag);

    if (detection == null) {
      _logger.debug('No issues detected — scheduled reflection');
      // Still produce a scheduled reflection for learning purposes
      final insight = _scheduledReflection(context, dag);
      _record(
        iteration: context.iterationNumber,
        insight: insight,
        severity: 0.1,
        trigger: ReflectionTrigger.scheduled,
        goalId: context.goal.id,
      );
      return insight;
    }

    final (trigger, severity, ruleBasedInsight) = detection;

    // If LLM is available and severity is high enough, use it for richer output
    String insight;
    if (_llm != null &&
        _config.enableLLMReflection &&
        severity >= 0.5) {
      insight = await _llmReflection(context, dag, trigger, ruleBasedInsight);
    } else {
      insight = ruleBasedInsight;
    }

    _record(
      iteration: context.iterationNumber,
      insight: insight,
      severity: severity,
      trigger: trigger,
      goalId: context.goal.id,
    );

    _logger.info(
        'Reflection [${trigger.name}, severity: ${severity.toStringAsFixed(2)}]: '
        '"${_trunc(insight)}"');

    return insight;
  }

  /// Notifies the reflection module about the most recent tool call.
  ///
  /// Call this from the agent loop each time a tool is successfully invoked
  /// so the loop-detection window stays accurate.
  void notifyToolCall(String toolName, Map<String, dynamic> input) {
    final key = '$toolName:${input.toString()}';
    _recentToolCalls.add(key);
    if (_recentToolCalls.length > _config.toolLoopWindowSize * 2) {
      _recentToolCalls.removeRange(
          0, _recentToolCalls.length - _config.toolLoopWindowSize * 2);
    }
    _consecutiveThinkOnlyIterations = 0;
  }

  /// Notifies the reflection module of a think-only decision (no tool used).
  void notifyThinkOnly() {
    _consecutiveThinkOnlyIterations++;
  }

  /// Resets all tracking state (e.g. after a successful re-plan).
  void resetTrackers() {
    _iterationsSinceProgress = 0;
    _consecutiveThinkOnlyIterations = 0;
    _lastSucceededCount = 0;
    _recentToolCalls.clear();
    _logger.debug('Reflection trackers reset');
  }

  // ── Private: Detectors ──────────────────────

  void _updateTrackers(AgentContext context, ExecutionDAG dag) {
    final succeededNow = dag.succeeded.length;
    if (succeededNow > _lastSucceededCount) {
      _iterationsSinceProgress = 0;
      _lastSucceededCount = succeededNow;
    } else {
      _iterationsSinceProgress++;
    }
  }

  /// Runs all detectors. Returns (trigger, severity, insight) or null.
  (ReflectionTrigger, double, String)? _detect(
    AgentContext context,
    ExecutionDAG dag,
  ) {
    // 1. Cascade failure — most urgent
    final failCount = dag.failed.length;
    if (failCount >= _config.maxFailuresBeforeReflect) {
      final severity = math.min(0.5 + failCount * 0.15, 1.0);
      final failedDescs =
          dag.failed.map((t) => '"${_trunc(t.description)}"').join(', ');
      return (
        ReflectionTrigger.taskFailures,
        severity,
        'Multiple task failures detected ($failCount): $failedDescs. '
            'Consider breaking tasks into smaller steps or using alternative tools.',
      );
    }

    // 2. Tool call loop detection
    if (_recentToolCalls.length >= _config.toolLoopWindowSize) {
      final window =
          _recentToolCalls.sublist(_recentToolCalls.length - _config.toolLoopWindowSize);
      final distinctCalls = window.toSet().length;
      if (distinctCalls == 1) {
        return (
          ReflectionTrigger.toolCallLoop,
          0.7,
          'Tool call loop detected: the same tool call "${_trunc(window.first)}" '
              'has been repeated ${_config.toolLoopWindowSize} times without progress. '
              'Try a different tool or approach.',
        );
      }
    }

    // 3. Stalled progress
    if (_iterationsSinceProgress >= _config.stalledProgressThreshold) {
      final severity = math.min(
          0.4 + (_iterationsSinceProgress - _config.stalledProgressThreshold) * 0.1,
          0.9);
      return (
        ReflectionTrigger.stalledProgress,
        severity,
        'No task progress for $_iterationsSinceProgress iterations. '
            'Currently ${dag.ready.length} task(s) ready and ${dag.running.length} running. '
            'Consider re-planning or requesting a different strategy.',
      );
    }

    // 4. Think-only spiral
    if (_consecutiveThinkOnlyIterations >= _config.noToolProgressThreshold) {
      return (
        ReflectionTrigger.noToolProgress,
        0.5,
        'Agent has been in a thought loop for $_consecutiveThinkOnlyIterations iterations '
            'without calling any tools. '
            'Consider invoking a search or calculation tool to make concrete progress.',
      );
    }

    return null; // No issue detected
  }

  /// Produces a scheduled (no-issue) reflection summary.
  String _scheduledReflection(AgentContext context, ExecutionDAG dag) {
    final buf = StringBuffer();
    buf.write('Periodic check at iteration ${context.iterationNumber}: ');

    if (dag.size == 0) {
      buf.write('No plan yet. ');
    } else {
      final pct = (dag.succeeded.length / dag.size * 100).round();
      buf.write('Plan ${pct}% complete '
          '(${dag.succeeded.length}/${dag.size} tasks). ');
    }

    final memStats = _memory.stats;
    buf.write('Memory: ${memStats['total']} entries. ');
    buf.write('Recent observations: ${context.recentObservations.length}. ');

    if (context.recentObservations.isNotEmpty) {
      buf.write(
          'Last observation: "${_trunc(context.recentObservations.last.content, 60)}". ');
    }

    buf.write('Continue executing the current plan.');
    return buf.toString();
  }

  /// Uses the LLM to generate a richer reflection when a serious issue is found.
  Future<String> _llmReflection(
    AgentContext context,
    ExecutionDAG dag,
    ReflectionTrigger trigger,
    String ruleBasedInsight,
  ) async {
    final prompt = _buildReflectionPrompt(context, dag, trigger, ruleBasedInsight);

    try {
      final request = LLMRequest(
        messages: [
          const LLMMessage(
            role: 'system',
            content: 'You are a meta-cognitive analysis module for an AI agent. '
                'Analyse the agent\'s current state and provide a concise, '
                'actionable improvement suggestion (2–3 sentences max).',
          ),
          LLMMessage(role: 'user', content: prompt),
        ],
        maxTokens: 200,
        temperature: 0.4,
      );

      final response = await _llm!.provider.complete(request);
      final text = response.text.trim();
      if (text.isNotEmpty) return text;
    } catch (e) {
      _logger.warning('LLM reflection call failed: $e — using rule-based insight');
    }

    return ruleBasedInsight;
  }

  String _buildReflectionPrompt(
    AgentContext context,
    ExecutionDAG dag,
    ReflectionTrigger trigger,
    String ruleBasedInsight,
  ) {
    final buf = StringBuffer();
    buf.writeln('## Agent Status Report');
    buf.writeln('Goal: ${context.goal.description}');
    buf.writeln('Iteration: ${context.iterationNumber}');
    buf.writeln('');

    buf.writeln('## Detected Issue');
    buf.writeln('Trigger: ${trigger.name}');
    buf.writeln('Rule-based insight: $ruleBasedInsight');
    buf.writeln('');

    buf.writeln('## Plan State');
    buf.writeln('Total tasks: ${dag.size}');
    buf.writeln('Succeeded: ${dag.succeeded.length}');
    buf.writeln('Failed: ${dag.failed.length}');
    buf.writeln('Ready: ${dag.ready.length}');
    buf.writeln('');

    if (context.recentObservations.isNotEmpty) {
      buf.writeln('## Recent Observations');
      for (final o in context.recentObservations.take(3)) {
        buf.writeln('• [${o.source}] ${_trunc(o.content, 100)}');
      }
      buf.writeln('');
    }

    buf.writeln('## Recent Reflections');
    final recent = _history.reversed.take(2).toList();
    if (recent.isEmpty) {
      buf.writeln('(none yet)');
    } else {
      for (final r in recent) {
        buf.writeln('• iter ${r.iteration}: ${_trunc(r.insight, 80)}');
      }
    }

    buf.writeln('');
    buf.writeln(
        'Based on this state, what specific action should the agent take next '
        'to get back on track? Be concise and direct.');

    return buf.toString();
  }

  // ── Private: Record keeping ──────────────────

  void _record({
    required int iteration,
    required String insight,
    required double severity,
    required ReflectionTrigger trigger,
    String? goalId,
  }) {
    final record = ReflectionRecord(
      iteration: iteration,
      insight: insight,
      severity: severity,
      triggeredBy: trigger,
      timestamp: DateTime.now(),
    );

    _history.add(record);

    // Trim history if over limit
    if (_history.length > _config.maxHistorySize) {
      _history.removeRange(0, _history.length - _config.maxHistorySize);
    }

    // Persist to agent memory if significant
    if (severity >= _config.minSeverityToStore && goalId != null) {
      _memory.remember(
        content: '[Reflection/${trigger.name}] $insight',
        type: AgentMemoryType.reflection,
        goalId: goalId,
        importance: severity.clamp(0.3, 0.95),
      );
    }
  }

  // ── Statistics & Diagnostics ──────────────────

  /// Returns a diagnostic summary of all reflections so far.
  String diagnostics() {
    if (_history.isEmpty) return 'No reflections recorded yet.';

    final avgSeverity =
        _history.map((r) => r.severity).reduce((a, b) => a + b) /
            _history.length;

    final triggerCounts = <String, int>{};
    for (final r in _history) {
      triggerCounts[r.triggeredBy.name] =
          (triggerCounts[r.triggeredBy.name] ?? 0) + 1;
    }

    final buf = StringBuffer();
    buf.writeln(
        'SelfReflection: ${_history.length} reflection(s), '
        'avg severity: ${avgSeverity.toStringAsFixed(2)}');
    buf.writeln('Triggers: $triggerCounts');
    if (_history.isNotEmpty) {
      buf.writeln(
          'Last: iter ${_history.last.iteration} — '
          '"${_trunc(_history.last.insight)}"');
    }
    return buf.toString().trimRight();
  }

  String _trunc(String s, [int n = 80]) =>
      s.length > n ? '${s.substring(0, n - 3)}...' : s;

  @override
  String toString() =>
      'SelfReflectionModule(reflections: ${_history.length}, '
      'itersSinceProgress: $_iterationsSinceProgress)';
}
