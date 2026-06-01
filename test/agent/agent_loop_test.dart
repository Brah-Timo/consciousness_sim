// test/agent/agent_loop_test.dart
//
// Integration tests for AgentLoopController, EnvironmentAdapter,
// and SelfReflectionModule.

import 'package:test/test.dart';
import 'package:consciousness_sim/consciousness_sim.dart';

// ─────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────

/// Builds a fully wired AgentLoopController with MockLLMProvider.
AgentLoopController _buildLoop(
  List<String> llmResponses, {
  List<List<AgentObservation>>? envBatches,
  AgentLoopConfig? config,
  SelfReflectionStub? reflection,
}) {
  final memory = AgentMemoryStore();
  final provider = MockLLMProvider(responses: llmResponses);
  final llm = LLMCore(provider: provider, memory: memory);
  // Use rule-based planning only — no llmCore — so ALL mock responses
  // are reserved exclusively for LLMCore.reason() calls in the loop body.
  final planner = PlanningEngine();
  final registry = ToolRegistry();
  BuiltinToolset.registerAll(registry);

  return AgentLoopController(
    llm: llm,
    memory: memory,
    planner: planner,
    registry: registry,
    environment:
        envBatches != null ? MockEnvironmentAdapter(batches: envBatches) : null,
    config: config ??
        const AgentLoopConfig(
          emitEvents: true,
          maxConsecutiveErrors: 3,
          enableReflection: false,
        ),
    reflection: reflection,
  );
}

AgentGoal _goal(String desc, {int maxIter = 10}) => AgentGoal(
      id: 'test-goal',
      description: desc,
      maxIterations: maxIter,
    );

