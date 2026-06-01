// example/multi_tool_agent.dart
//
// Demonstrates ALL 6 built-in tools, custom tool registration,
// self-reflection, and mock environment observations.
//
// Run with:   dart run example/multi_tool_agent.dart
//
// Tools exercised:
//   search_web    — mock web search (DuckDuckGo-style)
//   calculate     — recursive-descent math evaluator
//   read_file     — sandbox-restricted file reader
//   write_file    — sandbox-restricted file writer
//   call_api      — HTTP GET/POST (mock in test mode)
//   schedule_task — delayed callback

import 'dart:io';

import 'package:consciousness_sim/consciousness_sim.dart';

// ─────────────────────────────────────────────
// Custom tool example
// ─────────────────────────────────────────────

/// A demonstration custom tool that reverses a string.
class ReverseStringTool extends Tool {
  const ReverseStringTool();

  @override
  String get name => 'reverse_string';

  @override
  String get description => 'Reverses the characters of a string.';

  @override
  Map<String, String> get inputSchema => {
        'text': 'The string to reverse.',
      };

  @override
  Future<ToolResult> run(Map<String, dynamic> input) async {
    final text = input['text'] as String? ?? '';
    final reversed = text.split('').reversed.join();
    return ToolResult.success(name, reversed);
  }
}

// ─────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────

Future<void> main() async {
  print('═══════════════════════════════════════════════');
  print('  consciousness_sim — Multi-Tool Agent Demo     ');
  print('═══════════════════════════════════════════════\n');

  // 1. Create the consciousness
  final mind = Consciousness(
    config: const ConsciousnessConfig(
      name: 'HermesAgent',
      logLevel: LogLevel.warning,
    ),
  );

  // 2. Set up a temporary sandbox directory for file tool demos
  final tempDir = Directory.systemTemp.createTempSync('agent_demo_');
  print('[Setup] Sandbox dir: ${tempDir.path}');

  // 3. Build the agent with all 6 built-in tools + one custom tool
  final provider = MockLLMProvider(
    name: 'mock-hermes',
    responses: [
      // --- Tool 1: search_web ---
      '{"action":"use_tool","tool":"search_web",'
          '"input":{"query":"Dart programming language"},'
          '"thought":"Let me search for Dart info first."}',

      // --- Tool 2: calculate ---
      '{"action":"use_tool","tool":"calculate",'
          '"input":{"expression":"sqrt(144) + pi"},'
          '"thought":"Now let me do some math: sqrt(144) + pi"}',

      // --- Tool 3: write_file ---
      '{"action":"use_tool","tool":"write_file",'
          '"input":{"path":"${tempDir.path}/notes.txt",'
          '"content":"Dart is a great language. sqrt(144)=12. pi≈3.14159"},'
          '"thought":"Saving results to a file."}',

      // --- Tool 4: read_file ---
      '{"action":"use_tool","tool":"read_file",'
          '"input":{"path":"${tempDir.path}/notes.txt"},'
          '"thought":"Now reading the file I just wrote."}',

      // --- Tool 5: call_api ---
      '{"action":"use_tool","tool":"call_api",'
          '"input":{"url":"https://httpbin.org/get","method":"GET"},'
          '"thought":"Making an HTTP call to test the API tool."}',

      // --- Tool 6: schedule_task ---
      '{"action":"use_tool","tool":"schedule_task",'
          '"input":{"task_name":"cleanup","delay_seconds":1},'
          '"thought":"Scheduling a deferred cleanup task."}',

      // --- Custom tool: reverse_string ---
      '{"action":"use_tool","tool":"reverse_string",'
          '"input":{"text":"consciousness"},'
          '"thought":"Let me test the custom reverse_string tool."}',

      // --- Done ---
      '{"action":"complete",'
          '"reason":"All 7 tools exercised successfully. '
          'Dart info searched, math computed, file written and read, '
          'API called, task scheduled, custom tool invoked."}',
    ],
  );

  final agent = mind.asAgent(
    provider: provider,
    config: AgentMindConfig(
      enableReflection: true,
      registerBuiltinTools: true,
      extraTools: const [ReverseStringTool()],
      loopConfig: const AgentLoopConfig(
        maxConsecutiveErrors: 3,
        reflectionIntervalIterations: 4,
        emitEvents: true,
      ),
    ),
  );

  // 4. Show registered tools
  print('\n[Tools] Registered (${agent.tools.count}):');
  print(agent.tools.buildCatalogue());

  // 5. Set up a mock environment that provides one batch of observations
  // (in this demo we use the NullEnvironmentAdapter built into asAgent,
  // so the agent works from its goal + tool results alone)

  // 6. Define the goal
  final goal = AgentGoal(
    id: 'demo-multi-tool',
    description: 'Exercise all 6 built-in tools plus a custom reverse_string tool. '
        'Search for Dart info, compute sqrt(144)+pi, write and read a file, '
        'call an API, schedule a task, and reverse the word "consciousness".',
    successCriteria: [
      'Web search performed',
      'Math calculation done',
      'File written and read',
      'HTTP API called',
      'Task scheduled',
      'Custom tool invoked',
    ],
    maxIterations: 15,
    priority: 1.0,
  );

  print('\n[Agent] Goal: "${goal.description}"\n');

  // 7. Track events
  var toolCallCount = 0;
  agent.events.listen((e) {
    if (e.type == AgentLoopEventType.toolExecuted) {
      toolCallCount++;
      final result = e.data as ToolResult?;
      print('  🔧 Tool call #$toolCallCount: ${result?.toolName ?? "?"}'
          ' → ${result?.success == true ? "✅" : "❌"}'
          ' ${_truncate(result?.outputText ?? "")}');
    } else if (e.type == AgentLoopEventType.completed) {
      print('  🎯 COMPLETED: ${_truncate(e.data?.toString() ?? "")}');
    } else if (e.type == AgentLoopEventType.reflected) {
      print('  🪞 REFLECTION: ${_truncate(e.data?.toString() ?? "")}');
    } else if (e.type == AgentLoopEventType.iterationStarted) {
      print('\n--- Iteration ${e.iteration} ---');
    }
  });

  // 8. Run
  final result = await agent.pursue(goal);

  // 9. Results
  print('\n─── Run Result ─────────────────────────────');
  print('Success     : ${result.success}');
  print('Iterations  : ${result.iterations}');
  print('Tool calls  : $toolCallCount');
  print('Summary     : ${result.summary}');

  // 10. Memory stats
  print('\n─── Memory Stats ────────────────────────────');
  final stats = agent.memory.stats;
  for (final entry in stats.entries) {
    if (entry.value > 0) print('  ${entry.key}: ${entry.value}');
  }

  // 11. Verify file was written
  final notesFile = File('${tempDir.path}/notes.txt');
  if (notesFile.existsSync()) {
    print('\n─── File Output ─────────────────────────────');
    print(notesFile.readAsStringSync());
  }

  // Cleanup
  tempDir.deleteSync(recursive: true);
  await agent.dispose();
  mind.dispose();

  print('\n═══════════════════════════════════════════════');
  print('  Multi-tool demo complete.                      ');
  print('═══════════════════════════════════════════════');
}

String _truncate(String s, [int n = 70]) =>
    s.length > n ? '${s.substring(0, n - 3)}...' : s;
