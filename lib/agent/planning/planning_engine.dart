// lib/agent/planning/planning_engine.dart
//
// PlanningEngine — the strategic brain of the autonomous agent.
//
// Responsibilities:
//   1. Goal decomposition   — break a natural-language goal into concrete tasks
//   2. DAG construction     — build a dependency graph of tasks
//   3. Task prioritisation  — surface the next executable task
//   4. Progress tracking    — mark tasks as running / done / failed
//   5. Dynamic re-planning  — invalidate stale tasks and re-decompose
//
// The engine is LLM-backed: it prompts the LLM once to generate a JSON
// task list, then manages execution entirely in Dart.  A rule-based
// fallback is used when no LLM is available.

import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'package:consciousness_sim/agent/agent_models.dart';
import 'package:consciousness_sim/agent/llm/llm_core.dart';
import 'package:consciousness_sim/agent/llm/llm_provider.dart';
import 'package:consciousness_sim/utils/logger.dart';

// ─────────────────────────────────────────────
// ExecutionDAG
// ─────────────────────────────────────────────

/// A directed acyclic graph of [AgentTask] nodes.
///
/// The DAG is used by [PlanningEngine] to determine:
///   - which tasks are blocked (have unfinished dependencies)
///   - which tasks are ready to execute (all deps succeeded)
///   - the topological execution order
class ExecutionDAG {
  ExecutionDAG(this.goalId);

  final String goalId;
  final Map<String, AgentTask> _tasks = {};

  // ── Mutation ────────────────────────────────

  /// Adds [task] to the DAG.
  void add(AgentTask task) => _tasks[task.id] = task;

  /// Removes a task by [id].
  void remove(String id) => _tasks.remove(id);

  /// Replaces all tasks (used during re-planning).
  void replace(List<AgentTask> tasks) {
    _tasks.clear();
    for (final t in tasks) {
      _tasks[t.id] = t;
    }
  }

  // ── Queries ─────────────────────────────────

  /// All tasks in insertion order.
  List<AgentTask> get all => List.unmodifiable(_tasks.values.toList());

  /// Tasks that can be started right now (all deps succeeded, not yet started).
  List<AgentTask> get ready {
    final succeeded = _tasks.values
        .where((t) => t.status == TaskStatus.succeeded)
        .map((t) => t.id)
        .toSet();

    return _tasks.values.where((t) {
      if (t.status != TaskStatus.pending && t.status != TaskStatus.blocked) {
        return false;
      }
      return t.dependsOnIds.every((dep) => succeeded.contains(dep));
    }).toList()
      ..sort((a, b) => b.estimatedComplexity.compareTo(a.estimatedComplexity));
  }

  /// Tasks currently running.
  List<AgentTask> get running =>
      _tasks.values.where((t) => t.status == TaskStatus.running).toList();

  /// Tasks that failed.
  List<AgentTask> get failed =>
      _tasks.values.where((t) => t.status == TaskStatus.failed).toList();

  /// Tasks that succeeded.
  List<AgentTask> get succeeded =>
      _tasks.values.where((t) => t.status == TaskStatus.succeeded).toList();

  /// Whether every task has either succeeded or been skipped.
  bool get isComplete => _tasks.values.every(
        (t) =>
            t.status == TaskStatus.succeeded || t.status == TaskStatus.skipped,
      );

  /// Whether any task is in a terminal-failure state with no retry left.
  bool get isFailed => _tasks.values.any(
        (t) => t.status == TaskStatus.failed && t.retryCount >= 2,
      );

  /// Total task count.
  int get size => _tasks.length;

  /// Task by ID.
  AgentTask? operator [](String id) => _tasks[id];

  // ── Topological sort ─────────────────────────

  /// Returns tasks in a valid topological execution order.
  ///
  /// Tasks with no dependents come first.  Uses Kahn's algorithm.
  List<AgentTask> get topologicalOrder {
    final inDegree = <String, int>{};
    final adj = <String, List<String>>{};

    for (final t in _tasks.values) {
      inDegree.putIfAbsent(t.id, () => 0);
      for (final dep in t.dependsOnIds) {
        adj.putIfAbsent(dep, () => []).add(t.id);
        inDegree[t.id] = (inDegree[t.id] ?? 0) + 1;
      }
    }

    final queue = _tasks.keys.where((id) => inDegree[id] == 0).toList();
    final result = <AgentTask>[];

    while (queue.isNotEmpty) {
      final id = queue.removeAt(0);
      final task = _tasks[id];
      if (task != null) result.add(task);
      for (final next in adj[id] ?? <String>[]) {
        inDegree[next] = (inDegree[next] ?? 1) - 1;
        if (inDegree[next] == 0) queue.add(next);
      }
    }

    return result;
  }

