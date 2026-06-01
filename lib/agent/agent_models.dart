// lib/agent/agent_models.dart
//
// Core data models for the autonomous agent framework.
// These types are shared across LLM, Tool, Planning, Loop, and Reflection
// layers and deliberately have no dependency on the consciousness_sim core
// so the agent framework can be used standalone.

import 'dart:math' as math;

// ─────────────────────────────────────────────
// AgentGoal
// ─────────────────────────────────────────────

/// The top-level objective the agent is working toward.
///
/// A goal has an [id], a plain-text [description], an optional
/// [successCriteria] list used by the loop to decide when the goal is
/// complete, and a [priority] (0.0 = lowest, 1.0 = most urgent).
class AgentGoal {
  AgentGoal({
    required this.id,
    required this.description,
    List<String>? successCriteria,
    this.priority = 0.5,
    this.maxIterations = 20,
    DateTime? createdAt,
    Map<String, dynamic>? metadata,
  })  : assert(priority >= 0.0 && priority <= 1.0),
        assert(maxIterations > 0),
        successCriteria = successCriteria ?? const [],
        createdAt = createdAt ?? DateTime.now(),
        metadata = metadata ?? const {};

  /// Unique identifier.
  final String id;

  /// Natural-language description of what the agent should accomplish.
  final String description;

  /// Declarative list of conditions that signal the goal is complete.
  final List<String> successCriteria;

  /// How urgent this goal is (0.0 – 1.0).
  final double priority;

  /// Hard cap on the number of agent-loop iterations for this goal.
  final int maxIterations;

  /// When this goal was created.
  final DateTime createdAt;

  /// Arbitrary metadata (caller context, tags, etc.).
  final Map<String, dynamic> metadata;

  /// Whether this goal was explicitly marked complete.
  bool isComplete = false;

  /// Optional human-readable reason the goal was considered done.
  String? completionReason;

  AgentGoal copyWith({
    double? priority,
    bool? isComplete,
    String? completionReason,
  }) =>
      AgentGoal(
        id: id,
        description: description,
        successCriteria: successCriteria,
        priority: priority ?? this.priority,
        maxIterations: maxIterations,
        createdAt: createdAt,
        metadata: metadata,
      )
        ..isComplete = isComplete ?? this.isComplete
        ..completionReason = completionReason ?? this.completionReason;

  @override
  String toString() =>
      'AgentGoal(id: $id, '
      'desc: "${_trunc(description)}", '
      'priority: ${priority.toStringAsFixed(2)}, '
      'complete: $isComplete)';

  String _trunc(String s, [int n = 60]) =>
      s.length > n ? '${s.substring(0, n - 3)}...' : s;
}

// ─────────────────────────────────────────────
// AgentTask
// ─────────────────────────────────────────────

/// A single concrete step produced by the [PlanningEngine].
///
/// Tasks form a DAG: each task may depend on zero or more previous tasks
/// (identified by [dependsOnIds]).  The [PlanningEngine] ensures tasks are
/// only started when all their dependencies have [TaskStatus.succeeded].
class AgentTask {
  AgentTask({
    required this.id,
    required this.goalId,
    required this.description,
    List<String>? dependsOnIds,
    this.toolHint,
    this.estimatedComplexity = 0.5,
    DateTime? createdAt,
    Map<String, dynamic>? inputContext,
  })  : assert(estimatedComplexity >= 0.0 && estimatedComplexity <= 1.0),
        dependsOnIds = dependsOnIds ?? const [],
        createdAt = createdAt ?? DateTime.now(),
        inputContext = inputContext ?? const {};

  /// Unique identifier (stable across re-plans).
  final String id;

  /// The parent goal this task belongs to.
  final String goalId;

  /// What needs to be done in plain English.
  final String description;

  /// IDs of tasks that must succeed before this one can start.
  final List<String> dependsOnIds;

  /// Optional hint to the tool router about which tool to use.
  final String? toolHint;

  /// 0.0 = trivial, 1.0 = highly complex.
  final double estimatedComplexity;

  /// When this task was created.
  final DateTime createdAt;

  /// Input data provided to the task executor (merged into LLM context).
  final Map<String, dynamic> inputContext;

