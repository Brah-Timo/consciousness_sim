// lib/core/consciousness.dart
// The central Consciousness class — orchestrates all subsystems.
//
// This is the primary public API entry point.  It coordinates:
//   • WorkspaceManager  — the global broadcast medium
//   • AttentionSpotlight — selective focus
//   • BindingEngine     — conceptual binding
//   • MemoryManager     — episodic / semantic / working memory
//   • PerceptionProcessor — sensory input pipeline
//   • InferenceEngine   — reasoning and thought generation
//   • ConceptualGraph   — semantic network
//   • CoherenceManager  — integration consistency
//   • ConsciousnessLogger / Metrics — observability
//
// ## Agent Extension (AgentMind)
//
// [AgentMind] is an extension on [Consciousness] that wires all four new
// agent layers on top of the existing cognition subsystems:
//   • LLMCore      — LLM reasoning brain
//   • PlanningEngine — goal decomposition + DAG
//   • AgentLoopController — autonomous execution loop
//   • AgentMemoryStore    — agent-scoped long-term memory
//
// ### Agent quick-start
// ```dart
// final mind = Consciousness();
// final agent = mind.asAgent(
//   provider: HttpLLMProvider(apiKey: '...', model: 'gpt-4o'),
// );
// final result = await agent.pursue(AgentGoal(
//   id: 'g1',
//   description: 'Research the latest advances in quantum computing',
// ));
// print(result.summary);
// ```

import 'dart:async';

import 'package:uuid/uuid.dart';

import 'package:consciousness_sim/agent/agent_models.dart';
import 'package:consciousness_sim/agent/llm/llm_core.dart';
import 'package:consciousness_sim/agent/llm/llm_provider.dart';
import 'package:consciousness_sim/agent/loop/agent_loop.dart';
import 'package:consciousness_sim/agent/memory/agent_memory_store.dart';
import 'package:consciousness_sim/agent/planning/planning_engine.dart';
import 'package:consciousness_sim/agent/reflection/self_reflection.dart';
import 'package:consciousness_sim/agent/tools/builtin_tools.dart';
import 'package:consciousness_sim/agent/tools/tool_interface.dart';
import 'package:consciousness_sim/core/attention.dart';
import 'package:consciousness_sim/core/binding.dart';
import 'package:consciousness_sim/core/models.dart';
import 'package:consciousness_sim/core/workspace.dart';
import 'package:consciousness_sim/integration/coherence_manager.dart';
import 'package:consciousness_sim/memory/memory_manager.dart';
import 'package:consciousness_sim/perception/sensory_input.dart';
import 'package:consciousness_sim/reasoning/conceptual_graph.dart';
import 'package:consciousness_sim/reasoning/inference_engine.dart';
import 'package:consciousness_sim/utils/logger.dart';
import 'package:consciousness_sim/utils/metrics.dart';

// ─────────────────────────────────────────────
// ConsciousnessConfig
// ─────────────────────────────────────────────

/// Configuration options for a [Consciousness] instance.
class ConsciousnessConfig {
  const ConsciousnessConfig({
    this.workspaceCapacity = 7,
    this.attentionThreshold = 0.30,
    this.enableLongTermLearning = true,
    this.enableContinuousDecay = true,
    this.decayIntervalSeconds = 5,
    this.memoryConsolidationIntervalMinutes = 10,
    this.logLevel = LogLevel.info,
    this.name = 'Mind',
  })  : assert(workspaceCapacity >= 1 && workspaceCapacity <= 20),
        assert(attentionThreshold >= 0.0 && attentionThreshold <= 1.0),
        assert(decayIntervalSeconds >= 1),
        assert(memoryConsolidationIntervalMinutes >= 1);

  /// Maximum number of concepts in the global workspace (Miller 7 ± 2).
  final int workspaceCapacity;

  /// Minimum salience score for a concept to enter the spotlight.
  final double attentionThreshold;

  /// Whether new experiences are permanently encoded in long-term memory.
  final bool enableLongTermLearning;

  /// Whether activation decay runs in a background timer.
  final bool enableContinuousDecay;

  /// How often (seconds) the background decay timer fires.
  final int decayIntervalSeconds;

  /// How often (minutes) memory consolidation runs.
  final int memoryConsolidationIntervalMinutes;

