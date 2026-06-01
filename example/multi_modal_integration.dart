// example/multi_modal_integration.dart
// Demonstrates cross-modal binding: visual + auditory + tactile integration.

import 'package:consciousness_sim/consciousness_sim.dart';

Future<void> main() async {
  print('═══════════════════════════════════════════════════');
  print('  consciousness_sim — Multi-Modal Integration      ');
  print('═══════════════════════════════════════════════════\n');

  final mind = Consciousness(
    config: ConsciousnessConfig(
      name: 'MultiModalMind',
      workspaceCapacity: 9,
      attentionThreshold: 0.1,
      enableLongTermLearning: true,
      enableContinuousDecay: false,
      logLevel: LogLevel.warning,
    ),
  );

  // ─────────────────────────────────────────────────────────────────────
  // Scenario: Robot navigating a room
  // ─────────────────────────────────────────────────────────────────────
  print('🤖 Scenario: Robot sensor fusion\n');

  // Visual input
  print('👁️  Visual: "obstacle detected ahead"');
  await mind.observeVisual('obstacle detected ahead blocking path');

  // Auditory input (simultaneous)
  print('👂 Auditory: "collision warning beep"');
  await mind.observeAuditory('collision warning beep sound');

  // Tactile input (proximity sensor)
  print('🤚 Tactile: "proximity sensor triggered"');
  await mind.observeTactile('proximity sensor triggered close range');

  // Abstract sensor data
  print('🧠 Abstract: "distance sensor: 15cm"');
  await mind.observeAbstract('distance sensor reading 15cm very close');

  final robotState = await mind.process();
  print('\n💭 Robot thought: "${mind.think()}"');
  print('   Workspace: ${robotState.workspace.length} concepts');
  print('   Coherence: ${(robotState.coherence * 100).toStringAsFixed(1)}%\n');

  // ─────────────────────────────────────────────────────────────────────
  // Scenario: Medical diagnosis
  // ─────────────────────────────────────────────────────────────────────
  mind.reset();
  print('🏥 Scenario: Medical sensor fusion\n');

  await mind.observeAbstract('temperature reading: 39.5°C fever');
  await mind.observeAbstract('heart rate: 110 bpm elevated');
  await mind.observeVisual('patient skin appears red and flushed');
  await mind.observeAuditory('patient reports pain and difficulty breathing');

  final medState = await mind.process();
  print('💭 Diagnosis thought: "${mind.think()}"');
  print('   Top inferences:');
  for (final inf in medState.inferencesGenerated.take(3)) {
    print('   → ${inf.conclusion} '
        '[${(inf.confidence * 100).toStringAsFixed(0)}%]');
  }
  print('');

  // ─────────────────────────────────────────────────────────────────────
  // Scenario: Game AI character
  // ─────────────────────────────────────────────────────────────────────
  mind.reset();
  print('🎮 Scenario: Game AI character decisions\n');

  await mind.observeVisual('enemy player approaching from the left');
  await mind.observeAbstract('health points: 20 out of 100 critical');
  await mind.observeAbstract('ammunition: 3 bullets remaining low');
  await mind.observeVisual('exit door visible to the right');

  final gameState = await mind.process();
  print('💭 AI Decision: "${mind.think()}"');
  print('   Active concepts: '
      '${gameState.workspace.map((c) => c.content.split(" ").first).join(", ")}\n');

  // ─────────────────────────────────────────────────────────────────────
  // Visualise final graph
  // ─────────────────────────────────────────────────────────────────────
  const viz = ConsciousnessVisualizer();
  print(viz.renderGraph(mind.conceptGraph));

  mind.dispose();
}
