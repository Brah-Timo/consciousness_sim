# PERFORMANCE_GUIDE.md — Optimization & Benchmarks

## 1. Resource Consumption Overview

### Memory Usage

| Component | Size (typical) | Size (max) |
|-----------|---------------|------------|
| WorkspaceManager (7 concepts) | ~2 KB | ~15 KB |
| ConceptualGraph (100 nodes) | ~50 KB | ~5 MB |
| EpisodicMemory (500 entries) | ~200 KB | ~2 MB |
| SemanticMemory (1000 facts) | ~100 KB | ~1 MB |
| WorkingMemory (4 slots) | ~4 KB | ~20 KB |
| PerceptionBuffer (50 items) | ~25 KB | ~100 KB |

### CPU Time (per operation)

| Operation | Typical | Worst Case |
|-----------|---------|------------|
| `observe()` | 1–5 ms | 15 ms |
| `process()` | 10–50 ms | 200 ms |
| `think()` | 2–10 ms | 30 ms |
| Memory search | 1–3 ms | 20 ms |
| Graph BFS (depth 2) | 0.5–5 ms | 50 ms |
| Full inference cycle | 5–30 ms | 100 ms |

---

## 2. Configuration Tuning

### Workspace Capacity

```dart
// For real-time applications (games, robots): keep small
final config = ConsciousnessConfig(workspaceCapacity: 5);  // Fast

// For analytical tasks (medical, research): allow larger
final config = ConsciousnessConfig(workspaceCapacity: 11); // Thorough
```

### Attention Threshold

```dart
// Higher threshold = less concepts enter workspace = faster
ConsciousnessConfig(attentionThreshold: 0.5);  // Strict

// Lower threshold = richer but slower processing
ConsciousnessConfig(attentionThreshold: 0.1);  // Permissive
```

### Decay Interval

```dart
// Infrequent decay = less background work
ConsciousnessConfig(
  enableContinuousDecay: true,
  decayIntervalSeconds: 30,  // Every 30s instead of 5s
);
```

---

## 3. Performance Patterns

### Pattern 1 — Batch observations

```dart
// ❌ Less efficient: process after each observation
for (final obs in observations) {
  await mind.observe(obs);
  await mind.process(); // Runs full cycle each time
}

// ✅ More efficient: buffer then process once
for (final obs in observations) {
  await mind.observe(obs);
}
await mind.process(); // Single consolidated cycle
```

### Pattern 2 — Reset between contexts

```dart
// When switching to a completely unrelated context:
mind.reset();  // Clears workspace only (long-term memory preserved)

// Avoids stale concepts polluting the new workspace
await mind.observe('completely different topic');
```

### Pattern 3 — Lazy initialisation

```dart
// Only enable long-term learning when needed
final quickMind = Consciousness(
  config: ConsciousnessConfig(enableLongTermLearning: false),
);
// Skips episodic encoding — 20-40% faster for single-session use
```

### Pattern 4 — Graph size management

```dart
// The conceptual graph grows unboundedly by default.
// For long-running processes, periodically inspect graph size:

if (mind.conceptGraph.nodeCount > 10000) {
  // Consider using a fresh Consciousness instance
  // or implementing a graph pruning strategy
  print('Graph is large: ${mind.conceptGraph.nodeCount} nodes');
}
```

---

## 4. Heavy Load Scenarios

### High-frequency observations (robot sensor loop)

```dart
// Problem: Robot camera sends 30 frames/second
// Solution: Throttle perception before observe()

var lastObserve = DateTime.now();

void onSensorData(String data) {
  final now = DateTime.now();
  if (now.difference(lastObserve).inMilliseconds < 100) return; // ~10 Hz
  lastObserve = now;
  mind.observe(data); // Don't await in hot path
}
```

### Large language model integration

```dart
// When routing LLM responses through consciousness:
// - Split long text into sentences first
// - Process in chunks, not all at once

final sentences = llmResponse.split('. ');
for (final sentence in sentences.take(5)) { // Limit to 5 sentences
  await mind.observe(sentence);
}
await mind.process();
```

---

## 5. Profiling

```dart
// Track per-cycle performance:
final mind = Consciousness();
// ... observations ...
await mind.process();

// After a few cycles:
print(mind.metrics.report());
// Shows: avg latency, P95 latency, coherence, etc.

// For custom profiling:
final start = DateTime.now();
final state = await mind.process();
final elapsed = DateTime.now().difference(start).inMilliseconds;
print('Cycle took: ${elapsed}ms '
      '(coherence: ${state.coherence.toStringAsFixed(2)})');
```

---

## 6. Memory Consolidation Strategy

```dart
// For long-running agents, run consolidation periodically:

Timer.periodic(Duration(minutes: 30), (_) async {
  final beforeEpisodic = mind.memoryManager.episodic.count;
  await mind.memoryManager.consolidateMemories();
  final afterEpisodic = mind.memoryManager.episodic.count;
  print('Consolidation: episodic ${beforeEpisodic} → ${afterEpisodic}');
  print('  Semantic facts: ${mind.memoryManager.semantic.count}');
});
```

---

## 7. Recommended Configurations by Use Case

| Use Case | workspaceCapacity | attentionThreshold | enableDecay | episodicCapacity |
|----------|------------------|--------------------|-------------|-----------------|
| Game AI (real-time) | 5 | 0.4 | false | 100 |
| Robotics (sensor loop) | 7 | 0.3 | true (30s) | 200 |
| Medical diagnosis | 9 | 0.2 | false | 1000 |
| Conversational agent | 7 | 0.25 | true (10s) | 500 |
| Research / analysis | 11 | 0.1 | false | 2000 |
| Unit testing | 7 | 0.1 | false | 50 |