  @override
  String toString() =>
      'ExecutionDAG(goal: $goalId, '
      'total: ${_tasks.length}, '
      'ready: ${ready.length}, '
      'done: ${succeeded.length})';
}

// ─────────────────────────────────────────────
// PlanningEngine
// ─────────────────────────────────────────────

/// Decomposes goals into tasks and tracks their execution.
///
/// ### Core usage
/// ```dart
/// final engine = PlanningEngine(llmCore: core);
///
/// // Generate initial plan
/// final dag = await engine.plan(goal, context);
///
/// // Pick next task
/// final task = engine.nextTask(dag);
///
/// // Mark progress
/// engine.markRunning(dag, task.id);
/// engine.markSucceeded(dag, task.id, result);
///
/// // Re-plan when needed
/// final newDag = await engine.replan(dag, reason: 'API unavailable', context: ctx);
/// ```
class PlanningEngine {
  PlanningEngine({
    LLMCore? llmCore,
    ConsciousnessLogger? logger,
  })  : _llm = llmCore,
        _logger = logger ?? ConsciousnessLogger('PlanningEngine'),
        _uuid = const Uuid();

  final LLMCore? _llm;
  final ConsciousnessLogger _logger;
  final Uuid _uuid;

  // ── PUBLIC API ──────────────────────────────

  /// Decomposes [goal] into an [ExecutionDAG] of concrete tasks.
  ///
  /// If an [LLMCore] is available, it is used to generate the task list.
  /// Otherwise a simple rule-based decomposition is used as a fallback.
  Future<ExecutionDAG> plan(
    AgentGoal goal,
    AgentContext context,
  ) async {
    _logger.info('Planning for goal: "${_trunc(goal.description)}"');

    final dag = ExecutionDAG(goal.id);
    List<AgentTask> tasks;

    if (_llm != null) {
      tasks = await _planWithLLM(goal, context);
    } else {
      tasks = _planRuleBased(goal);
    }

    for (final t in tasks) {
      dag.add(t);
    }

    _logger.info('Plan generated: ${dag.size} task(s)');
    for (final t in dag.topologicalOrder) {
      _logger.debug(
          '  [${t.status.name}] ${t.description}'
          '${t.dependsOnIds.isNotEmpty ? " (deps: ${t.dependsOnIds.join(", ")})" : ""}');
    }

    return dag;
  }

  /// Re-plans [dag] because of [reason].
  ///
  /// Preserves succeeded tasks and only re-generates pending/failed ones.
  Future<ExecutionDAG> replan(
    ExecutionDAG dag,
    AgentContext context, {
    required String reason,
  }) async {
    _logger.info('Re-planning: "$reason"');

    final goal = context.goal;
    final newDag = ExecutionDAG(goal.id);

    // Keep succeeded tasks
    for (final t in dag.succeeded) {
      newDag.add(t);
    }

    // Re-generate the rest
    final newTasks = _llm != null
        ? await _planWithLLM(goal, context, previousResults: dag.succeeded)
        : _planRuleBased(goal);

    // Avoid re-adding already-succeeded tasks (same description)
    final doneDescs =
        dag.succeeded.map((t) => t.description.toLowerCase()).toSet();

    for (final t in newTasks) {
      if (!doneDescs.contains(t.description.toLowerCase())) {
        newDag.add(t);
      }
    }

    _logger.info(
        'Re-plan complete: ${newDag.size} task(s) '
        '(${newDag.succeeded.length} carried over)');
    return newDag;
  }

  /// Returns the highest-priority ready task, or null if none are ready.
  AgentTask? nextTask(ExecutionDAG dag) {
    final ready = dag.ready;
    if (ready.isEmpty) return null;
    // Highest estimatedComplexity first (harder tasks benefit most from early start)
    return ready.first;
  }

  /// Marks [taskId] as running.
  void markRunning(ExecutionDAG dag, String taskId) {
    final task = dag[taskId];
    if (task == null) return;
    task.status = TaskStatus.running;
    task.startedAt = DateTime.now();
    _logger.debug('Task running: "$taskId"');
  }

