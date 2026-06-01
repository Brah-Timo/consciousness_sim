# Changelog

All notable changes to `consciousness_sim` are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [1.0.1] — 2026-06-01
### Fixed
#### Consciousness Engine
- Fixed workspace admission edge case that could allow duplicate concepts under heavy broadcast load.
- Fixed salience normalization overflow when processing extremely large concept streams.
- Fixed temporal binding cleanup issue causing stale bindings to persist longer than intended.

---

## [1.0.0] — 2024-01-01

### Added

#### Consciousness engine
- `Consciousness` — main orchestrator built on Global Workspace Theory (Baars, 1988)
- `WorkspaceManager` — 7±2 concept broadcast buffer with salience-based admission
- `AttentionSpotlight` — focus/defocus, automatic wander, salience computation
- `BindingEngine` — temporal and semantic concept binding with co-activation tracking
- `EpisodicMemory` — event-based autobiographical memory with decay
- `SemanticMemory` — world-knowledge triple store with confidence scoring
- `WorkingMemory` — short-term 4±1 buffer with LRU eviction
- `MemoryManager` — unified retrieval and episodic→semantic consolidation
- `SensoryInputProcessor` — full perceptual pipeline with modality tagging
- `FeatureExtractor` — linguistic features: entities, actions, spatial/temporal markers
- `PerceptionBuffer` — pre-attentive sensory register
- `InferenceEngine` — forward-chaining, causal, associative, and memory-driven rules
- `ConceptualGraph` — directed, weighted semantic network with BFS/DFS/spreading activation
- `CausalInferenceEngine` — Pearl-inspired cause-effect detection from concept streams
- `PatternRecognizer` — co-occurrence, sequence, and cluster pattern discovery
- `CrossModalBinding` — multi-sensory fusion across visual/auditory/tactile modalities
- `SynchronizationManager` — parallel processing stream coordination
- `CoherenceManager` — workspace consistency scoring
- `ConsciousnessPlugin` — extensible processing hooks
- `ConsciousnessLogger` — structured, level-filtered logging
- `ConsciousnessMetrics` — latency, throughput, and P95 tracking
- `ConsciousnessVisualizer` — ASCII workspace/graph rendering

#### Autonomous agent framework (new in v1.0)
- `AgentMind` + `ConsciousnessAgentExtension` — upgrade any `Consciousness` to an
  autonomous agent via `mind.asAgent(provider: ...)`
- `AgentGoal`, `AgentTask`, `AgentDecision`, `AgentContext`, `AgentRunResult` —
  typed data model for goal-driven execution
- `AgentMemoryStore` — inverted word index with composite scoring and LRU eviction
- `LLMProvider` (abstract) + `EchoLLMProvider`, `MockLLMProvider`, `HttpLLMProvider` —
  zero-dependency testing and OpenAI-compatible production backends
- `LLMCore` — prompt assembly, context compression (middle-truncation), JSON parsing,
  token usage tracking; supports all 5 action types: `use_tool`, `think`, `complete`,
  `replan`, `error`
- `Tool`, `ToolResult`, `ToolRegistry`, `ToolRouter` — extensible tool system
- `BuiltinToolset` — 6 ready-to-use tools: `search_web`, `calculate`, `read_file`,
  `write_file`, `call_api`, `schedule_task`
- `_MathParser` — AOT-safe recursive-descent evaluator for `CalculateTool`
- `ExecutionDAG` — Kahn's topological sort; full task state machine
  `pending → running → succeeded / failed / skipped`
- `PlanningEngine` — LLM-backed JSON decomposition + rule-based fallback;
  `replan()` preserves succeeded tasks
- `AgentLoopController` — full autonomous
  `observe → retrieveMemory → plan → decide → execute → updateMemory → checkComplete` cycle
- `EnvironmentAdapter` (abstract) + `NullEnvironmentAdapter`, `MockEnvironmentAdapter`
- `AgentLoopEvent` broadcast stream with 14 event types
- `SelfReflectionModule` — 4 detectors: cascade failures, tool loop, stalled progress,
  thought spiral; optional LLM deep-reflection; history with LRU cap

#### Examples
- `example/basic_consciousness.dart` — consciousness quick-start
- `example/advanced_awareness.dart` — attention control, plugins, metrics
- `example/learning_simulation.dart` — rule learning and inference
- `example/multi_modal_integration.dart` — cross-modal binding
- `example/autonomous_agent.dart` — full agent loop with event stream
- `example/multi_tool_agent.dart` — all 6 tools + custom tool + self-reflection

#### Documentation
- `doc/AGENT_ARCHITECTURE.md` — deep-dive architecture reference
- `THEORY.md` — scientific foundations (GWT, binding theory, memory models)
- `PERFORMANCE_GUIDE.md` — tuning tips and benchmarks

### Dependencies
- `collection: ^1.17.0`
- `equatable: ^2.0.5`
- `http: ^1.2.1`
- `logging: ^1.2.0`
- `meta: ^1.9.0`
- `uuid: ^4.0.0`
