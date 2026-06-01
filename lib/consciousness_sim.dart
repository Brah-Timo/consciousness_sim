/// # consciousness_sim
///
/// An advanced Dart library simulating machine consciousness based on
/// **Global Workspace Theory** (Baars, 1988) — now extended with a full
/// **autonomous AI agent framework**.
///
/// ## Architecture overview
///
/// ```
/// consciousness_sim
/// ├── core/          ← Consciousness, WorkspaceManager, AttentionSpotlight, BindingEngine
/// ├── memory/        ← EpisodicMemory, SemanticMemory, WorkingMemory, MemoryManager
/// ├── perception/    ← SensoryInputProcessor, FeatureExtractor, PerceptionBuffer
/// ├── reasoning/     ← InferenceEngine, ConceptualGraph, CausalInference, PatternRecognizer
/// ├── integration/   ← CrossModalBinding, SynchronizationManager, CoherenceManager
/// ├── utils/         ← ConsciousnessLogger, ConsciousnessMetrics, ConsciousnessVisualizer
/// │
/// └── agent/         ← AUTONOMOUS AGENT FRAMEWORK (NEW)
///     ├── agent_models.dart       ← AgentGoal, AgentTask, AgentDecision, AgentContext
///     ├── memory/                 ← AgentMemoryStore (inverted-index, LRU eviction)
///     ├── llm/                    ← LLMCore, LLMProvider (Echo/Mock/Http)
///     ├── tools/                  ← Tool, ToolRegistry, ToolRouter, 6 built-in tools
///     ├── planning/               ← PlanningEngine, ExecutionDAG
///     ├── loop/                   ← AgentLoopController, EnvironmentAdapter
///     └── reflection/             ← SelfReflectionModule
/// ```
///
/// ## Consciousness quick start
///
/// ```dart
/// import 'package:consciousness_sim/consciousness_sim.dart';
///
/// Future<void> main() async {
///   final mind = Consciousness();
///
///   await mind.observe('a cat is sitting on the table');
///   await mind.observe('the cat looks hungry');
///   await mind.observe('there is fish on the table');
///
///   print(mind.think());
///   // → "The cat will likely try to eat the fish."
/// }
/// ```
///
/// ## Autonomous agent quick start
///
/// ```dart
/// import 'package:consciousness_sim/consciousness_sim.dart';
///
/// Future<void> main() async {
///   final mind = Consciousness();
///
///   // Upgrade to autonomous agent with one call
///   final agent = mind.asAgent(
///     provider: MockLLMProvider(responses: [
///       '{"action":"use_tool","tool":"calculate","input":{"expression":"42*2"},"thought":"Computing"}',
///       '{"action":"complete","reason":"Calculation done: 84"}',
///     ]),
///   );
///
///   final result = await agent.pursue(AgentGoal(
///     id: 'g-001',
///     description: 'Calculate 42 * 2',
///     successCriteria: ['Result returned'],
///   ));
///
///   print(result.success ? result.summary : result.error);
/// }
/// ```
library consciousness_sim;

// ── Core ─────────────────────────────────────

/// Data models shared across all subsystems.
export 'core/models.dart'
    show
        // Enums
        PerceptionModality,
        RelationshipType,
        MemoryType,
        EmotionalValence,
        // Value objects
        SemanticVector,
        // Entities
        Concept,
        ConceptNode,
        ConceptEdge,
        Memory,
        Inference,
        Perception,
        InferenceRule,
        Pattern,
        CausalRelationship,
        ConsciousState;

/// The global workspace — the broadcast medium of consciousness.
export 'core/workspace.dart' show WorkspaceManager;

/// Selective attention spotlight.
export 'core/attention.dart' show AttentionSpotlight;

/// Conceptual binding engine.
export 'core/binding.dart' show BindingEngine, BindingResult;

/// The main Consciousness class, agent extension, and configuration.
export 'core/consciousness.dart'
    show
        Consciousness,
        ConsciousnessConfig,
        ConsciousnessPlugin,
        EmotionDetectorPlugin,
        // Agent integration
        AgentMind,
        AgentMindConfig,
        ConsciousnessAgentExtension;

// ── Memory ────────────────────────────────────

/// Episodic (event-based) memory store.
export 'memory/episodic_memory.dart' show EpisodicMemory;

/// Semantic (fact-based) memory store.
export 'memory/semantic_memory.dart' show SemanticMemory, SemanticFact;

/// Short-term working memory buffer.
export 'memory/working_memory.dart' show WorkingMemory;

/// Unified memory manager orchestrating all memory subsystems.
export 'memory/memory_manager.dart' show MemoryManager;

// ── Perception ────────────────────────────────

/// Full perceptual processing pipeline.
export 'perception/sensory_input.dart' show SensoryInputProcessor;

/// Linguistic / sensory feature extractor.
export 'perception/feature_extraction.dart'
    show FeatureExtractor, ExtractedFeatures;

/// Pre-attentive sensory buffer.
export 'perception/perception_buffer.dart' show PerceptionBuffer;

