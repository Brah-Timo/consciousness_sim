// example/autonomous_agent.dart
//
// Demonstrates the full autonomous agent loop:
//   Consciousness  +  AgentMind  =  cognitive + agentic system
//
// Run with:   dart run example/autonomous_agent.dart
//
// This example uses MockLLMProvider (no real API key required) to show:
//   1. Basic goal pursuit with a tool call + completion
//   2. Listening to AgentLoopEvent stream
//   3. Accessing agent memory after a run

import 'package:consciousness_sim/consciousness_sim.dart';

// ─────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────

Future<void> main() async {
  print('═══════════════════════════════════════════════');
  print('  consciousness_sim — Autonomous Agent Demo     ');
  print('═══════════════════════════════════════════════\n');

  // 1. Create the cognitive foundation
  final mind = Consciousness(
    config: const ConsciousnessConfig(
      name: 'Atlas',
      workspaceCapacity: 7,
      logLevel: LogLevel.warning, // quiet for demo
    ),
  );

  // 2. Pre-load some observations into the consciousness workspace
  print('[Consciousness] Perceiving environment...');
  await mind.observe('User asked about the speed of light in a vacuum');
  await mind.observe('Physics constants are well documented');
  await mind.process();

  print('[Consciousness] Think: "${mind.think()}"\n');

  // 3. Upgrade to autonomous agent using MockLLMProvider
  //    The mock provider simulates a real LLM response queue.
  final provider = MockLLMProvider(
    name: 'mock-gpt-4o',
    responses: [
      // Iteration 1: agent decides to calculate
      '{"action":"use_tool","tool":"calculate",'
          '"input":{"expression":"299792458"},'
          '"thought":"The speed of light is exactly 299,792,458 m/s. '
          'Let me confirm by expressing it in km/s."}',

      // Iteration 2: agent decides to calculate km/s
      '{"action":"use_tool","tool":"calculate",'
          '"input":{"expression":"299792458 / 1000"},'
          '"thought":"Converting to km/s for the answer."}',

      // Iteration 3: agent decides the goal is complete
      '{"action":"complete",'
          '"reason":"The speed of light is 299,792,458 m/s (299,792.458 km/s). '
          'This is a fundamental physical constant."}',
    ],
  );

  final agent = mind.asAgent(
    provider: provider,
    config: const AgentMindConfig(
      enableReflection: false, // keep output clean for demo
      loopConfig: AgentLoopConfig(
        emitEvents: true,
        maxConsecutiveErrors: 2,
      ),
    ),
  );

  // 4. Listen to the event stream BEFORE calling pursue()
  final eventLog = <String>[];
  final sub = agent.events.listen((event) {
    final icon = _eventIcon(event.type);
    final msg = '$icon [iter ${event.iteration}] ${event.type.name}'
        '${event.data != null ? ": ${_truncate(event.data.toString())}" : ""}';
    eventLog.add(msg);
    print(msg);
  });

  // 5. Define the goal
  final goal = AgentGoal(
    id: 'goal-speed-of-light',
    description: 'What is the speed of light in both m/s and km/s?',
    successCriteria: [
      'Speed in m/s reported',
      'Speed in km/s reported',
    ],
    maxIterations: 10,
    priority: 0.8,
  );

  print('\n[Agent] Pursuing goal: "${goal.description}"\n');

  // 6. Run the autonomous loop
  final result = await agent.pursue(goal);

  await sub.cancel();

  // 7. Print the result
  print('\n─── Run Result ─────────────────────────────');
  print('Success     : ${result.success}');
  print('Iterations  : ${result.iterations}');
  print('Tasks done  : ${result.tasksCompleted}');
  print('Tasks failed: ${result.tasksFailed}');
  print('Summary     : ${result.summary}');
  if (result.error != null) {
    print('Error       : ${result.error}');
  }

  // 8. Inspect agent memory
  print('\n─── Agent Memory ────────────────────────────');
  final memSummary = agent.memory.summarise(maxEntries: 5, goalId: goal.id);
  print(memSummary);

  // 9. LLM usage stats
  print('\n─── LLM Stats ───────────────────────────────');
  print('Reasoning calls : ${agent.llm.reasoningCalls}');
  print('Prompt tokens   : ${agent.llm.totalPromptTokens}');
  print('Completion tokens: ${agent.llm.totalCompletionTokens}');

  // 10. Events summary
  print('\n─── Events log (${ eventLog.length} total) ──────────────');
  for (final e in eventLog) {
    print('  $e');
  }

  print('\n═══════════════════════════════════════════════');
  print('  Demo complete.                                ');
  print('═══════════════════════════════════════════════');

  // Cleanup
  await agent.dispose();
  mind.dispose();
}

// ─────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────

String _eventIcon(AgentLoopEventType type) => switch (type) {
      AgentLoopEventType.iterationStarted => '🔄',
      AgentLoopEventType.observed => '👁️',
      AgentLoopEventType.memoryRetrieved => '🧠',
      AgentLoopEventType.planned => '📋',
      AgentLoopEventType.decided => '💡',
      AgentLoopEventType.toolExecuted => '🔧',
      AgentLoopEventType.thoughtRecorded => '💭',
      AgentLoopEventType.taskSucceeded => '✅',
      AgentLoopEventType.taskFailed => '❌',
      AgentLoopEventType.memoryUpdated => '💾',
      AgentLoopEventType.completed => '🎯',
      AgentLoopEventType.failed => '🚫',
      AgentLoopEventType.replanned => '🔁',
      AgentLoopEventType.reflected => '🪞',
    };

String _truncate(String s, [int n = 80]) =>
    s.length > n ? '${s.substring(0, n - 3)}...' : s;