  // ── Mutable execution state ────────────────

  /// Current execution status.
  TaskStatus status = TaskStatus.pending;

  /// The result produced by executing this task (may be null if not yet run).
  TaskResult? result;

  /// How many times this task has been retried.
  int retryCount = 0;

  /// When execution started.
  DateTime? startedAt;

  /// When execution finished (success or failure).
  DateTime? finishedAt;

  /// Wall-clock duration of the last execution attempt.
  Duration? get duration =>
      (startedAt != null && finishedAt != null)
          ? finishedAt!.difference(startedAt!)
          : null;

  @override
  String toString() =>
      'AgentTask(id: $id, status: ${status.name}, '
      'desc: "${_trunc(description)}")';

  String _trunc(String s, [int n = 60]) =>
      s.length > n ? '${s.substring(0, n - 3)}...' : s;
}

/// Execution status for a [AgentTask].
enum TaskStatus {
  /// Not yet started.
  pending,

  /// Waiting for dependency tasks to succeed.
  blocked,

  /// Currently running.
  running,

  /// Finished successfully.
  succeeded,

  /// Failed; may be retried.
  failed,

  /// Explicitly skipped (e.g. determined irrelevant by re-plan).
  skipped,
}

// ─────────────────────────────────────────────
// TaskResult
// ─────────────────────────────────────────────

/// The outcome of executing an [AgentTask].
class TaskResult {
  const TaskResult({
    required this.taskId,
    required this.success,
    this.output,
    this.error,
    this.toolUsed,
    this.rawLlmResponse,
    DateTime? completedAt,
  }) : completedAt = completedAt;

  /// Which task produced this result.
  final String taskId;

  /// Whether the task completed without error.
  final bool success;

  /// The structured or textual output produced (may be null on failure).
  final dynamic output;

  /// Error message if [success] is false.
  final String? error;

  /// Name of the tool used (if any).
  final String? toolUsed;

  /// Raw LLM response text before parsing.
  final String? rawLlmResponse;

  /// When the result was created.
  final DateTime? completedAt;

  @override
  String toString() =>
      'TaskResult(task: $taskId, success: $success, '
      'tool: $toolUsed, output: ${_trunc(output.toString())})';

  String _trunc(String s, [int n = 80]) =>
      s.length > n ? '${s.substring(0, n - 3)}...' : s;
}

// ─────────────────────────────────────────────
// AgentObservation
// ─────────────────────────────────────────────

/// A piece of information the agent has gathered from the environment
/// (tool results, user inputs, sensor data, etc.).
class AgentObservation {
  AgentObservation({
    required this.id,
    required this.content,
    required this.source,
    this.confidence = 1.0,
    DateTime? timestamp,
    Map<String, dynamic>? metadata,
  })  : assert(confidence >= 0.0 && confidence <= 1.0),
        timestamp = timestamp ?? DateTime.now(),
        metadata = metadata ?? const {};

  final String id;

  /// Plain-text or JSON-serialised content of the observation.
  final String content;

  /// Where the observation came from (tool name, sensor type, user, etc.).
  final String source;

  /// How reliable this observation is (0.0 – 1.0).
  final double confidence;

  final DateTime timestamp;
  final Map<String, dynamic> metadata;

  @override
  String toString() =>
      'Observation(source: $source, '
      'confidence: ${confidence.toStringAsFixed(2)}, '
      'content: "${_trunc(content)}")';

  String _trunc(String s, [int n = 80]) =>
      s.length > n ? '${s.substring(0, n - 3)}...' : s;
}

// ─────────────────────────────────────────────
// AgentDecision
// ─────────────────────────────────────────────

/// The action decision produced by the LLM Core after reasoning.
///
/// The LLM may decide to:
///   - call a tool ([AgentDecisionType.useTool])
///   - reason further ([AgentDecisionType.think])
///   - declare the goal complete ([AgentDecisionType.complete])
///   - request a re-plan ([AgentDecisionType.replan])
///   - report a blocking error ([AgentDecisionType.error])
class AgentDecision {
  const AgentDecision({
    required this.type,
    this.toolName,
    this.toolInput,
    this.thought,
    this.replanReason,
    this.confidence = 1.0,
    this.rawResponse,
  }) : assert(confidence >= 0.0 && confidence <= 1.0);