  /// Verbosity of internal logging.
  final LogLevel logLevel;

  /// A human-readable name for this consciousness instance.
  final String name;
}

// ─────────────────────────────────────────────
// Consciousness
// ─────────────────────────────────────────────

/// The main entry point — a fully integrated conscious agent.
///
/// ### Quick start
/// ```dart
/// final mind = Consciousness();
/// await mind.observe('a cat is on the table');
/// await mind.observe('the cat looks hungry');
/// print(mind.think()); // "The cat probably wants food from the table"
/// ```
///
/// ### Architecture overview
/// ```
/// observe(input)
///     ↓
/// PerceptionProcessor  → extract features & tokens
///     ↓
/// AttentionSpotlight   → rank by salience, select focus
///     ↓
/// WorkspaceManager     → broadcast to global workspace
///     ↓
/// BindingEngine        → create / reinforce concept links
///     ↓
/// ConceptualGraph      → update semantic network
///     ↓
/// InferenceEngine      → derive new conclusions
///     ↓
/// MemoryManager        → encode experiences
///     ↓
/// think() / getCurrentState()
/// ```
class Consciousness {
  Consciousness({ConsciousnessConfig? config})
      : _config = config ?? const ConsciousnessConfig() {
    _logger = ConsciousnessLogger(
      _config.name,
      level: _config.logLevel,
    );

    _workspace = WorkspaceManager(
      capacity: _config.workspaceCapacity,
      logger: _logger,
    );

    _attention = AttentionSpotlight(
      attentionThreshold: _config.attentionThreshold,
      logger: _logger,
    );

    _binding = BindingEngine(logger: _logger);

    _memory = MemoryManager(
      enableLongTermLearning: _config.enableLongTermLearning,
      logger: _logger,
    );

    _graph = ConceptualGraph(logger: _logger);

    _inference = InferenceEngine(
      graph: _graph,
      memory: _memory,
      logger: _logger,
    );

    _perception = SensoryInputProcessor(logger: _logger);

    _coherence = CoherenceManager(logger: _logger);

    _metrics = ConsciousnessMetrics();

    if (_config.enableContinuousDecay) {
      _startDecayTimer();
    }
    if (_config.enableLongTermLearning) {
      _startConsolidationTimer();
    }

    _logger.info('Consciousness "${_config.name}" initialised '
        '(workspace: ${_config.workspaceCapacity}, '
        'threshold: ${_config.attentionThreshold})');
  }

  // ── Subsystems ─────────────────────────────
  late final WorkspaceManager _workspace;
  late final AttentionSpotlight _attention;
  late final BindingEngine _binding;
  late final MemoryManager _memory;
  late final ConceptualGraph _graph;
  late final InferenceEngine _inference;
  late final SensoryInputProcessor _perception;
  late final CoherenceManager _coherence;
  late final ConsciousnessMetrics _metrics;
  late final ConsciousnessLogger _logger;

  final ConsciousnessConfig _config;
  final _uuid = const Uuid();

  // ── Background timers ──────────────────────
  Timer? _decayTimer;
  Timer? _consolidationTimer;

  // ── Processing state ───────────────────────
  final List<Perception> _perceptionBuffer = [];

  // ── PUBLIC API ─────────────────────────────

  /// Observes a [rawInput] via the default [PerceptionModality.linguistic].
  ///
  /// The input is processed through the full perceptual pipeline:
  /// feature extraction → attention evaluation → workspace broadcast
  /// → conceptual binding → memory encoding.
  Future<void> observe(String rawInput) async =>
      _observe(rawInput, PerceptionModality.linguistic);

  /// Observes visual information (descriptions, scene text, etc.).
  Future<void> observeVisual(String description) async =>
      _observe(description, PerceptionModality.visual);

  /// Observes auditory information.
  Future<void> observeAuditory(String description) async =>
      _observe(description, PerceptionModality.auditory);

  /// Observes tactile / physical sensation information.
  Future<void> observeTactile(String description) async =>
      _observe(description, PerceptionModality.tactile);

  /// Observes abstract / conceptual information.
  Future<void> observeAbstract(String description) async =>
      _observe(description, PerceptionModality.abstract);

  // ── Process all buffered perceptions ───────

