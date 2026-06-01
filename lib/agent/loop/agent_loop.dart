// lib/agent/loop/agent_loop.dart
//
// AgentLoopController — the continuous autonomous execution engine.
//
// This is the heart of the agent framework.  It orchestrates every cycle:
//
//   observe        → perceive new information from the environment
//   retrieveMemory → pull relevant past experiences into context
//   plan           → build / update the execution DAG
//   decide         → ask LLMCore for the next action
//   execute        → call tool or record thought
//   updateMemory   → store outcome in AgentMemoryStore
//   checkComplete  → break the loop on success / failure / timeout
//
// External I/O is pluggable through the [EnvironmentAdapter] interface,
// so the loop can run in tests with a mock or in production with real APIs.

import 'dart:async';

import 'package:uuid/uuid.dart';

import 'package:consciousness_sim/agent/agent_models.dart';
import 'package:consciousness_sim/agent/llm/llm_core.dart';
import 'package:consciousness_sim/agent/memory/agent_memory_store.dart';
import 'package:consciousness_sim/agent/planning/planning_engine.dart';
import 'package:consciousness_sim/agent/tools/tool_interface.dart';
import 'package:consciousness_sim/utils/logger.dart';

// ─────────────────────────────────────────────
// EnvironmentAdapter
// ─────────────────────────────────────────────

/// Pluggable interface for reading new observations from the environment.
///
/// Implement this to connect the agent to a real data source — a message
/// queue, sensor feed, user input stream, or test fixture.
abstract class EnvironmentAdapter {
  /// Returns the most recent observations since the last call.
  ///
  /// The agent calls this at the start of every loop iteration.
  /// Return an empty list if nothing new is available.
  Future<List<AgentObservation>> poll();

  /// Optional cleanup hook called when the loop terminates.
  Future<void> dispose() async {}
}

/// A no-op [EnvironmentAdapter] that never yields new observations.
///
/// Useful when the agent operates purely from its initial goal + memory.
class NullEnvironmentAdapter implements EnvironmentAdapter {
  const NullEnvironmentAdapter();

  @override
  Future<List<AgentObservation>> poll() async => const [];

  @override
  Future<void> dispose() async {}
}

/// A programmable [EnvironmentAdapter] for testing.
///
/// Pre-load [observations] before running the agent; they are delivered
/// one batch per `poll()` call.
class MockEnvironmentAdapter implements EnvironmentAdapter {
  MockEnvironmentAdapter({List<List<AgentObservation>>? batches})
      : _batches = batches?.toList() ?? [];

  final List<List<AgentObservation>> _batches;
  int _cursor = 0;

  /// Queues a batch of [observations] to be returned on the next [poll()].
  void enqueue(List<AgentObservation> observations) =>
      _batches.add(observations);

  @override
  Future<List<AgentObservation>> poll() async {
    if (_cursor >= _batches.length) return const [];
    return _batches[_cursor++];
  }

  @override
  Future<void> dispose() async {}
}

// ─────────────────────────────────────────────
// AgentLoopConfig
// ─────────────────────────────────────────────

/// Tuning parameters for [AgentLoopController].
class AgentLoopConfig {
  const AgentLoopConfig({
    this.maxObservationsPerCycle = 5,
    this.maxMemoryRetrievals = 8,
    this.iterationDelay = Duration.zero,
    this.enableReflection = true,
    this.reflectionIntervalIterations = 3,
    this.maxConsecutiveErrors = 3,
    this.emitEvents = true,
  });

  /// How many observations to keep per context window.
  final int maxObservationsPerCycle;

  /// How many memory entries to retrieve per cycle.
  final int maxMemoryRetrievals;

  /// Optional artificial delay between iterations (useful for demos / UIs).
  final Duration iterationDelay;

  /// Whether to run a self-reflection pass periodically.
  final bool enableReflection;

  /// How many iterations between self-reflection invocations.
  final int reflectionIntervalIterations;