  /// The kind of action the agent decided to take.
  final AgentDecisionType type;

  /// When [type] == [AgentDecisionType.useTool], the tool to invoke.
  final String? toolName;

  /// Input arguments for the tool.
  final Map<String, dynamic>? toolInput;

  /// The reasoning text the LLM produced.
  final String? thought;

  /// Explanation for why a re-plan is needed.
  final String? replanReason;

  /// How confident the LLM is in this decision.
  final double confidence;

  /// Raw LLM response string before parsing.
  final String? rawResponse;

  /// Convenience factory for a tool-use decision.
  factory AgentDecision.useTool(
    String tool,
    Map<String, dynamic> input, {
    String? thought,
    double confidence = 0.9,
  }) =>
      AgentDecision(
        type: AgentDecisionType.useTool,
        toolName: tool,
        toolInput: input,
        thought: thought,
        confidence: confidence,
      );

  /// Convenience factory for a pure-thinking step.
  factory AgentDecision.think(String thought, {double confidence = 0.8}) =>
      AgentDecision(
        type: AgentDecisionType.think,
        thought: thought,
        confidence: confidence,
      );

  /// Convenience factory for a goal-complete signal.
  factory AgentDecision.complete(String reason, {double confidence = 1.0}) =>
      AgentDecision(
        type: AgentDecisionType.complete,
        thought: reason,
        confidence: confidence,
      );

  /// Convenience factory for a re-plan request.
  factory AgentDecision.replan(String reason) =>
      AgentDecision(
        type: AgentDecisionType.replan,
        replanReason: reason,
        confidence: 1.0,
      );

  @override
  String toString() =>
      'AgentDecision(type: ${type.name}, '
      'tool: $toolName, '
      'confidence: ${confidence.toStringAsFixed(2)}, '
      'thought: "${_trunc(thought ?? "")})")';

  String _trunc(String s, [int n = 60]) =>
      s.length > n ? '${s.substring(0, n - 3)}...' : s;
}

/// What kind of action the agent decided to take.
enum AgentDecisionType {
  /// Call a registered tool.
  useTool,

  /// Pure reasoning step — no external tool needed.
  think,

  /// The current goal is satisfied; stop the loop.
  complete,

  /// The current plan is no longer valid; re-plan before continuing.
  replan,

  /// A blocking error occurred that the agent cannot recover from alone.
  error,
}

// ─────────────────────────────────────────────
// AgentContext
// ─────────────────────────────────────────────

/// A window of information injected into every LLM prompt.
///
/// The [LLMCore] compresses this context to fit within the token budget.
class AgentContext {
  AgentContext({
    required this.goal,
    List<AgentTask>? activeTasks,
    List<AgentObservation>? recentObservations,
    List<String>? workspaceConcepts,
    List<String>? retrievedMemories,
    Map<String, dynamic>? environment,
    this.iterationNumber = 0,
  })  : activeTasks = activeTasks ?? const [],
        recentObservations = recentObservations ?? const [],
        workspaceConcepts = workspaceConcepts ?? const [],
        retrievedMemories = retrievedMemories ?? const [],
        environment = environment ?? const {};

  /// The goal being pursued.
  final AgentGoal goal;

  /// Tasks currently in the plan.
  final List<AgentTask> activeTasks;

  /// The most recent observations (tool results, sensor data).
  final List<AgentObservation> recentObservations;

  /// Active concepts from the consciousness workspace.
  final List<String> workspaceConcepts;

  /// Memory snippets relevant to the goal (retrieved by the memory system).
  final List<String> retrievedMemories;

  /// Key-value pairs describing the external environment state.
  final Map<String, dynamic> environment;

  /// How many agent-loop cycles have completed.
  final int iterationNumber;