  /// Processes the buffered perceptions and returns the resulting
  /// [ConsciousState].  Typically called after one or more [observe] calls.
  Future<ConsciousState> process() async {
    final startTime = DateTime.now();
    _logger.info('Processing ${_perceptionBuffer.length} buffered perception(s)');

    // Step 1 — drain the perception buffer into the workspace
    for (final percept in List.of(_perceptionBuffer)) {
      await _integratePerception(percept);
    }
    _perceptionBuffer.clear();

    // Step 2 — binding pass over current workspace
    final active = _workspace.getActiveWorkspace();
    final bindings = _binding.bindWorkspace(
      active,
      _graph.getAllNodes(),
    );
    for (final b in bindings) {
      _graph.linkConcepts(
        b.conceptId1,
        b.conceptId2,
        relationshipType: b.relationshipType,
        strength: b.strength,
        label: b.label,
      );
    }

    // Step 3 — coherence check
    final coherence = _coherence.evaluate(
      workspaceConcepts: active,
      graph: _graph,
    );

    // Step 4 — inference generation
    final inferences = _inference.runInferenceCycle(active);

    // Step 5 — record metrics
    final elapsed =
        DateTime.now().difference(startTime).inMilliseconds;
    _metrics.recordCycle(
      inferenceCount: inferences.length,
      bindingCount: bindings.length,
      latencyMs: elapsed,
      coherence: coherence,
      workspaceSize: active.length,
    );

    final focus = _workspace.getSpotlightFocus();
    final state = ConsciousState(
      workspace: active,
      focusedConceptId: focus?.id ?? '',
      activationMap: _workspace.activationSnapshot,
      inferencesGenerated: inferences,
      coherence: coherence,
    );

    _logger.info(
        'Process cycle complete: '
        '${inferences.length} inference(s), '
        'coherence: ${coherence.toStringAsFixed(2)}, '
        '${elapsed}ms');

    return state;
  }

  // ── Thinking ───────────────────────────────

  /// Synthesises the currently active workspace into a natural-language thought.
  ///
  /// This is the primary "output" of consciousness — what the system
  /// is currently "thinking" given its workspace contents.
  String think() {
    final active = _workspace.getActiveWorkspace();
    if (active.isEmpty) {
      return '(No active thoughts — nothing has been observed yet.)';
    }

    // Run a quick inference pass on the current workspace
    final inferences = _inference.runInferenceCycle(active);

    if (inferences.isNotEmpty) {
      final best = inferences
          .reduce((a, b) => a.confidence >= b.confidence ? a : b);
      return best.conclusion;
    }

    return _inference.synthesiseThought(active);
  }

