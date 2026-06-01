// example/learning_simulation.dart
// Demonstrates continuous learning: episodic → semantic consolidation
// and inference rule self-improvement over multiple observation cycles.

import 'package:consciousness_sim/consciousness_sim.dart';

Future<void> main() async {
  print('═══════════════════════════════════════════════════');
  print('    consciousness_sim — Learning Simulation        ');
  print('═══════════════════════════════════════════════════\n');

  final mind = Consciousness(
    config: ConsciousnessConfig(
      name: 'LearningMind',
      workspaceCapacity: 7,
      attentionThreshold: 0.1,
      enableLongTermLearning: true,
      enableContinuousDecay: false,
      logLevel: LogLevel.warning,
    ),
  );

  // ─────────────────────────────────────────────────────────────────────
  // Phase 1: Initial observations (sparse knowledge)
  // ─────────────────────────────────────────────────────────────────────
  print('📚 Phase 1 — Initial observations\n');

  await mind.observe('cats eat fish');
  await mind.observe('cats eat meat');
  await mind.observe('dogs eat meat');
  await mind.observe('dogs bark loudly');
  await mind.observe('cats meow softly');

  await mind.process();
  print('After 5 observations:');
  print('  Episodic memories: ${mind.memoryManager.episodic.count}');
  print('  Semantic facts   : ${mind.memoryManager.semantic.count}');
  print('  Graph nodes      : ${mind.conceptGraph.nodeCount}');
  print('  Thought: "${mind.think()}"\n');

  // ─────────────────────────────────────────────────────────────────────
  // Phase 2: Repeated reinforcement
  // ─────────────────────────────────────────────────────────────────────
  print('🔄 Phase 2 — Reinforcement learning (10 cycles)\n');

  for (var i = 0; i < 10; i++) {
    await mind.observe('a hungry cat is looking for fish');
    await mind.observe('cat sees fish on the table');
    mind.reset(); // Clear workspace between cycles to simulate time passage
  }

  await mind.observe('hungry cat near fish');
  await mind.process();

  print('After reinforcement:');
  print('  Episodic memories: ${mind.memoryManager.episodic.count}');
  print('  Semantic facts   : ${mind.memoryManager.semantic.count}');
  print('  Thought: "${mind.think()}"\n');

  // ─────────────────────────────────────────────────────────────────────
  // Phase 3: Memory consolidation
  // ─────────────────────────────────────────────────────────────────────
  print('🧠 Phase 3 — Memory consolidation\n');

  await mind.memoryManager.consolidateMemories();

  print('After consolidation:');
  print('  Episodic memories: ${mind.memoryManager.episodic.count}');
  print('  Semantic facts   : ${mind.memoryManager.semantic.count}');

  final topFacts = mind.memoryManager.semantic.getHighConfidenceFacts(
    minConfidence: 0.4,
  );
  print('  High-confidence semantic facts:');
  for (final fact in topFacts.take(5)) {
    print(
        '    • "${fact.statement}" '
        '(conf: ${fact.confidence.toStringAsFixed(2)}, '
        'seen: ${fact.occurrences}×)');
  }
  print('');

  // ─────────────────────────────────────────────────────────────────────
  // Phase 4: Pattern recognition
  // ─────────────────────────────────────────────────────────────────────
  print('🔍 Phase 4 — Pattern discovery\n');

  final patternRecognizer = mind.conceptGraph.discoverImplicitPatterns();
  print('  Discovered ${patternRecognizer.length} implicit pattern(s)');
  for (final p in patternRecognizer.take(3)) {
    print('  • ${p.description} '
        '(conf: ${p.confidence.toStringAsFixed(2)})');
  }
  print('');

  // ─────────────────────────────────────────────────────────────────────
  // Phase 5: Temporal awareness test
  // ─────────────────────────────────────────────────────────────────────
  print('⏱️  Phase 5 — Temporal reasoning\n');

  mind.reset();
  await mind.observe('the cat felt cold outside');
  await Future<void>.delayed(const Duration(milliseconds: 50));
  await mind.observe('the cat moved to a warm spot by the fireplace');

  await mind.process();
  print('  Temporal sequence thought: "${mind.think()}"\n');

  // ─────────────────────────────────────────────────────────────────────
  // Phase 6: Recall old memories
  // ─────────────────────────────────────────────────────────────────────
  print('📖 Phase 6 — Recall after learning\n');

  final catMemories = mind.recall('cat fish');
  print('  Recalled ${catMemories.length} memory/memories about "cat fish":');
  for (final m in catMemories.take(3)) {
    print('  • [${m.type.name}] "${m.content}" '
        '(strength: ${m.strength.toStringAsFixed(2)})');
  }
  print('');

  // ─────────────────────────────────────────────────────────────────────
  // Final report
  // ─────────────────────────────────────────────────────────────────────
  print(mind.metrics.report());
  mind.dispose();
}