  /// Returns a copy with updated fields.
  AgentContext copyWith({
    List<AgentTask>? activeTasks,
    List<AgentObservation>? recentObservations,
    List<String>? workspaceConcepts,
    List<String>? retrievedMemories,
    Map<String, dynamic>? environment,
    int? iterationNumber,
  }) =>
      AgentContext(
        goal: goal,
        activeTasks: activeTasks ?? this.activeTasks,
        recentObservations: recentObservations ?? this.recentObservations,
        workspaceConcepts: workspaceConcepts ?? this.workspaceConcepts,
        retrievedMemories: retrievedMemories ?? this.retrievedMemories,
        environment: environment ?? this.environment,
        iterationNumber: iterationNumber ?? this.iterationNumber,
      );

  @override
  String toString() =>
      'AgentContext('
      'goal: "${_trunc(goal.description)}", '
      'iter: $iterationNumber, '
      'obs: ${recentObservations.length}, '
      'tasks: ${activeTasks.length})';

  String _trunc(String s, [int n = 60]) =>
      s.length > n ? '${s.substring(0, n - 3)}...' : s;
}

// ─────────────────────────────────────────────
// AgentMemoryEntry
// ─────────────────────────────────────────────

/// A long-term memory entry specific to the agent framework.
///
/// Distinct from the consciousness_sim [Memory] type — this stores
/// agent-level events: decisions made, tool results, goal completions,
/// and self-reflection outputs.
class AgentMemoryEntry {
  AgentMemoryEntry({
    required this.id,
    required this.type,
    required this.content,
    this.goalId,
    this.taskId,
    double importance = 0.5,
    DateTime? timestamp,
    Map<String, dynamic>? metadata,
  })  : assert(importance >= 0.0 && importance <= 1.0),
        importance = importance,
        timestamp = timestamp ?? DateTime.now(),
        metadata = metadata ?? const {};

  final String id;

  /// Category of memory (decision, observation, reflection, etc.).
  final AgentMemoryType type;

  /// Plain-text or JSON content of the memory.
  final String content;

  /// Associated goal ID (if any).
  final String? goalId;

  /// Associated task ID (if any).
  final String? taskId;

  /// Importance score used for retrieval ranking (0.0 – 1.0).
  double importance;

  final DateTime timestamp;
  final Map<String, dynamic> metadata;

  /// How many times this memory has been retrieved.
  int retrievalCount = 0;

  /// Recency decay: exponential with 24-hour half-life.
  double get recencyScore {
    final ageH = DateTime.now().difference(timestamp).inMinutes / 60.0;
    return math.exp(-ageH / 24.0).clamp(0.0, 1.0);
  }

  /// Composite retrieval score: importance × recency.
  double get score => importance * recencyScore;

  @override
  String toString() =>
      'AgentMemoryEntry(type: ${type.name}, '
      'importance: ${importance.toStringAsFixed(2)}, '
      'content: "${_trunc(content)}")';

  String _trunc(String s, [int n = 80]) =>
      s.length > n ? '${s.substring(0, n - 3)}...' : s;
}

/// Category of an [AgentMemoryEntry].
enum AgentMemoryType {
  /// A decision the agent made.
  decision,

  /// An observation received from a tool or sensor.
  observation,

  /// An LLM reasoning step.
  reasoning,

  /// Output from a self-reflection cycle.
  reflection,

  /// A completed goal summary.
  goalCompletion,

  /// An error or failure event.
  failure,
}

// ─────────────────────────────────────────────
// AgentRunResult
// ─────────────────────────────────────────────

/// Summary produced when the agent loop terminates.
class AgentRunResult {
  const AgentRunResult({
    required this.goalId,
    required this.success,
    required this.iterations,
    required this.tasksCompleted,
    required this.tasksFailed,
    required this.summary,
    this.error,
    DateTime? finishedAt,
  }) : finishedAt = finishedAt;

  final String goalId;
  final bool success;
  final int iterations;
  final int tasksCompleted;
  final int tasksFailed;

  /// Human-readable summary of what the agent accomplished.
  final String summary;

  /// Error message if the run failed without completing the goal.
  final String? error;

  final DateTime? finishedAt;

  @override
  String toString() =>
      'AgentRunResult(goal: $goalId, '
      'success: $success, '
      'iterations: $iterations, '
      'tasks: $tasksCompleted done / $tasksFailed failed)';
}