void main() {
  // ──────────────────────────────────────────
  group('AgentLoopController — basic run', () {
    test('completes when LLM returns complete action', () async {
      final loop = _buildLoop([
        '{"action":"complete","reason":"Done immediately"}',
      ]);
      final result = await loop.run(_goal('Simple goal'));
      expect(result.success, isTrue);
      expect(result.summary, contains('Done immediately'));
      await loop.dispose();
    });

    test('runs tool call then completes', () async {
      final loop = _buildLoop([
        '{"action":"use_tool","tool":"calculate","input":{"expression":"2+2"},"thought":"Math"}',
        '{"action":"complete","reason":"Calculation done"}',
      ]);
      final result = await loop.run(_goal('Calculate 2+2'));
      expect(result.success, isTrue);
      await loop.dispose();
    });

    test('think step then complete', () async {
      final loop = _buildLoop([
        '{"action":"think","thought":"I need to reason about this"}',
        '{"action":"complete","reason":"Reasoned successfully"}',
      ]);
      final result = await loop.run(_goal('Think and decide'));
      expect(result.success, isTrue);
      await loop.dispose();
    });

    test('replan then complete', () async {
      final loop = _buildLoop([
        '{"action":"replan","reason":"Need new approach"}',
        '{"action":"complete","reason":"New plan worked"}',
      ]);
      final result = await loop.run(_goal('Replan test'));
      expect(result.success, isTrue);
      await loop.dispose();
    });

    test('fails after max iterations', () async {
      final loop = _buildLoop(
        ['{"action":"think","thought":"still thinking"}'],
        config: const AgentLoopConfig(
          maxConsecutiveErrors: 99,
          emitEvents: false,
          enableReflection: false,
        ),
      );
      final result = await loop.run(_goal('Infinite loop', maxIter: 3));
      expect(result.success, isFalse);
      expect(result.iterations, 3);
      await loop.dispose();
    });

    test('aborts after maxConsecutiveErrors', () async {
      final loop = _buildLoop(
        ['{"action":"error","message":"Something broke"}'],
        config: const AgentLoopConfig(
          maxConsecutiveErrors: 2,
          emitEvents: false,
          enableReflection: false,
        ),
      );
      final result = await loop.run(_goal('Error test', maxIter: 20));
      expect(result.success, isFalse);
      expect(result.error, contains('consecutive errors'));
      await loop.dispose();
    });
  });

  // ──────────────────────────────────────────
  group('AgentLoopController — events stream', () {
    test('emits iterationStarted and completed events', () async {
      final loop = _buildLoop([
        '{"action":"complete","reason":"instant"}',
      ]);

      final types = <AgentLoopEventType>[];
      final sub = loop.events.listen((e) => types.add(e.type));

      await loop.run(_goal('Event test'));
      await sub.cancel();

      expect(types, contains(AgentLoopEventType.iterationStarted));
      expect(types, contains(AgentLoopEventType.completed));
      await loop.dispose();
    });

    test('emits toolExecuted when tool called', () async {
      final loop = _buildLoop([
        '{"action":"use_tool","tool":"calculate","input":{"expression":"1+1"},"thought":""}',
        '{"action":"complete","reason":"done"}',
      ]);

      final types = <AgentLoopEventType>[];
      final sub = loop.events.listen((e) => types.add(e.type));

      await loop.run(_goal('Tool event test'));
      await sub.cancel();

      expect(types, contains(AgentLoopEventType.toolExecuted));
      await loop.dispose();
    });

    test('emits thoughtRecorded for think decisions', () async {
      final loop = _buildLoop([
        '{"action":"think","thought":"pondering"}',
        '{"action":"complete","reason":"done"}',
      ]);

      final types = <AgentLoopEventType>[];
      final sub = loop.events.listen((e) => types.add(e.type));

      await loop.run(_goal('Thought event'));
      await sub.cancel();

      expect(types, contains(AgentLoopEventType.thoughtRecorded));
      await loop.dispose();
    });
  });

  // ──────────────────────────────────────────
  group('MockEnvironmentAdapter', () {
    test('delivers observations in batches', () async {
      final obs1 = AgentObservation(id: 'o1', content: 'Data 1', source: 'env');
      final obs2 = AgentObservation(id: 'o2', content: 'Data 2', source: 'env');

      final adapter = MockEnvironmentAdapter(batches: [
        [obs1],
        [obs2],
      ]);

      final first = await adapter.poll();
      expect(first, hasLength(1));
      expect(first.first.id, 'o1');

      final second = await adapter.poll();
      expect(second, hasLength(1));
      expect(second.first.id, 'o2');

      // Exhausted — returns empty
      final third = await adapter.poll();
      expect(third, isEmpty);
    });

    test('enqueue adds batch', () async {
      final adapter = MockEnvironmentAdapter();
      adapter.enqueue([
        AgentObservation(id: 'x', content: 'new obs', source: 'test'),
      ]);
      final batch = await adapter.poll();
      expect(batch, hasLength(1));
    });

    test('loop receives environment observations', () async {
      final obs = AgentObservation(
          id: 'env-1', content: 'Important context', source: 'test');
      final loop = _buildLoop(
        ['{"action":"complete","reason":"got the context"}'],
        envBatches: [[obs]],
      );

      final observedEvents = <AgentLoopEvent>[];
      final sub = loop.events.listen((e) {
        if (e.type == AgentLoopEventType.observed) observedEvents.add(e);
      });

      await loop.run(_goal('Env observation test'));
      await sub.cancel();

      expect(observedEvents, isNotEmpty);
      await loop.dispose();
    });
  });

  // ──────────────────────────────────────────
  group('NullEnvironmentAdapter', () {
    test('always returns empty list', () async {
      const adapter = NullEnvironmentAdapter();
      final result = await adapter.poll();
      expect(result, isEmpty);
    });
  });

  // ──────────────────────────────────────────
  group('stop() graceful abort', () {
    test('stop() causes loop to exit before maxIterations', () async {
      var iteration = 0;
      final loop = _buildLoop(
        ['{"action":"think","thought":"ongoing"}'],
        config: const AgentLoopConfig(
          emitEvents: true, // must be true so the listener fires and stop() is called
          enableReflection: false,
          maxConsecutiveErrors: 99,
          iterationDelay: Duration(milliseconds: 5),
        ),
      );

      loop.events.listen((e) {
        if (e.type == AgentLoopEventType.iterationStarted) {
          iteration++;
          if (iteration >= 2) loop.stop();
        }
      });

      final result = await loop.run(_goal('Stop test', maxIter: 100));
      expect(result.success, isFalse);
      expect(result.iterations, lessThan(100));
      await loop.dispose();
    });
  });

  // ──────────────────────────────────────────
  group('SelfReflectionModule', () {
    test('reflects and returns non-null insight', () async {
      final memory = AgentMemoryStore();
      final reflection = SelfReflectionModule(memory: memory);

      final goal = AgentGoal(id: 'rg', description: 'Reflect on this');
      final ctx = AgentContext(goal: goal, iterationNumber: 3);
      final planner = PlanningEngine();
      final dag = await planner.plan(
          goal, AgentContext(goal: goal, iterationNumber: 0));

      final insight = await reflection.reflect(ctx, dag);
      expect(insight, isNotNull);
      expect(insight!, isNotEmpty);
    });

    test('detects task failures trigger', () async {
      final memory = AgentMemoryStore();
      final reflection = SelfReflectionModule(
        memory: memory,
        config: const SelfReflectionConfig(maxFailuresBeforeReflect: 1),
      );

      final goal = AgentGoal(id: 'rg2', description: 'Failure test');
      final planner = PlanningEngine();
      final dag =
          await planner.plan(goal, AgentContext(goal: goal, iterationNumber: 0));

      // Force a task failure
      if (dag.all.isNotEmpty) {
        dag.all.first.status = TaskStatus.failed;
        dag.all.first.retryCount = 2;
      }

      final ctx = AgentContext(goal: goal, iterationNumber: 1);
      final insight = await reflection.reflect(ctx, dag);

      expect(insight, isNotNull);
      expect(reflection.reflectionCount, greaterThan(0));
    });

    test('diagnostics returns string', () async {
      final memory = AgentMemoryStore();
      final reflection = SelfReflectionModule(memory: memory);
      expect(reflection.diagnostics(), isA<String>());
    });

    test('history grows with each call', () async {
      final memory = AgentMemoryStore();
      final reflection = SelfReflectionModule(memory: memory);
      final goal = AgentGoal(id: 'rg3', description: 'History test');
      final planner = PlanningEngine();
      final dag =
          await planner.plan(goal, AgentContext(goal: goal, iterationNumber: 0));
      final ctx = AgentContext(goal: goal, iterationNumber: 1);

      expect(reflection.history, isEmpty);
      await reflection.reflect(ctx, dag);
      expect(reflection.history, hasLength(1));
      await reflection.reflect(ctx, dag);
      expect(reflection.history, hasLength(2));
    });
  });
}
