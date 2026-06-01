// example/advanced_awareness.dart
// Demonstrates advanced attention control, custom rules, and plugin usage.

import 'dart:async';

import 'package:consciousness_sim/consciousness_sim.dart';

// ─────────────────────────────────────────────
// Custom plugin: prints when coherence drops below a threshold
// ─────────────────────────────────────────────
class CoherenceAlertPlugin extends ConsciousnessPlugin {
  const CoherenceAlertPlugin({this.threshold = 0.4});

  final double threshold;

  @override
  String get name => 'CoherenceAlert';

  @override
  Future<void> process(ConsciousState state) async {
    if (state.coherence < threshold && state.workspace.isNotEmpty) {
      print('⚠️  [CoherenceAlert] Low coherence: '
          '${(state.coherence * 100).toStringAsFixed(1)}% '
          '— workspace may be fragmented!');
    }
  }
}

// ─────────────────────────────────────────────
Future<void> main() async {
  print('═══════════════════════════════════════════════════');
  print('     consciousness_sim — Advanced Awareness        ');
  print('═══════════════════════════════════════════════════\n');

  final mind = Consciousness(
    config: ConsciousnessConfig(
      name: 'AdvancedMind',
      workspaceCapacity: 9,
      attentionThreshold: 0.15,
      enableLongTermLearning: true,
      enableContinuousDecay: false,
      logLevel: LogLevel.warning,
    ),
  );

  // ── 1. Custom plugin ──────────────────────────────────────────────────
  mind.addPlugin(const CoherenceAlertPlugin(threshold: 0.3));
  mind.addPlugin(const EmotionDetectorPlugin(threshold: 0.5));
  print('🔌 Plugins registered\n');

  // ── 2. Custom inference rules ──────────────────────────────────────────
  mind.learn(InferenceRule(
    id: 'rule_storm',
    name: 'storm_warning',
    conditions: ['rain', 'thunder'],
    conclusion: 'A storm is approaching — seek shelter immediately.',
    weight: 0.95,
  ));
  mind.learn(InferenceRule(
    id: 'rule_robot',
    name: 'robot_low_battery',
    conditions: ['battery', 'low'],
    conclusion: 'Battery is low — returning to charging station.',
    weight: 0.9,
  ));
  print('📚 Custom rules loaded\n');

  // ── 3. Storm scenario ─────────────────────────────────────────────────
  print('⛈️  Scenario 1: Incoming storm\n');
  await mind.observe('dark clouds are gathering outside');
  await mind.observe('it is starting to rain heavily');
  await mind.observe('I can hear distant thunder');

  final stormState = await mind.process();
  print('💭 Thought: "${mind.think()}"');
  print('   Workspace: ${stormState.workspace.length} concepts, '
      'coherence: ${(stormState.coherence * 100).toStringAsFixed(1)}%\n');

  // ── 4. Attention redirection ──────────────────────────────────────────
  print('🎯 Redirecting attention to "shelter"...');
  mind.refocusAttention(['shelter', 'safety']);
  print('   Think after refocus: "${mind.think()}"\n');

  // ── 5. Emotional observation ──────────────────────────────────────────
  print('😨 Scenario 2: Emergency\n');
  mind.reset(); // Clear short-term state
  await mind.observe('FIRE ALARM IS RINGING!!');
  await mind.observe('smoke is filling the corridor');
  await mind.observe('people are running out of the building');

  final emergencyState = await mind.process();
  print('💭 Thought: "${mind.think()}"');
  print('   Most activated: '
      '${emergencyState.workspace.isNotEmpty ? emergencyState.workspace.first.content : "none"}\n');

  // ── 6. Attention wandering ────────────────────────────────────────────
  print('🔄 Attention wandering demo...');
  await mind.wanderAttention(
    ['fire', 'smoke', 'exit', 'safety'],
    const Duration(milliseconds: 50),
  );
  print('   After wander, thought: "${mind.think()}"\n');

  // ── 7. Learning feedback ──────────────────────────────────────────────
  print('📖 Learning from positive outcome...');
  await mind.learnFrom('escaped safely', positive: true);
  print('   Learned from experience\n');

  // ── 8. Memory inspection ──────────────────────────────────────────────
  print('🗂️  Memory summary:');
  final stats = mind.memoryManager.getStats();
  print('   Episodic : ${stats['episodic']}');
  print('   Semantic : ${stats['semantic']}');
  print('   Working  : ${stats['working']}\n');

  // ── 9. Final metrics ──────────────────────────────────────────────────
  print(mind.metrics.report());

  mind.dispose();
}