  /// Returns a structured thought with metadata.
  Map<String, dynamic> thinkDetailed() {
    final active = _workspace.getActiveWorkspace();
    final inferences = _inference.runInferenceCycle(active);

    return {
      'thought': think(),
      'focus': _attention.primaryFocusId ?? '',
      'workspace_size': active.length,
      'inference_count': inferences.length,
      'top_inferences': inferences
          .take(3)
          .map((i) => {'conclusion': i.conclusion, 'confidence': i.confidence})
          .toList(),
      'coherence': _workspace.computeCoherence(),
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  // ── Memory ─────────────────────────────────

  /// Recalls memories related to the given [query] string.
  List<Memory> recall(String query) {
    final results = _memory.retrieveByContext(query);
    _metrics.recordMemoryRetrieval();
    _logger.debug('Recall "$query" → ${results.length} memory/memories');
    return results;
  }

  /// Recalls episodic memories (specific past events).
  List<Memory> recallEpisodes(String query) {
    _metrics.recordMemoryRetrieval();
    return _memory.episodic.search(query);
  }

  /// Recalls semantic memories (general facts / knowledge).
  List<Memory> recallFacts(String query) {
    _metrics.recordMemoryRetrieval();
    return _memory.semantic.search(query);
  }

  // ── Attention control ───────────────────────

  /// Redirects attention toward the listed [priorities] (concept IDs or labels).
  void refocusAttention(List<String> priorities) {
    _attention.rebalance(priorities);
    _logger.info('Attention refocused on: ${priorities.join(', ')}');
  }

  /// Causes the spotlight to wander over [targets] with [dwellTime] each.
  Future<void> wanderAttention(
    List<String> targets,
    Duration dwellTime,
  ) async {
    await _attention.wanderAttention(targets, dwellTime);
  }

  // ── State ───────────────────────────────────

  /// Returns the current [ConsciousState] without running a new process cycle.
  ConsciousState getCurrentState() {
    final active = _workspace.getActiveWorkspace();
    final focus = _workspace.getSpotlightFocus();
    final inferences = _inference.runInferenceCycle(active);
    return ConsciousState(
      workspace: active,
      focusedConceptId: focus?.id ?? '',
      activationMap: _workspace.activationSnapshot,
      inferencesGenerated: inferences,
      coherence: _workspace.computeCoherence(),
    );
  }

  /// Exposes performance metrics collected across all processing cycles.
  ConsciousnessMetrics get metrics => _metrics;

  /// Exposes the underlying workspace manager (for advanced use).
  WorkspaceManager get workspace => _workspace;

  /// Exposes the conceptual graph (for advanced use).
  ConceptualGraph get conceptGraph => _graph;

  /// Exposes the memory manager (for advanced use).
  MemoryManager get memoryManager => _memory;

  // ── Learning ────────────────────────────────

  /// Explicitly teaches the consciousness a new rule or fact.
  ///
  /// Adds an [InferenceRule] directly to the inference engine.
  void learn(InferenceRule rule) {
    _inference.addRule(rule);
    _logger.info('Learned new rule: "${rule.name}"');
  }

  /// Provides feedback on the last thought (reinforces or weakens memories).
  Future<void> learnFrom(String outcome, {bool positive = true}) async {
    final active = _workspace.getActiveWorkspace();
    for (final concept in active) {
      _memory.reinforceAssociation(concept.id, outcome,
          strength: positive ? 0.2 : -0.1);
    }
    _logger.info(
        'Learned from outcome: "$outcome" (positive: $positive)');
  }

  // ── Lifecycle ───────────────────────────────

  /// Adds a [ConsciousnessPlugin] to the processing pipeline.
  void addPlugin(ConsciousnessPlugin plugin) {
    _plugins.add(plugin);
    _logger.info('Plugin added: "${plugin.name}"');
  }

  final List<ConsciousnessPlugin> _plugins = [];

  /// Resets the consciousness to an empty state (clears workspace, buffers).
  /// Long-term memory and the conceptual graph are preserved.
  void reset() {
    _workspace.clear();
    _perceptionBuffer.clear();
    _attention.cancelWander();
    _logger.info('Consciousness reset (short-term state cleared)');
  }

  /// Disposes all timers and releases resources.
  void dispose() {
    _decayTimer?.cancel();
    _consolidationTimer?.cancel();
    _logger.info('Consciousness "${_config.name}" disposed');
  }

  // ── Private implementation ─────────────────

  Future<void> _observe(
    String rawInput,
    PerceptionModality modality,
  ) async {
    final percept = _perception.process(
      rawInput,
      modality: modality,
      id: _uuid.v4(),
    );

    // Buffer the perception for the next process() call
    _perceptionBuffer.add(percept);

    // Eagerly integrate for immediate responsiveness
    await _integratePerception(percept);

    // Store in working memory
    _memory.working.push(
      Memory(
        id: _uuid.v4(),
        content: rawInput,
        type: MemoryType.working,
        associatedConceptIds: percept.tokens.take(5).toList(),
      ),
    );

    _logger.debug('Observed: "$rawInput" [${modality.name}]');
  }

  Future<void> _integratePerception(Perception percept) async {
    // 1. Extract concepts from perception
    final concepts = _perception.extractConcepts(percept, _uuid);

    // 2. Update context relevance based on memory
    for (final concept in concepts) {
      concept.contextualRelevance = _memory.computeContextualRelevance(
        concept.content,
      );
    }

    // 3. Evaluate salience and decide what enters the workspace
    final focusId = _attention.evaluateAndFocus(concepts);

    // 4. Broadcast to workspace
    for (final concept in concepts) {
      _workspace.broadcast(concept);
      _graph.addConcept(concept.id, concept);
    }

    // 5. Register concepts for temporal binding
    final allNodes = _graph.getAllNodes();
    for (final concept in concepts) {
      final bindings = _binding.registerAndBind(concept, allNodes);
      for (final b in bindings) {
        _graph.linkConcepts(
          b.conceptId1,
          b.conceptId2,
          relationshipType: b.relationshipType,
          strength: b.strength,
          label: b.label,
        );
      }
    }

    // 6. Encode in episodic memory if long-term learning is enabled
    if (_config.enableLongTermLearning) {
      _memory.storeEpisode(percept);
    }

    // 7. Run plugin hooks
    final state = ConsciousState(
      workspace: _workspace.getActiveWorkspace(),
      focusedConceptId: focusId ?? '',
      activationMap: _workspace.activationSnapshot,
      inferencesGenerated: const [],
      coherence: _workspace.computeCoherence(),
    );
    for (final plugin in _plugins) {
      await plugin.process(state);
    }
  }

  void _startDecayTimer() {
    _decayTimer = Timer.periodic(
      Duration(seconds: _config.decayIntervalSeconds),
      (_) {
        // The workspace handles its own decay internally; this timer
        // triggers additional memory decay.
        _memory.applyTemporalDecay();
      },
    );
  }

  void _startConsolidationTimer() {
    _consolidationTimer = Timer.periodic(
      Duration(minutes: _config.memoryConsolidationIntervalMinutes),
      (_) async {
        await _memory.consolidateMemories();
        _logger.debug('Memory consolidation pass completed');
      },
    );
  }

  @override
  String toString() =>
      'Consciousness("${_config.name}", '
      'workspace: ${_workspace.size}/${_config.workspaceCapacity}, '
      'graph: ${_graph.nodeCount} nodes, '
      'episodic: ${_memory.episodic.count} memories)';
}

// ─────────────────────────────────────────────
// ConsciousnessPlugin
// ─────────────────────────────────────────────

/// An extension hook that receives the [ConsciousState] after each
/// integration cycle.
///
/// Use plugins for: emotion detection, personality modelling,
/// external API calls, logging to UI, etc.
abstract class ConsciousnessPlugin {
  const ConsciousnessPlugin();

  /// The unique name of this plugin.
  String get name;

  /// Called once per integration cycle with the current [state].
  Future<void> process(ConsciousState state);
}

// ─────────────────────────────────────────────
// EmotionDetectorPlugin — example plugin
// ─────────────────────────────────────────────

/// Example plugin: logs when highly emotional concepts enter the workspace.
class EmotionDetectorPlugin extends ConsciousnessPlugin {
  const EmotionDetectorPlugin({this.threshold = 0.6});

  final double threshold;

  @override
  String get name => 'EmotionDetector';

  @override
  Future<void> process(ConsciousState state) async {
    final emotional = state.workspace.where(
      (c) =>
          c.emotionalWeight >= threshold &&
          c.emotionalValence != EmotionalValence.neutral,
    );
    for (final c in emotional) {
      // ignore: avoid_print
      print('[EmotionDetector] Emotional concept detected: '
          '"${c.content}" '
          '(${c.emotionalValence.name}, '
          'intensity: ${c.emotionalIntensity.toStringAsFixed(2)})');
    }
  }
}

// ─────────────────────────────────────────────
// AgentMindConfig
// ─────────────────────────────────────────────

/// Configuration for the autonomous agent layer wired on top of [Consciousness].
class AgentMindConfig {
  const AgentMindConfig({
    this.loopConfig = const AgentLoopConfig(),
    this.llmCoreConfig = const LLMCoreConfig(),
    this.memoryCapacity = 2000,
    this.enableReflection = true,
    this.registerBuiltinTools = true,
    this.extraTools = const [],
  });

  /// Configuration for the autonomous execution loop.
  final AgentLoopConfig loopConfig;

  /// Configuration for the LLM reasoning core.
  final LLMCoreConfig llmCoreConfig;

  /// Capacity of the agent-specific memory store.
  final int memoryCapacity;

  /// Whether to attach a [SelfReflectionModule] to the loop.
  final bool enableReflection;

  /// Whether to register all 6 built-in tools automatically.
  final bool registerBuiltinTools;

  /// Additional custom tools to register on startup.
  final List<Tool> extraTools;
}

// ─────────────────────────────────────────────
// AgentMind
// ─────────────────────────────────────────────

/// Wraps a [Consciousness] instance with a fully autonomous agent layer.
///
/// [AgentMind] connects:
///   - [LLMCore]            — reasoning brain (requires an [LLMProvider])
///   - [PlanningEngine]     — goal decomposition + ExecutionDAG
///   - [AgentLoopController]— the observe→plan→decide→execute loop
///   - [AgentMemoryStore]   — agent-scoped long-term memory
///   - [SelfReflectionModule] (optional) — meta-cognitive error correction
///
/// The existing [Consciousness] workspace is used as the source of
/// `workspaceConcepts` fed into every LLM prompt, bridging cognitive
/// simulation with autonomous goal pursuit.
///
/// ### Quick start
/// ```dart
/// final mind = Consciousness();
/// final agent = mind.asAgent(
///   provider: HttpLLMProvider(apiKey: 'sk-...', model: 'gpt-4o'),
/// );
///
/// final result = await agent.pursue(
///   AgentGoal(
///     id: 'g-001',
///     description: 'What is the weather in Algiers right now?',
///     successCriteria: ['Temperature reported', 'Conditions described'],
///   ),
/// );
///
/// print(result.success ? 'Done: ${result.summary}' : 'Failed: ${result.error}');
/// ```
class AgentMind {
  AgentMind._({
    required Consciousness consciousness,
    required LLMProvider provider,
    AgentMindConfig? config,
    ConsciousnessLogger? logger,
  })  : _consciousness = consciousness,
        _config = config ?? const AgentMindConfig(),
        _logger = logger ??
            ConsciousnessLogger(
              '${consciousness._config.name}/Agent',
              level: consciousness._config.logLevel,
            ) {
    // Build shared memory store
    _agentMemory = AgentMemoryStore(
      capacity: _config.memoryCapacity,
      logger: _logger,
    );

    // Build LLM core
    _llm = LLMCore(
      provider: provider,
      memory: _agentMemory,
      config: _config.llmCoreConfig,
      logger: _logger,
    );

    // Build planning engine
    _planner = PlanningEngine(
      llmCore: _llm,
      logger: _logger,
    );

    // Build tool registry
    _registry = ToolRegistry(logger: _logger);
    if (_config.registerBuiltinTools) {
      BuiltinToolset.registerAll(_registry);
    }
    for (final tool in _config.extraTools) {
      _registry.register(tool);
    }

    // Build optional reflection module
    final reflection = _config.enableReflection
        ? SelfReflectionModule(
            memory: _agentMemory,
            llm: _llm,
            logger: _logger,
          )
        : null;

    // Build the loop controller
    _loop = AgentLoopController(
      llm: _llm,
      memory: _agentMemory,
      planner: _planner,
      registry: _registry,
      environment: _WorkspaceEnvironmentAdapter(_consciousness),
      config: _config.loopConfig,
      reflection: reflection,
      logger: _logger,
    );

    _logger.info(
        'AgentMind initialised '
        '(tools: ${_registry.count}, '
        'reflection: ${_config.enableReflection})');
  }

  final Consciousness _consciousness;
  final AgentMindConfig _config;
  final ConsciousnessLogger _logger;

  late final AgentMemoryStore _agentMemory;
  late final LLMCore _llm;
  late final PlanningEngine _planner;
  late final ToolRegistry _registry;
  late final AgentLoopController _loop;

  // ── PUBLIC API ──────────────────────────────

  /// The agent-scoped long-term memory store.
  AgentMemoryStore get memory => _agentMemory;

  /// The LLM reasoning core.
  LLMCore get llm => _llm;

  /// The planning engine.
  PlanningEngine get planner => _planner;

  /// The tool registry (register custom tools here).
  ToolRegistry get tools => _registry;

  /// The loop controller (listen to events here).
  AgentLoopController get loop => _loop;

  /// Broadcast stream of [AgentLoopEvent]s emitted during execution.
  Stream<AgentLoopEvent> get events => _loop.events;

  /// Whether the agent loop is currently running.
  bool get isRunning => _loop.isRunning;

  /// Runs the autonomous agent loop for [goal] and returns an [AgentRunResult].
  ///
  /// The method:
  /// 1. Flushes the [Consciousness] workspace into the first context window.
  /// 2. Runs the full observe→plan→decide→execute loop.
  /// 3. Archives the result in long-term memory.
  Future<AgentRunResult> pursue(AgentGoal goal) async {
    _logger.info('Pursuing goal: "${goal.description}"');

    // Sync workspace concepts into agent memory before starting
    _syncWorkspaceToMemory(goal.id);

    final result = await _loop.run(goal);

    _logger.info(
        'Goal "${goal.description}" → '
        '${result.success ? "SUCCESS" : "FAILED"} '
        '(${result.iterations} iterations)');

    return result;
  }

  /// Requests a graceful stop of the currently running loop.
  void stop() => _loop.stop();

  /// Disposes all agent resources.  The underlying [Consciousness] is NOT
  /// disposed — call [Consciousness.dispose] separately if needed.
  Future<void> dispose() async {
    await _loop.dispose();
  }

  // ── Private ─────────────────────────────────

  /// Copies active workspace concepts into agent memory so the LLM prompt
  /// can reference what the consciousness subsystem is currently "thinking".
  void _syncWorkspaceToMemory(String goalId) {
    final active = _consciousness.workspace.getActiveWorkspace();
    if (active.isEmpty) return;

    for (final concept in active) {
      _agentMemory.remember(
        content: concept.content,
        type: AgentMemoryType.observation,
        goalId: goalId,
        importance: concept.calculateSalience().clamp(0.1, 0.9),
      );
    }

    _logger.debug(
        'Synced ${active.length} workspace concept(s) into agent memory');
  }

  @override
  String toString() =>
      'AgentMind('
      'consciousness: ${_consciousness._config.name}, '
      'tools: ${_registry.count}, '
      'llm: ${_llm.toString()})';
}

// ─────────────────────────────────────────────
// _WorkspaceEnvironmentAdapter (private)
// ─────────────────────────────────────────────

/// Bridges the [Consciousness] perception buffer to the agent's
/// [EnvironmentAdapter] interface.
///
/// Every time the loop polls for new observations, this adapter drains the
/// consciousness workspace delta (concepts that appeared since the last poll)
/// and converts them to [AgentObservation]s.
class _WorkspaceEnvironmentAdapter implements EnvironmentAdapter {
  _WorkspaceEnvironmentAdapter(this._consciousness);

  final Consciousness _consciousness;
  int _lastSnapshotSize = 0;

  @override
  Future<List<AgentObservation>> poll() async {
    final active = _consciousness.workspace.getActiveWorkspace();
    if (active.length <= _lastSnapshotSize) return const [];

    // Only return concepts that are NEW since the last poll
    final newConcepts = active.skip(_lastSnapshotSize).toList();
    _lastSnapshotSize = active.length;

    return newConcepts
        .map((c) => AgentObservation(
              id: c.id,
              content: c.content,
              source: 'consciousness_workspace',
              confidence: c.calculateSalience().clamp(0.1, 1.0),
            ))
        .toList();
  }

  @override
  Future<void> dispose() async {
    _lastSnapshotSize = 0;
  }
}

// ─────────────────────────────────────────────
// Consciousness.asAgent() extension method
// ─────────────────────────────────────────────

/// Extension on [Consciousness] that creates an [AgentMind] wrapper.
extension ConsciousnessAgentExtension on Consciousness {
  /// Creates an [AgentMind] that layers autonomous agent capabilities on top
  /// of this [Consciousness] instance.
  ///
  /// The agent shares the consciousness workspace: concepts perceived by the
  /// [Consciousness] are visible as observations to the agent loop, creating
  /// a unified cognitive + agentic system.
  ///
  /// ### Parameters
  /// - [provider]  — the LLM backend (required)
  /// - [config]    — optional tuning (tools, reflection, memory capacity)
  /// - [logger]    — optional logger override
  ///
  /// ### Example
  /// ```dart
  /// final mind = Consciousness(config: ConsciousnessConfig(name: 'Atlas'));
  /// await mind.observe('The user wants to know about climate change');
  /// await mind.process();
  ///
  /// final agent = mind.asAgent(
  ///   provider: MockLLMProvider(responses: ['{"action":"complete","reason":"Done"}'])
  /// );
  ///
  /// final result = await agent.pursue(AgentGoal(
  ///   id: 'goal-1',
  ///   description: 'Explain climate change to a 10-year-old',
  /// ));
  /// ```
  AgentMind asAgent({
    required LLMProvider provider,
    AgentMindConfig? config,
    ConsciousnessLogger? logger,
  }) =>
      AgentMind._(
        consciousness: this,
        provider: provider,
        config: config,
        logger: logger,
      );
}