  /// Marks [taskId] as succeeded with [result].
  void markSucceeded(ExecutionDAG dag, String taskId, TaskResult result) {
    final task = dag[taskId];
    if (task == null) return;
    task.status = TaskStatus.succeeded;
    task.result = result;
    task.finishedAt = DateTime.now();
    _logger.info('Task succeeded: "${_trunc(task.description)}" '
        '(${task.duration?.inMilliseconds ?? 0}ms)');
  }

  /// Marks [taskId] as failed with [error].
  ///
  /// If [retryable] is true and retry count < 2, resets to pending for retry.
  void markFailed(
    ExecutionDAG dag,
    String taskId,
    String error, {
    bool retryable = true,
  }) {
    final task = dag[taskId];
    if (task == null) return;
    task.retryCount++;
    task.finishedAt = DateTime.now();

    if (retryable && task.retryCount < 2) {
      task.status = TaskStatus.pending;
      _logger.warning(
          'Task failed (retry ${task.retryCount}/2): '
          '"${_trunc(task.description)}" — $error');
    } else {
      task.status = TaskStatus.failed;
      task.result = TaskResult(
        taskId: taskId,
        success: false,
        error: error,
        completedAt: DateTime.now(),
      );
      _logger.error('Task permanently failed: "${_trunc(task.description)}" — $error');
    }
  }

  /// Marks [taskId] as skipped.
  void markSkipped(ExecutionDAG dag, String taskId, {String? reason}) {
    final task = dag[taskId];
    if (task == null) return;
    task.status = TaskStatus.skipped;
    _logger.info('Task skipped: "$taskId"${reason != null ? " ($reason)" : ""}');
  }

  /// Builds a human-readable plan summary for display or LLM context.
  String summarise(ExecutionDAG dag) {
    final buf = StringBuffer();
    buf.writeln('Plan for goal ${dag.goalId} (${dag.size} tasks):');
    var step = 1;
    for (final t in dag.topologicalOrder) {
      final status = _statusIcon(t.status);
      buf.writeln('  Step $step $status ${t.description}');
      if (t.result?.output != null) {
        buf.writeln(
            '       → ${_trunc(t.result!.output.toString(), 100)}');
      }
      step++;
    }
    return buf.toString().trimRight();
  }

  // ── Private: LLM-based planning ─────────────

  Future<List<AgentTask>> _planWithLLM(
    AgentGoal goal,
    AgentContext context, {
    List<AgentTask>? previousResults,
  }) async {
    final doneDescriptions = previousResults
            ?.map((t) => '• ${t.description} ✓')
            .join('\n') ??
        '';

    final prompt = '''
You are a planning agent.  Break the following goal into a concrete list of
actionable tasks.  Each task should be doable in a single step using a tool or
reasoning.

Goal: ${goal.description}

${doneDescriptions.isNotEmpty ? "Already completed:\n$doneDescriptions\n" : ""}
Output a JSON array of task objects.  Example schema:
[
  {
    "id": "t1",
    "description": "Search for recent news about the topic",
    "depends_on": [],
    "tool_hint": "search_web",
    "complexity": 0.4
  },
  {
    "id": "t2",
    "description": "Summarise the search results",
    "depends_on": ["t1"],
    "tool_hint": null,
    "complexity": 0.3
  }
]

Rules:
- 3 to 7 tasks (no more).
- Each task must have a unique "id" string starting with "t".
- "depends_on" is a list of ids that must complete first.
- "tool_hint" is one of: search_web, calculate, read_file, write_file, call_api, schedule_task, or null.
- "complexity" is 0.0 (easy) to 1.0 (hard).
- Reply with ONLY the JSON array.  No markdown.  No extra text.
''';

    final request = LLMRequest(
      messages: [
        const LLMMessage(
          role: 'system',
          content: 'You are a task-planning assistant. Reply only with JSON.',
        ),
        LLMMessage(role: 'user', content: prompt),
      ],
      maxTokens: 800,
      temperature: 0.3, // Lower temperature = more structured output
    );

    LLMResponse response;
    try {
      response = await _llm!.provider.complete(request);
    } catch (e) {
      _logger.warning('LLM planning failed: $e — using rule-based fallback');
      return _planRuleBased(goal);
    }

    final tasks = _parseTaskList(goal.id, response.text);
    if (tasks.isEmpty) {
      _logger.warning('LLM returned empty/unparseable task list — using rule-based fallback');
      return _planRuleBased(goal);
    }
    return tasks;
  }

