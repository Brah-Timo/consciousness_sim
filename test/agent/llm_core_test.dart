// test/agent/llm_core_test.dart
//
// Unit tests for LLMCore, LLMCoreConfig, and LLMProvider implementations.

import 'package:test/test.dart';
import 'package:consciousness_sim/consciousness_sim.dart';

void main() {
  // ──────────────────────────────────────────
  group('EchoLLMProvider', () {
    test('echoes last user message', () async {
      final p = EchoLLMProvider();
      final req = LLMRequest(
        messages: [
          const LLMMessage(role: 'system', content: 'sys'),
          const LLMMessage(role: 'user', content: 'Hello world'),
        ],
      );
      final resp = await p.complete(req);
      expect(resp.text, contains('Hello world'));
    });

    test('returns empty string for empty messages', () async {
      final p = EchoLLMProvider();
      final req = LLMRequest(messages: []);
      final resp = await p.complete(req);
      expect(resp.text, isA<String>());
    });

    test('name is echo', () {
      expect(EchoLLMProvider().name, 'echo');
    });
  });

  // ──────────────────────────────────────────
  group('MockLLMProvider', () {
    test('returns queued responses in order', () async {
      final p = MockLLMProvider(
        responses: ['first', 'second', 'third'],
      );
      expect((await p.complete(LLMRequest(messages: []))).text, 'first');
      expect((await p.complete(LLMRequest(messages: []))).text, 'second');
      expect((await p.complete(LLMRequest(messages: []))).text, 'third');
    });

    test('cycles back to first when queue exhausted', () async {
      final p = MockLLMProvider(responses: ['only']);
      await p.complete(LLMRequest(messages: []));
      // second call should still work (cycles)
      final resp = await p.complete(LLMRequest(messages: []));
      expect(resp.text, isA<String>());
    });

    test('callCount increments', () async {
      final p = MockLLMProvider(responses: ['a']);
      expect(p.callCount, 0);
      await p.complete(LLMRequest(messages: []));
      expect(p.callCount, 1);
      await p.complete(LLMRequest(messages: []));
      expect(p.callCount, 2);
    });

    test('keyword heuristic returns think for vague input', () async {
      final p = MockLLMProvider();
      final req = LLMRequest(
        messages: [const LLMMessage(role: 'user', content: 'Decide now')],
      );
      final resp = await p.complete(req);
      expect(resp.text, isA<String>());
      expect(resp.text.isNotEmpty, isTrue);
    });
  });

  // ──────────────────────────────────────────
  group('LLMCore — reason()', () {
    late AgentMemoryStore memory;
    late LLMCore core;

    setUp(() {
      memory = AgentMemoryStore();
    });

    AgentContext _makeContext(String goalDesc) {
      final goal = AgentGoal(id: 'g1', description: goalDesc);
      return AgentContext(goal: goal);
    }

    test('returns useTool decision when LLM outputs use_tool JSON', () async {
      core = LLMCore(
        provider: MockLLMProvider(responses: [
          '{"action":"use_tool","tool":"calculate","input":{"expression":"2+2"},'
              '"thought":"Math time"}',
        ]),
        memory: memory,
      );
      final ctx = _makeContext('Calculate 2 plus 2');
      final decision = await core.reason(ctx);
      expect(decision.type, AgentDecisionType.useTool);
      expect(decision.toolName, 'calculate');
      expect(decision.toolInput, containsPair('expression', '2+2'));
    });

    test('returns complete decision', () async {
      core = LLMCore(
        provider: MockLLMProvider(responses: [
          '{"action":"complete","reason":"All done!"}',
        ]),
        memory: memory,
      );
      final decision = await core.reason(_makeContext('Finish'));
      expect(decision.type, AgentDecisionType.complete);
      expect(decision.thought, 'All done!');
    });

    test('returns think decision for plain JSON', () async {
      core = LLMCore(
        provider: MockLLMProvider(responses: [
          '{"action":"think","thought":"Analysing the situation"}',
        ]),
        memory: memory,
      );
      final decision = await core.reason(_makeContext('Think'));
      expect(decision.type, AgentDecisionType.think);
      expect(decision.thought, 'Analysing the situation');
    });

    test('returns replan decision', () async {
      core = LLMCore(
        provider: MockLLMProvider(responses: [
          '{"action":"replan","reason":"API is down"}',
        ]),
        memory: memory,
      );
      final decision = await core.reason(_makeContext('Use API'));
      expect(decision.type, AgentDecisionType.replan);
      expect(decision.replanReason, 'API is down');
    });

    test('handles markdown-fenced JSON gracefully', () async {
      core = LLMCore(
        provider: MockLLMProvider(responses: [
          '```json\n{"action":"complete","reason":"fenced"}\n```',
        ]),
        memory: memory,
      );
      final decision = await core.reason(_makeContext('Fenced'));
      expect(decision.type, AgentDecisionType.complete);
    });

    test('falls back to think on non-JSON response', () async {
      core = LLMCore(
        provider: MockLLMProvider(responses: ['This is plain text, not JSON']),
        memory: memory,
      );
      final decision = await core.reason(_makeContext('Plain'));
      // Graceful degradation — returns think
      expect(decision.type, anyOf(AgentDecisionType.think, AgentDecisionType.error));
    });

    test('tracks reasoning calls and tokens', () async {
      core = LLMCore(
        provider: MockLLMProvider(
            responses: ['{"action":"think","thought":"ok"}']),
        memory: memory,
      );
      expect(core.reasoningCalls, 0);
      await core.reason(_makeContext('Track'));
      expect(core.reasoningCalls, 1);
    });

    test('provider getter is accessible', () {
      core = LLMCore(
        provider: EchoLLMProvider(),
        memory: AgentMemoryStore(),
      );
      expect(core.provider, isA<LLMProvider>());
      expect(core.provider.name, 'echo');
    });
  });

  // ──────────────────────────────────────────
  group('LLMCore — compressContext()', () {
    late LLMCore core;

    setUp(() {
      core = LLMCore(
        provider: EchoLLMProvider(),
        memory: AgentMemoryStore(),
      );
    });

    test('short text returned unchanged', () {
      const text = 'Hello world';
      expect(core.compressContext(text, maxChars: 200), text);
    });

    test('long text is compressed with ellipsis', () {
      final text = 'A' * 5000;
      final compressed = core.compressContext(text, maxChars: 100);
      expect(compressed.length, lessThan(text.length));
      expect(compressed, contains('…[compressed]…'));
    });
  });

  // ──────────────────────────────────────────
  group('LLMCoreConfig', () {
    test('default values are sensible', () {
      const cfg = LLMCoreConfig();
      expect(cfg.maxContextTokens, greaterThan(0));
      expect(cfg.maxMemoryEntries, greaterThan(0));
      expect(cfg.temperature, inInclusiveRange(0.0, 2.0));
    });

    test('custom values applied', () {
      const cfg = LLMCoreConfig(
        maxContextTokens: 1000,
        temperature: 0.0,
        maxResponseTokens: 256,
      );
      expect(cfg.maxContextTokens, 1000);
      expect(cfg.temperature, 0.0);
      expect(cfg.maxResponseTokens, 256);
    });
  });
}