  /// How many consecutive errors before the loop hard-stops.
  final int maxConsecutiveErrors;

  /// Whether to emit [AgentLoopEvent]s to [events] stream.
  final bool emitEvents;
}

// ─────────────────────────────────────────────
// AgentLoopEvent  (observable stream of lifecycle events)
// ─────────────────────────────────────────────

/// Type of event emitted by the agent loop.
enum AgentLoopEventType {
  /// A new iteration started.
  iterationStarted,

  /// Observations were polled from the environment.
  observed,

  /// Memory entries were retrieved.
  memoryRetrieved,

  /// A plan was generated or re-generated.
  planned,

  /// A decision was made by the LLM.
  decided,

  /// A tool call was executed.
  toolExecuted,

  /// A thought was recorded (no tool).
  thoughtRecorded,

  /// A task was marked succeeded.
  taskSucceeded,

  /// A task was marked failed.
  taskFailed,

  /// Memory was updated.
  memoryUpdated,

  /// The loop completed successfully.
  completed,

  /// The loop failed (max iterations / errors).
  failed,

  /// A re-plan was triggered.
  replanned,

  /// Self-reflection was performed.
  reflected,
}

/// An event emitted on the [AgentLoopController.events] stream.
class AgentLoopEvent {
  AgentLoopEvent({
    required this.type,
    required this.goalId,
    required this.iteration,
    this.data,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final AgentLoopEventType type;
  final String goalId;
  final int iteration;

  /// Optional payload — tool result, decision, memory snippet, etc.
  final dynamic data;

  final DateTime timestamp;

  @override
  String toString() =>
      'AgentLoopEvent(${type.name}, goal: $goalId, iter: $iteration)';
}

// ─────────────────────────────────────────────
// AgentLoopController
// ─────────────────────────────────────────────

/// Runs the autonomous agent loop for a given [AgentGoal].
///
/// ### Minimal wiring
/// ```dart
/// final memory  = AgentMemoryStore();
/// final llm     = LLMCore(provider: MockLLMProvider(), memory: memory);
/// final planner = PlanningEngine(llmCore: llm);
/// final tools   = ToolRegistry();
/// BuiltinToolset.registerAll(tools);
///
/// final loop = AgentLoopController(
///   llm: llm,
///   memory: memory,
///   planner: planner,
///   registry: tools,
/// );
///
/// final goal = AgentGoal(
///   id: 'g-001',
///   description: 'What is the current weather in Paris?',
/// );
///
/// final result = await loop.run(goal);
/// print(result.success); // true
/// ```
///
/// ### Listening to events
/// ```dart
/// loop.events.listen((e) => print('[${e.type.name}] ${e.iteration}'));
/// ```
class AgentLoopController {
  AgentLoopController({
    required LLMCore llm,
    required AgentMemoryStore memory,
    required PlanningEngine planner,
    required ToolRegistry registry,
    EnvironmentAdapter? environment,
    AgentLoopConfig? config,
    SelfReflectionStub? reflection,
    ConsciousnessLogger? logger,
  })  : _llm = llm,
        _memory = memory,
        _planner = planner,
        _router = ToolRouter(registry,
            logger: logger ?? ConsciousnessLogger('ToolRouter')),
        _env = environment ?? const NullEnvironmentAdapter(),
        _config = config ?? const AgentLoopConfig(),
        _reflection = reflection,
        _logger = logger ?? ConsciousnessLogger('AgentLoop'),
        _uuid = const Uuid() {
    _eventController = StreamController<AgentLoopEvent>.broadcast();
  }

  final LLMCore _llm;
  final AgentMemoryStore _memory;
  final PlanningEngine _planner;
  final ToolRouter _router;
  final EnvironmentAdapter _env;
  final AgentLoopConfig _config;
  final SelfReflectionStub? _reflection;
  final ConsciousnessLogger _logger;
  final Uuid _uuid;

  late final StreamController<AgentLoopEvent> _eventController;

  /// Broadcast stream of [AgentLoopEvent]s emitted during execution.
  Stream<AgentLoopEvent> get events => _eventController.stream;

  // ── State ─────────────────────────────────

  bool _running = false;

  /// Whether the loop is currently active.
  bool get isRunning => _running;

  // ── PUBLIC API ────────────────────────────

  /// Executes the agent loop for [goal] and returns an [AgentRunResult].
  ///
  /// The loop runs synchronously in a `while` cycle, yielding to the event
  /// loop between iterations via [AgentLoopConfig.iterationDelay].
  ///
  /// Call [stop] from another isolate/coroutine to request a graceful abort.
  Future<AgentRunResult> run(AgentGoal goal) async {
    _running = true;
    _stopRequested = false;
    final startTime = DateTime.now();

    _logger.info('━━━ Agent loop START ━━━  goal: "${_trunc(goal.description)}"');

    // ── Initial plan ─────────────────────────
    var context = AgentContext(
      goal: goal,
      iterationNumber: 0,
    );

    var dag = await _planner.plan(goal, context);
    _emit(AgentLoopEventType.planned, goal.id, 0, data: _planner.summarise(dag));

    int iteration = 0;
    int consecutiveErrors = 0;

    // ── Main loop ────────────────────────────
    while (iteration < goal.maxIterations && !_stopRequested) {
      iteration++;
      _emit(AgentLoopEventType.iterationStarted, goal.id, iteration);
      _logger.info('── Iteration $iteration / ${goal.maxIterations} ──');

      // Step 1 — Observe
      context = await _stepObserve(context, goal.id, iteration);

      // Step 2 — Retrieve memory
      context = await _stepRetrieveMemory(context, goal.id, iteration);

      // Step 3 — Sync active tasks from DAG into context
      context = context.copyWith(activeTasks: dag.all);

      // Step 4 — Decide
      final decision = await _llm.reason(context);
      _emit(AgentLoopEventType.decided, goal.id, iteration, data: decision);
      _logger.info('Decision: ${decision.type.name}'
          '${decision.toolName != null ? " → ${decision.toolName}" : ""}');

      // Step 5 — Execute decision
      switch (decision.type) {
        // ── Tool call ──────────────────────
        case AgentDecisionType.useTool:
          consecutiveErrors = 0;
          final toolResult = await _stepExecuteTool(
            decision,
            context,
            goal,
            dag,
            iteration,
          );
          // Inject observation into context
          final obs = AgentObservation(
            id: _uuid.v4(),
            content: toolResult.success
                ? toolResult.outputText
                : 'Tool error: ${toolResult.error}',
            source: decision.toolName ?? 'unknown_tool',
            confidence: toolResult.success ? 0.9 : 0.3,
          );
          context = _addObservation(context, obs);

        // ── Pure thought ───────────────────
        case AgentDecisionType.think:
          consecutiveErrors = 0;
          _stepRecordThought(decision, goal, iteration);
          context = _addObservation(
            context,
            AgentObservation(
              id: _uuid.v4(),
              content: decision.thought ?? '(thinking)',
              source: 'llm_reasoning',
              confidence: decision.confidence,
            ),
          );

        // ── Goal complete ──────────────────
        case AgentDecisionType.complete:
          goal.isComplete = true;
          goal.completionReason = decision.thought;
          _memory.remember(
            content: 'Goal completed: ${goal.description}. '
                'Reason: ${decision.thought ?? "achieved"}',
            type: AgentMemoryType.goalCompletion,
            goalId: goal.id,
            importance: 1.0,
          );
          _emit(AgentLoopEventType.completed, goal.id, iteration,
              data: decision.thought);
          _logger.info('Goal COMPLETED after $iteration iteration(s)');

          await _env.dispose();
          _running = false;
          return _buildResult(
            goal: goal,
            dag: dag,
            iterations: iteration,
            success: true,
            startTime: startTime,
            summary: decision.thought ?? 'Goal achieved.',
          );

        // ── Re-plan ────────────────────────
        case AgentDecisionType.replan:
          consecutiveErrors = 0;
          final reason = decision.replanReason ?? 'Plan revision requested';
          _logger.info('Re-planning: "$reason"');
          dag = await _planner.replan(dag, context, reason: reason);
          context = context.copyWith(activeTasks: dag.all);
          _emit(AgentLoopEventType.replanned, goal.id, iteration,
              data: reason);
          _memory.remember(
            content: 'Re-planned because: $reason',
            type: AgentMemoryType.reasoning,
            goalId: goal.id,
            importance: 0.6,
          );

        // ── Error ──────────────────────────
        case AgentDecisionType.error:
          consecutiveErrors++;
          final msg = decision.thought ?? 'Unknown error';
          _logger.error('Agent error (consecutive: $consecutiveErrors): $msg');
          _memory.remember(
            content: 'Error: $msg',
            type: AgentMemoryType.failure,
            goalId: goal.id,
            importance: 0.8,
          );

          if (consecutiveErrors >= _config.maxConsecutiveErrors) {
            _logger.error(
                'Max consecutive errors reached — aborting loop');
            _emit(AgentLoopEventType.failed, goal.id, iteration,
                data: 'Max errors: $msg');
            await _env.dispose();
            _running = false;
            final abortReason =
                'Aborted after $consecutiveErrors consecutive errors.';
            return _buildResult(
              goal: goal,
              dag: dag,
              iterations: iteration,
              success: false,
              startTime: startTime,
              summary: abortReason,
              error: abortReason,
            );
          }
      }

      // Step 6 — Check if DAG is complete (all tasks succeeded/skipped)
      if (dag.isComplete && dag.size > 0) {
        _logger.info(
            'All DAG tasks complete — checking goal criteria');
        goal.isComplete = true;
        goal.completionReason = 'All planned tasks succeeded.';
        _memory.remember(
          content: 'All tasks in plan succeeded for goal: ${goal.description}',
          type: AgentMemoryType.goalCompletion,
          goalId: goal.id,
          importance: 0.9,
        );
        _emit(AgentLoopEventType.completed, goal.id, iteration);
        await _env.dispose();
        _running = false;
        return _buildResult(
          goal: goal,
          dag: dag,
          iterations: iteration,
          success: true,
          startTime: startTime,
          summary: 'All ${dag.size} task(s) completed successfully.',
        );
      }

      // Step 7 — Periodic self-reflection
      if (_config.enableReflection &&
          _reflection != null &&
          iteration % _config.reflectionIntervalIterations == 0) {
        await _stepReflect(context, goal, dag, iteration);
      }

      // Step 8 — Optional throttle
      if (_config.iterationDelay > Duration.zero) {
        await Future<void>.delayed(_config.iterationDelay);
      }
    } // end while

    // ── Fell through max iterations ──────────
    final reason = _stopRequested
        ? 'Stop requested by caller.'
        : 'Maximum iterations (${goal.maxIterations}) reached.';

    _logger.warning('Loop ended without goal completion: $reason');
    _emit(AgentLoopEventType.failed, goal.id, iteration, data: reason);

    await _env.dispose();
    _running = false;

    return _buildResult(
      goal: goal,
      dag: dag,
      iterations: iteration,
      success: false,
      startTime: startTime,
      summary: reason,
      error: reason,
    );
  }

  bool _stopRequested = false;

  /// Requests a graceful stop after the current iteration finishes.
  ///
  /// The in-progress iteration completes normally; the loop then returns an
  /// [AgentRunResult] with `success: false` and an appropriate error message.
  void stop() {
    _stopRequested = true;
    _logger.info('Stop requested — will halt after current iteration');
  }

  /// Disposes the event stream.  Call after the loop has finished.
  Future<void> dispose() async {
    await _eventController.close();
    await _env.dispose();
    _running = false;
  }

  // ── Private: Step implementations ─────────

  /// Step 1 — Observe: poll the environment and merge new observations.
  Future<AgentContext> _stepObserve(
    AgentContext ctx,
    String goalId,
    int iteration,
  ) async {
    final newObs = await _env.poll();
    if (newObs.isEmpty) return ctx;

    _logger.debug('Observed ${newObs.length} new item(s) from environment');
    _emit(AgentLoopEventType.observed, goalId, iteration, data: newObs.length);

    // Store observations in memory
    for (final o in newObs) {
      _memory.remember(
        content: '[${o.source}] ${o.content}',
        type: AgentMemoryType.observation,
        goalId: goalId,
        importance: o.confidence * 0.7,
      );
    }

    // Merge new observations (keep most recent N)
    final combined = [...ctx.recentObservations, ...newObs];
    final trimmed = combined.length > _config.maxObservationsPerCycle
        ? combined.sublist(combined.length - _config.maxObservationsPerCycle)
        : combined;

    return ctx.copyWith(recentObservations: trimmed);
  }

  /// Step 2 — Retrieve memory relevant to the current goal.
  Future<AgentContext> _stepRetrieveMemory(
    AgentContext ctx,
    String goalId,
    int iteration,
  ) async {
    final entries = _memory.retrieve(
      ctx.goal.description,
      maxResults: _config.maxMemoryRetrievals,
      filterGoalId: goalId,
    );

    if (entries.isEmpty) {
      _logger.debug('No relevant memories found for this iteration');
      return ctx;
    }

    final snippets = entries.map((e) => '[${e.type.name}] ${e.content}').toList();
    _emit(AgentLoopEventType.memoryRetrieved, goalId, iteration,
        data: entries.length);

    return ctx.copyWith(retrievedMemories: snippets);
  }

  /// Step 5a — Execute a tool call based on an [AgentDecision.useTool].
  Future<ToolResult> _stepExecuteTool(
    AgentDecision decision,
    AgentContext ctx,
    AgentGoal goal,
    ExecutionDAG dag,
    int iteration,
  ) async {
    final toolName = decision.toolName!;
    final toolInput = decision.toolInput ?? {};

    _logger.info('Executing tool: $toolName | input: $toolInput');

    final result = await _router.route(toolName, toolInput);

    _emit(AgentLoopEventType.toolExecuted, goal.id, iteration, data: result);

    // Update DAG: find a running or ready task that matches the tool hint
    final taskToUpdate = _findMatchingTask(dag, toolName);
    if (taskToUpdate != null) {
      if (result.success) {
        _planner.markSucceeded(
          dag,
          taskToUpdate.id,
          TaskResult(
            taskId: taskToUpdate.id,
            success: true,
            output: result.output,
            toolUsed: toolName,
            completedAt: DateTime.now(),
          ),
        );
        _emit(AgentLoopEventType.taskSucceeded, goal.id, iteration,
            data: taskToUpdate.id);
      } else {
        _planner.markFailed(dag, taskToUpdate.id, result.error ?? 'Tool failed');
        _emit(AgentLoopEventType.taskFailed, goal.id, iteration,
            data: taskToUpdate.id);
      }
    }

    // Store result in memory
    _memory.remember(
      content: result.success
          ? 'Tool $toolName succeeded: ${_trunc(result.outputText)}'
          : 'Tool $toolName failed: ${result.error ?? "unknown"}',
      type: result.success
          ? AgentMemoryType.observation
          : AgentMemoryType.failure,
      goalId: goal.id,
      importance: result.success ? 0.7 : 0.8,
    );

    _emit(AgentLoopEventType.memoryUpdated, goal.id, iteration);
    return result;
  }

  /// Step 5b — Record a pure-thought step (no tool call).
  void _stepRecordThought(
    AgentDecision decision,
    AgentGoal goal,
    int iteration,
  ) {
    final thought = decision.thought ?? '(silent thought)';
    _logger.debug('Thought recorded: "${_trunc(thought)}"');

    _memory.remember(
      content: thought,
      type: AgentMemoryType.reasoning,
      goalId: goal.id,
      importance: decision.confidence * 0.6,
    );

    _emit(AgentLoopEventType.thoughtRecorded, goal.id, iteration,
        data: thought);
  }

  /// Step 7 — Self-reflection pass.
  Future<void> _stepReflect(
    AgentContext ctx,
    AgentGoal goal,
    ExecutionDAG dag,
    int iteration,
  ) async {
    if (_reflection == null) return;
    _logger.info('Running self-reflection at iteration $iteration');

    final insight = await _reflection!.reflect(ctx, dag);
    if (insight != null) {
      _memory.remember(
        content: insight,
        type: AgentMemoryType.reflection,
        goalId: goal.id,
        importance: 0.8,
      );
      _emit(AgentLoopEventType.reflected, goal.id, iteration, data: insight);
      _logger.info('Self-reflection insight: "${_trunc(insight)}"');
    }
  }

  // ── Private: Helpers ───────────────────────

  /// Adds [obs] to context, trimming to [maxObservationsPerCycle].
  AgentContext _addObservation(AgentContext ctx, AgentObservation obs) {
    final list = [...ctx.recentObservations, obs];
    final trimmed = list.length > _config.maxObservationsPerCycle
        ? list.sublist(list.length - _config.maxObservationsPerCycle)
        : list;
    return ctx.copyWith(recentObservations: trimmed);
  }

  /// Finds the first task in [dag] that is running or ready and whose
  /// [toolHint] matches [toolName].
  AgentTask? _findMatchingTask(ExecutionDAG dag, String toolName) {
    // First, look for a task already in running state
    final running = dag.running.where((t) => t.toolHint == toolName);
    if (running.isNotEmpty) return running.first;

    // Then look for a ready task with the same hint
    final ready = dag.ready.where((t) => t.toolHint == toolName);
    if (ready.isNotEmpty) {
      final task = ready.first;
      _planner.markRunning(dag, task.id);
      return task;
    }

    // Fallback: advance the next ready task regardless of hint
    final anyReady = dag.ready;
    if (anyReady.isNotEmpty) {
      _planner.markRunning(dag, anyReady.first.id);
      return anyReady.first;
    }

    return null;
  }

  AgentRunResult _buildResult({
    required AgentGoal goal,
    required ExecutionDAG dag,
    required int iterations,
    required bool success,
    required DateTime startTime,
    required String summary,
    String? error,
  }) {
    final elapsed = DateTime.now().difference(startTime);
    _logger.info(
        '━━━ Agent loop END ━━━  '
        'success=$success  '
        'iterations=$iterations  '
        'elapsed=${elapsed.inMilliseconds}ms');

    return AgentRunResult(
      goalId: goal.id,
      success: success,
      iterations: iterations,
      tasksCompleted: dag.succeeded.length,
      tasksFailed: dag.failed.length,
      summary: summary,
      error: error,
      finishedAt: DateTime.now(),
    );
  }

  void _emit(
    AgentLoopEventType type,
    String goalId,
    int iteration, {
    dynamic data,
  }) {
    if (!_config.emitEvents) return;
    if (_eventController.isClosed) return;
    _eventController.add(AgentLoopEvent(
      type: type,
      goalId: goalId,
      iteration: iteration,
      data: data,
    ));
  }

  String _trunc(String s, [int n = 80]) =>
      s.length > n ? '${s.substring(0, n - 3)}...' : s;
}

// ─────────────────────────────────────────────
// SelfReflectionStub
// ─────────────────────────────────────────────

/// Minimal interface that [AgentLoopController] calls during the reflection
/// step.  The full implementation lives in
/// `lib/agent/reflection/self_reflection.dart`.
///
/// By keeping this as an interface here, the loop does not need to import the
/// reflection module — avoiding a circular dependency.
abstract class SelfReflectionStub {
  /// Analyses the current [context] and [dag] and returns an insight string,
  /// or null if no useful reflection is available.
  Future<String?> reflect(AgentContext context, ExecutionDAG dag);
}