// ── Reasoning ─────────────────────────────────

/// Semantic concept graph.
export 'reasoning/conceptual_graph.dart' show ConceptualGraph;

/// Inference engine — forward-chaining, causal, associative, memory-driven.
export 'reasoning/inference_engine.dart' show InferenceEngine;

/// Causal relationship detector.
export 'reasoning/causal_inference.dart' show CausalInferenceEngine;

/// Pattern recognition over concept streams.
export 'reasoning/pattern_recognizer.dart' show PatternRecognizer;

// ── Integration ───────────────────────────────

/// Cross-modal sensory binding.
export 'integration/cross_modal_binding.dart'
    show CrossModalBinding, MultiModalPercept;

/// Stream synchronisation manager.
export 'integration/synchronization.dart'
    show SynchronizationManager, ProcessingStream, SyncEvent;

/// Workspace coherence evaluator.
export 'integration/coherence_manager.dart'
    show CoherenceManager, CoherenceReport;

// ── Utils ─────────────────────────────────────

/// Structured logger for all subsystems.
export 'utils/logger.dart' show ConsciousnessLogger, LogLevel, LogEntry;

/// Performance metrics collector.
export 'utils/metrics.dart' show ConsciousnessMetrics;

/// ASCII visualisation utilities.
export 'utils/visualization.dart' show ConsciousnessVisualizer;

// ═════════════════════════════════════════════
// AGENT FRAMEWORK (NEW — Autonomous AI Agent)
// ═════════════════════════════════════════════

// ── Agent models ──────────────────────────────

/// Core data types for the autonomous agent framework.
///
/// Includes [AgentGoal], [AgentTask], [AgentDecision], [AgentContext],
/// [AgentObservation], [AgentMemoryEntry], [AgentRunResult], and enums.
export 'agent/agent_models.dart'
    show
        AgentGoal,
        AgentTask,
        TaskStatus,
        TaskResult,
        AgentObservation,
        AgentDecision,
        AgentDecisionType,
        AgentContext,
        AgentMemoryEntry,
        AgentMemoryType,
        AgentRunResult;

// ── Agent memory ──────────────────────────────

/// Long-term memory store with keyword index, recency scoring, and eviction.
export 'agent/memory/agent_memory_store.dart' show AgentMemoryStore;

// ── LLM layer ────────────────────────────────

/// LLM provider abstraction and built-in implementations.
///
/// - [LLMProvider] — abstract interface
/// - [EchoLLMProvider] — echoes the last user message (debug)
/// - [MockLLMProvider] — keyword heuristics + response queue (testing)
/// - [HttpLLMProvider] — OpenAI-compatible HTTP backend (production)
/// - [LLMMessage], [LLMRequest], [LLMResponse] — request/response types
export 'agent/llm/llm_provider.dart'
    show
        LLMMessage,
        LLMRequest,
        LLMResponse,
        LLMProvider,
        EchoLLMProvider,
        MockLLMProvider,
        HttpLLMProvider,
        LLMProviderException;

/// LLM orchestration: prompt building, context compression, response parsing.
///
/// [LLMCore.reason] converts an [AgentContext] into an [AgentDecision].
export 'agent/llm/llm_core.dart' show LLMCore, LLMCoreConfig, LLMCoreException;

// ── Tool system ───────────────────────────────

/// Tool base class, result type, registry, and router.
export 'agent/tools/tool_interface.dart'
    show Tool, ToolResult, ToolRegistry, ToolRouter;

/// Six built-in tools + registration helper.
///
/// Tools: search_web, calculate, read_file, write_file, call_api, schedule_task
export 'agent/tools/builtin_tools.dart'
    show
        SearchWebTool,
        CalculateTool,
        ReadFileTool,
        WriteFileTool,
        CallApiTool,
        ScheduleTaskTool,
        BuiltinToolset;

// ── Planning engine ───────────────────────────

/// Goal decomposition and execution DAG.
///
/// [PlanningEngine] builds and tracks an [ExecutionDAG] of [AgentTask]s.
export 'agent/planning/planning_engine.dart'
    show ExecutionDAG, PlanningEngine;

// ── Agent loop ────────────────────────────────

/// The continuous autonomous execution loop.
///
/// [AgentLoopController.run] drives the full
/// observe→retrieveMemory→plan→decide→execute→updateMemory→checkComplete cycle.
export 'agent/loop/agent_loop.dart'
    show
        AgentLoopController,
        AgentLoopConfig,
        AgentLoopEvent,
        AgentLoopEventType,
        EnvironmentAdapter,
        NullEnvironmentAdapter,
        MockEnvironmentAdapter,
        SelfReflectionStub;

// ── Self-reflection ───────────────────────────

/// Meta-cognitive error-correction layer.
///
/// [SelfReflectionModule] detects task failures, tool loops, stalled progress,
/// and thought spirals — then generates actionable correction insights.
export 'agent/reflection/self_reflection.dart'
    show
        SelfReflectionModule,
        SelfReflectionConfig,
        ReflectionRecord,
        ReflectionTrigger;
