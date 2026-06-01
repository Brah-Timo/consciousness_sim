// example/basic_consciousness.dart
// The simplest usage of consciousness_sim — the canonical cat+fish demo.

import 'package:consciousness_sim/consciousness_sim.dart';

Future<void> main() async {
  print('═══════════════════════════════════════════════════');
  print('       consciousness_sim — Basic Example           ');
  print('═══════════════════════════════════════════════════\n');

  // ── Step 1: Instantiate a conscious mind ──────────────────────────────
  final mind = Consciousness(
    config: ConsciousnessConfig(
      name: 'BasicMind',
      workspaceCapacity: 7,
      attentionThreshold: 0.2,
      enableLongTermLearning: true,
      logLevel: LogLevel.warning, // Suppress verbose logs in demo
    ),
  );

  print('🧠 Mind created: $mind\n');

  // ── Step 2: Feed observations ─────────────────────────────────────────
  print('📥 Feeding observations...\n');

  await mind.observe('a cat is sitting on the table');
  print('  Observed: "a cat is sitting on the table"');

  await mind.observe('the cat looks hungry');
  print('  Observed: "the cat looks hungry"');

  await mind.observe('there is fish on the table');
  print('  Observed: "there is fish on the table"\n');

  // ── Step 3: Process and think ─────────────────────────────────────────
  print('⚙️  Processing...\n');
  final state = await mind.process();

  print('💭 Thought: "${mind.think()}"\n');

  // ── Step 4: Examine the conscious state ──────────────────────────────
  const viz = ConsciousnessVisualizer();
  print(viz.renderState(state));

  // ── Step 5: Recall related memories ──────────────────────────────────
  print('🗂️  Recalling memories for "cat"...');
  final memories = mind.recall('cat');
  if (memories.isEmpty) {
    print('  No memories yet.\n');
  } else {
    for (final m in memories.take(3)) {
      print('  • ${m.content} (strength: ${m.strength.toStringAsFixed(2)})');
    }
    print('');
  }

  // ── Step 6: Detailed thought breakdown ───────────────────────────────
  print('🔍 Detailed thought analysis:');
  final detail = mind.thinkDetailed();
  print('  Thought      : ${detail['thought']}');
  print('  Focus        : ${detail['focus']}');
  print('  Workspace    : ${detail['workspace_size']} concepts');
  print('  Inferences   : ${detail['inference_count']}');
  print('  Coherence    : ${(detail['coherence'] as double).toStringAsFixed(2)}\n');

  // ── Step 7: Metrics ───────────────────────────────────────────────────
  print(mind.metrics.report());

  mind.dispose();
}