  List<AgentTask> _parseTaskList(String goalId, String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'```json\s*'), '')
        .replaceAll(RegExp(r'```\s*'), '')
        .trim();

    // Extract first [...] block
    final start = cleaned.indexOf('[');
    final end = cleaned.lastIndexOf(']');
    if (start == -1 || end == -1) {
      _logger.warning('No JSON array found in planning response');
      return [];
    }

    List<dynamic> jsonList;
    try {
      jsonList = jsonDecode(cleaned.substring(start, end + 1)) as List<dynamic>;
    } catch (e) {
      _logger.warning('Failed to parse task list JSON: $e');
      return [];
    }

    return jsonList.map((item) {
      final map = item as Map<String, dynamic>;
      final rawId = map['id'] as String? ?? _uuid.v4();
      // Prefix rawId with goalId to make it globally unique
      final taskId = '${goalId}_$rawId';
      final rawDeps = map['depends_on'] as List<dynamic>? ?? [];
      final deps = rawDeps
          .map((d) => '${goalId}_$d')
          .cast<String>()
          .toList();

      return AgentTask(
        id: taskId,
        goalId: goalId,
        description: map['description'] as String? ?? 'Unnamed task',
        dependsOnIds: deps,
        toolHint: map['tool_hint'] as String?,
        estimatedComplexity:
            (map['complexity'] as num?)?.toDouble() ?? 0.5,
      );
    }).toList();
  }

  // ── Private: Rule-based fallback planning ─────

  List<AgentTask> _planRuleBased(AgentGoal goal) {
    final id = goal.id;
    final desc = goal.description.toLowerCase();

    // Detect simple single-step goals
    if (desc.contains('calculate') || desc.contains('compute')) {
      return [
        AgentTask(
          id: '${id}_t1',
          goalId: id,
          description: 'Calculate: ${goal.description}',
          toolHint: 'calculate',
          estimatedComplexity: 0.3,
        ),
      ];
    }

    if (desc.contains('search') || desc.contains('find') ||
        desc.contains('look up') || desc.contains('what is')) {
      return [
        AgentTask(
          id: '${id}_t1',
          goalId: id,
          description: 'Search for: ${goal.description}',
          toolHint: 'search_web',
          estimatedComplexity: 0.4,
        ),
        AgentTask(
          id: '${id}_t2',
          goalId: id,
          description: 'Summarise the search results',
          dependsOnIds: ['${id}_t1'],
          estimatedComplexity: 0.2,
        ),
      ];
    }

    if (desc.contains('write') && desc.contains('file')) {
      return [
        AgentTask(
          id: '${id}_t1',
          goalId: id,
          description: 'Prepare the content to write',
          estimatedComplexity: 0.4,
        ),
        AgentTask(
          id: '${id}_t2',
          goalId: id,
          description: 'Write the file',
          dependsOnIds: ['${id}_t1'],
          toolHint: 'write_file',
          estimatedComplexity: 0.3,
        ),
      ];
    }

    // Generic 5-step plan
    return [
      AgentTask(
        id: '${id}_t1',
        goalId: id,
        description: 'Analyse the requirements for: ${goal.description}',
        estimatedComplexity: 0.3,
      ),
      AgentTask(
        id: '${id}_t2',
        goalId: id,
        description: 'Gather necessary information',
        dependsOnIds: ['${id}_t1'],
        toolHint: 'search_web',
        estimatedComplexity: 0.5,
      ),
      AgentTask(
        id: '${id}_t3',
        goalId: id,
        description: 'Process and reason about the gathered information',
        dependsOnIds: ['${id}_t2'],
        estimatedComplexity: 0.6,
      ),
      AgentTask(
        id: '${id}_t4',
        goalId: id,
        description: 'Synthesise a conclusion or output',
        dependsOnIds: ['${id}_t3'],
        estimatedComplexity: 0.4,
      ),
      AgentTask(
        id: '${id}_t5',
        goalId: id,
        description: 'Validate the output against the goal criteria',
        dependsOnIds: ['${id}_t4'],
        estimatedComplexity: 0.3,
      ),
    ];
  }

  String _statusIcon(TaskStatus s) => switch (s) {
        TaskStatus.pending => '⏳',
        TaskStatus.blocked => '🔒',
        TaskStatus.running => '🔄',
        TaskStatus.succeeded => '✅',
        TaskStatus.failed => '❌',
        TaskStatus.skipped => '⏭️',
      };

  String _trunc(String s, [int n = 60]) =>
      s.length > n ? '${s.substring(0, n - 3)}...' : s;
}
