# Autonomous Agent Architecture — consciousness_sim

> Version 2.0  ·  Batch 4 of 4  ·  Dart ≥ 3.0

---

## Table of Contents

1. [Overview](#1-overview)
2. [Architectural Layers](#2-architectural-layers)
3. [Component Reference](#3-component-reference)
   - 3.1 [Agent Models](#31-agent-models)
   - 3.2 [LLM Layer](#32-llm-layer)
   - 3.3 [Tool System](#33-tool-system)
   - 3.4 [Planning Engine](#34-planning-engine)
   - 3.5 [Agent Loop Controller](#35-agent-loop-controller)
   - 3.6 [Self-Reflection Module](#36-self-reflection-module)
   - 3.7 [Agent Memory Store](#37-agent-memory-store)
   - 3.8 [AgentMind (integration)](#38-agentmind-integration)
4. [Data Flow](#4-data-flow)
5. [Quick-Start Examples](#5-quick-start-examples)
6. [Extending the Framework](#6-extending-the-framework)
7. [Configuration Reference](#7-configuration-reference)

---

## 1. Overview

`consciousness_sim` v2.0 extends the original Global Workspace Theory (GWT)
cognitive simulation library with a **fully autonomous AI agent framework**
layered on top.

The two layers are **complementary but independent**:

| Layer | Purpose | Entry point |
|-------|---------|-------------|
| **Cognitive** | Perception, attention, workspace, inference | `Consciousness` |
| **Agentic** | Goal pursuit, LLM reasoning, tool calling, planning | `AgentMind` |

The bridge between them is `Consciousness.asAgent()` — a single extension
method that creates an `AgentMind` which uses the consciousness workspace as
the environmental observation source.

---

## 2. Architectural Layers

```
┌─────────────────────────────────────────────────────────────┐
│                     consciousness_sim                        │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              AUTONOMOUS AGENT FRAMEWORK               │  │
│  │                                                      │  │
│  │   AgentMind  (Consciousness.asAgent())               │  │
│  │       │                                              │  │
│  │       ├── AgentLoopController  ←── EnvironmentAdapter│  │
│  │       │       │                                      │  │
│  │       │       ├── observe()   ← polls environment    │  │
│  │       │       ├── retrieveMemory() ← AgentMemoryStore│  │
│  │       │       ├── plan()      ← PlanningEngine       │  │
│  │       │       ├── decide()    ← LLMCore              │  │
│  │       │       ├── execute()   ← ToolRouter           │  │
│  │       │       ├── updateMemory() ← AgentMemoryStore  │  │
│  │       │       └── reflect()   ← SelfReflectionModule │  │
│  │       │                                              │  │
│  │       ├── LLMCore (reason → AgentDecision)           │  │
│  │       │       └── LLMProvider (Echo/Mock/Http)       │  │
│  │       │                                              │  │
│  │       ├── PlanningEngine (goal → ExecutionDAG)       │  │
│  │       │       └── ExecutionDAG (Kahn's topo sort)    │  │
│  │       │                                              │  │
│  │       ├── ToolRegistry + ToolRouter                  │  │
│  │       │       └── 6 built-in tools                   │  │
│  │       │                                              │  │
│  │       ├── AgentMemoryStore (inverted index + LRU)    │  │
│  │       │                                              │  │
│  │       └── SelfReflectionModule (meta-cognition)      │  │
│  │                                                      │  │
│  └──────────────────────────────────────────────────────┘  │
│                         ↕ workspace sync                    │
│  ┌──────────────────────────────────────────────────────┐  │
│  │          COGNITIVE SIMULATION (GWT model)             │  │
│  │                                                      │  │
│  │   Consciousness                                      │  │
│  │       ├── WorkspaceManager   (broadcast medium)      │  │
│  │       ├── AttentionSpotlight (selective focus)       │  │
│  │       ├── BindingEngine      (concept association)   │  │
│  │       ├── MemoryManager      (episodic/semantic/WM)  │  │
│  │       ├── InferenceEngine    (rule-based reasoning)  │  │
│  │       ├── ConceptualGraph    (semantic network)      │  │
│  │       ├── SensoryInputProcessor (perception)         │  │
│  │       └── CoherenceManager  (integration check)     │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. Component Reference

### 3.1 Agent Models

**File**: `lib/agent/agent_models.dart`

| Type | Description |
|------|-------------|
| `AgentGoal` | Top-level objective with `id`, `description`, `successCriteria`, `priority`, `maxIterations` |
| `AgentTask` | Single executable step in the plan DAG; mutable `status`, `result`, `retryCount` |
| `TaskStatus` | Enum: `pending → running → succeeded/failed/skipped` |
| `TaskResult` | Outcome of a task: `success`, `output`, `error`, `toolUsed` |
| `AgentObservation` | Environmental input: `content`, `source`, `confidence` |
| `AgentDecision` | LLM output parsed into one of 5 action types |
| `AgentDecisionType` | `useTool / think / complete / replan / error` |
| `AgentContext` | Snapshot fed to LLM each iteration: goal + tasks + observations + memories |
| `AgentMemoryEntry` | Long-term memory record with composite score `importance × recency` |
| `AgentMemoryType` | `decision / observation / reasoning / reflection / goalCompletion / failure` |
| `AgentRunResult` | Loop termination summary: success, iterations, tasks completed/failed |

---

### 3.2 LLM Layer

**Files**: `lib/agent/llm/llm_provider.dart`, `lib/agent/llm/llm_core.dart`

#### LLMProvider hierarchy

```
LLMProvider (abstract)
  ├── EchoLLMProvider     — echoes last user message; zero latency (debug)
  ├── MockLLMProvider     — response queue + keyword heuristics (testing)
  └── HttpLLMProvider     — OpenAI-compatible /v1/chat/completions (production)
```

#### LLMCore

The brain of the agent. `reason(AgentContext) → Future<AgentDecision>`:

1. **Prompt building** — constructs system + user messages from context
2. **Context compression** — middle-truncation when over token budget
3. **LLM call** — delegates to `LLMProvider.complete()`
4. **Response parsing** — extracts `{...}` from markdown fences, decodes JSON,
   routes to typed `AgentDecision`
5. **Token tracking** — `totalPromptTokens`, `totalCompletionTokens`

**Response schema the LLM must follow:**

```json
{"action":"use_tool","tool":"<name>","input":{...},"thought":"..."}
{"action":"think","thought":"..."}
{"action":"complete","reason":"..."}
{"action":"replan","reason":"..."}
{"action":"error","message":"..."}
```

---

### 3.3 Tool System

**Files**: `lib/agent/tools/tool_interface.dart`, `lib/agent/tools/builtin_tools.dart`

#### Execution flow

```
AgentDecision.useTool
    → ToolRouter.route(name, input)
    → tool.validate(input)          // schema check
    → tool.run(input)               // execution
    → ToolResult                    // back into context as AgentObservation
```

#### Built-in tools

| Tool | Input | Description |
|------|-------|-------------|
| `search_web` | `query: String` | DuckDuckGo JSON API (mock fallback in offline mode) |
| `calculate` | `expression: String` | Safe recursive-descent math evaluator; supports `sqrt`, `abs`, `floor`, `ceil`, `sin`, `cos`, `tan`, `log`, `pi`, `e`, `^` |
| `read_file` | `path: String` | Reads a local file (optional `allowedDirectory` sandbox) |
| `write_file` | `path: String`, `content: String` | Writes a file; creates parent dirs recursively |
| `call_api` | `url`, `method`, `headers?`, `body?` | HTTP GET/POST with 15s timeout |
| `schedule_task` | `task_name`, `delay_seconds` | `Future.delayed` with callback |

#### Implementing a custom tool

```dart
class MyTool extends Tool {
  @override String get name => 'my_tool';
  @override String get description => 'Does something.';
  @override Map<String, String> get inputSchema => {'input': 'The input.'};

  @override
  Future<ToolResult> run(Map<String, dynamic> input) async {
    final value = input['input'] as String? ?? '';
    return ToolResult.success(name, 'Processed: $value');
  }
}

// Register:
agent.tools.register(MyTool());
```

---

### 3.4 Planning Engine

**File**: `lib/agent/planning/planning_engine.dart`

#### ExecutionDAG

A typed directed acyclic graph of `AgentTask` nodes:

- `ready` — tasks whose dependencies all have `succeeded` status
- `topologicalOrder` — Kahn's algorithm for valid execution sequence
- `isComplete` — all tasks succeeded or skipped
- `isFailed` — any task failed with `retryCount >= 2`

#### PlanningEngine

| Method | Description |
|--------|-------------|
| `plan(goal, context)` | Generates initial DAG (LLM-backed or rule-based fallback) |
| `replan(dag, context, reason)` | Preserves succeeded tasks, regenerates the rest |
| `nextTask(dag)` | Returns the highest-complexity ready task |
| `markRunning/Succeeded/Failed/Skipped` | Task lifecycle state machine |
| `summarise(dag)` | Human-readable plan string |

**LLM planning prompt output format:**
```json
[
  {"id":"t1","description":"...","depends_on":[],"tool_hint":"search_web","complexity":0.4},
  {"id":"t2","description":"...","depends_on":["t1"],"tool_hint":null,"complexity":0.3}
]
```

---

### 3.5 Agent Loop Controller

**File**: `lib/agent/loop/agent_loop.dart`

The central execution engine. `run(goal) → Future<AgentRunResult>`:

```
while (iteration < goal.maxIterations):
  1. observe()        — poll EnvironmentAdapter for new observations
  2. retrieveMemory() — fetch relevant past entries from AgentMemoryStore
  3. sync DAG tasks   — inject current plan into context
  4. decide()         — LLMCore.reason(context) → AgentDecision
  5. execute():
     - useTool  → ToolRouter.route() → inject observation → advance DAG task
     - think    → record thought in memory
     - complete → archive goal + return AgentRunResult(success: true)
     - replan   → PlanningEngine.replan() + update context
     - error    → increment error counter; abort if >= maxConsecutiveErrors
  6. checkDAGComplete — if all tasks done, return success
  7. reflect (every N iterations, if SelfReflectionModule attached)
  8. delay (if iterationDelay > 0)
```

**Events stream**: every lifecycle milestone emits an `AgentLoopEvent` on the
`events` broadcast stream — subscribe with `loop.events.listen(...)`.

**EnvironmentAdapter interface:**
```dart
abstract class EnvironmentAdapter {
  Future<List<AgentObservation>> poll();
  Future<void> dispose();
}
```

---

### 3.6 Self-Reflection Module

**File**: `lib/agent/reflection/self_reflection.dart`

Performs meta-cognitive analysis every N iterations.

| Detector | Trigger condition | Severity |
|----------|-------------------|----------|
| `taskFailures` | `failed.length >= maxFailuresBeforeReflect` | 0.5–1.0 |
| `toolCallLoop` | Same tool+input repeated N times in window | 0.7 |
| `stalledProgress` | No task progress for N iterations | 0.4–0.9 |
| `noToolProgress` | Only `think` decisions for N iterations | 0.5 |
| `scheduled` | Periodic (no issue detected) | 0.1 |

When severity ≥ 0.5 and `enableLLMReflection: true`, the module sends a
focused analysis prompt to the LLM and returns a richer insight string.
All insights are stored in `AgentMemoryStore` as `AgentMemoryType.reflection`.

---

### 3.7 Agent Memory Store

**File**: `lib/agent/memory/agent_memory_store.dart`

A flat, high-performance memory store with:

- **Inverted word index** — O(tokens) lookup by keyword
- **Composite scoring** — `importance × exp(-ageH/24)` (24h half-life)
- **LRU eviction** — removes `capacity/10` lowest-scored entries when full
- **Goal archive** — completed goals stored separately for cross-run learning
- **`retrieve(query, maxResults)` ** — keyword overlap + score ranking
- **`summarise(maxEntries, goalId?)`** — compact multi-line string for prompts

---

### 3.8 AgentMind (integration)

**File**: `lib/core/consciousness.dart`

`AgentMind` wires all agent subsystems onto an existing `Consciousness`
instance via the `ConsciousnessAgentExtension.asAgent()` method:

```dart
final mind = Consciousness();
final agent = mind.asAgent(provider: HttpLLMProvider(apiKey: '...'));
final result = await agent.pursue(goal);
```

**`_WorkspaceEnvironmentAdapter`** bridges the consciousness workspace to the
agent loop: each `poll()` call returns workspace concepts that appeared since
the last call as `AgentObservation`s.

---

## 4. Data Flow

```
User / Application
        │
        ▼
   AgentGoal (description, successCriteria, maxIterations)
        │
        ▼
   AgentLoopController.run(goal)
        │
   ┌────┴─────────────────────────────────────────┐
   │  Iteration N                                 │
   │                                              │
   │  EnvironmentAdapter.poll()                   │
   │        → AgentObservation[]                  │
   │        → AgentMemoryStore.remember()         │
   │                 ↓                            │
   │  AgentMemoryStore.retrieve(goal.description) │
   │        → retrieved memories (strings)        │
   │                 ↓                            │
   │  AgentContext { goal, tasks, obs, memories } │
   │                 ↓                            │
   │  LLMCore.reason(context)                     │
   │        → LLMProvider.complete(request)       │
   │        → parse JSON → AgentDecision          │
   │                 ↓                            │
   │  switch decision.type:                       │
   │    useTool  → ToolRouter.route()             │
   │                → ToolResult                  │
   │                → AgentObservation            │
   │    think    → memory.remember(reasoning)     │
   │    complete → return AgentRunResult(✅)      │
   │    replan   → PlanningEngine.replan()        │
   │    error    → error counter                  │
   │                 ↓                            │
   │  Every N iterations:                         │
   │    SelfReflectionModule.reflect()            │
   │        → insight → memory.remember()        │
   └────────────────────────────────────────────┘
        │ (if maxIterations reached)
        ▼
   AgentRunResult(success: false, error: "Max iterations")
```

---

## 5. Quick-Start Examples

### Minimal (no real LLM)

```dart
import 'package:consciousness_sim/consciousness_sim.dart';

Future<void> main() async {
  final memory  = AgentMemoryStore();
  final llm     = LLMCore(provider: MockLLMProvider(responses: [
    '{"action":"use_tool","tool":"calculate","input":{"expression":"2^10"},"thought":""}',
    '{"action":"complete","reason":"2^10 = 1024"}',
  ]), memory: memory);
  final planner = PlanningEngine();
  final tools   = ToolRegistry();
  BuiltinToolset.registerAll(tools);

  final loop = AgentLoopController(
    llm: llm, memory: memory, planner: planner, registry: tools,
  );

  final result = await loop.run(AgentGoal(
    id: 'g1',
    description: 'What is 2 to the power of 10?',
  ));

  print(result.summary);          // "2^10 = 1024"
  print(result.tasksCompleted);   // number of plan tasks completed
  await loop.dispose();
}
```

### Production (real OpenAI API)

```dart
import 'package:consciousness_sim/consciousness_sim.dart';

Future<void> main() async {
  final mind = Consciousness();

  final agent = mind.asAgent(
    provider: HttpLLMProvider(
      apiKey: 'sk-...',
      model: 'gpt-4o',
      baseUrl: 'https://api.openai.com',
    ),
    config: const AgentMindConfig(
      enableReflection: true,
      registerBuiltinTools: true,
      loopConfig: AgentLoopConfig(
        maxConsecutiveErrors: 3,
        reflectionIntervalIterations: 3,
      ),
    ),
  );

  // Listen to events for UI updates
  agent.events.listen((e) {
    if (e.type == AgentLoopEventType.toolExecuted) {
      final r = e.data as ToolResult?;
      print('Tool: ${r?.toolName} → ${r?.outputText.substring(0, 50)}');
    }
  });

  final result = await agent.pursue(AgentGoal(
    id: 'research-001',
    description: 'Research the latest advances in quantum computing',
    successCriteria: [
      'Key breakthrough identified',
      'Timeline reported',
      'Practical implications described',
    ],
    maxIterations: 15,
  ));

  print(result.success ? '✅ ${result.summary}' : '❌ ${result.error}');
  await agent.dispose();
  mind.dispose();
}
```

---

## 6. Extending the Framework

### Custom LLM provider

```dart
class OllamaProvider extends LLMProvider {
  @override String get name => 'ollama-llama3';

  @override
  Future<LLMResponse> complete(LLMRequest request) async {
    // POST to http://localhost:11434/api/chat
    // Parse response → return LLMResponse(text: ..., promptTokens: ..., completionTokens: ...)
    throw UnimplementedError();
  }
}
```

### Custom tool

```dart
class WeatherTool extends Tool {
  @override String get name => 'get_weather';
  @override String get description => 'Gets current weather for a city.';
  @override Map<String, String> get inputSchema => {'city': 'City name.'};

  @override
  Future<ToolResult> run(Map<String, dynamic> input) async {
    final city = input['city'] as String;
    // Call real weather API...
    return ToolResult.success(name, 'Sunny, 22°C in $city');
  }
}

// Register:
agent.tools.register(WeatherTool());
```

### Custom EnvironmentAdapter

```dart
class MessageQueueAdapter implements EnvironmentAdapter {
  final Stream<String> _stream;
  MessageQueueAdapter(this._stream);

  @override
  Future<List<AgentObservation>> poll() async {
    final messages = <String>[];
    await for (final msg in _stream.take(5).timeout(Duration(ms: 100))) {
      messages.add(msg);
    }
    return messages.map((m) => AgentObservation(
      id: Uuid().v4(), content: m, source: 'message_queue')).toList();
  }

  @override Future<void> dispose() async {}
}
```

---

## 7. Configuration Reference

### AgentMindConfig

| Field | Default | Description |
|-------|---------|-------------|
| `loopConfig` | `AgentLoopConfig()` | Loop execution settings |
| `llmCoreConfig` | `LLMCoreConfig()` | LLM prompt/token settings |
| `memoryCapacity` | `2000` | Max agent memory entries |
| `enableReflection` | `true` | Attach SelfReflectionModule |
| `registerBuiltinTools` | `true` | Auto-register all 6 built-in tools |
| `extraTools` | `[]` | Additional custom tools |

### AgentLoopConfig

| Field | Default | Description |
|-------|---------|-------------|
| `maxObservationsPerCycle` | `5` | Max observations kept per context window |
| `maxMemoryRetrievals` | `8` | Memory entries retrieved per cycle |
| `iterationDelay` | `Duration.zero` | Artificial delay between iterations |
| `enableReflection` | `true` | Whether reflection is called |
| `reflectionIntervalIterations` | `3` | How often reflection runs |
| `maxConsecutiveErrors` | `3` | Consecutive errors before abort |
| `emitEvents` | `true` | Whether events stream is populated |

### LLMCoreConfig

| Field | Default | Description |
|-------|---------|-------------|
| `maxContextTokens` | `3000` | Hard token limit per request |
| `maxMemoryEntries` | `8` | Memory snippets in prompt |
| `maxObservations` | `6` | Observations in prompt |
| `temperature` | `0.7` | LLM sampling temperature |
| `maxResponseTokens` | `512` | Max tokens in LLM response |
| `systemPersona` | (default) | System prompt persona string |

### SelfReflectionConfig

| Field | Default | Description |
|-------|---------|-------------|
| `stalledProgressThreshold` | `3` | Iterations with no progress before stall detection |
| `toolLoopWindowSize` | `4` | Window for repeated tool-call detection |
| `maxFailuresBeforeReflect` | `2` | Failures that trigger urgent reflection |
| `noToolProgressThreshold` | `5` | Think-only iterations before spiral detection |
| `maxHistorySize` | `50` | Max reflection records kept |
| `enableLLMReflection` | `true` | Use LLM for severity ≥ 0.5 reflections |
| `minSeverityToStore` | `0.3` | Min severity to persist in AgentMemoryStore |
