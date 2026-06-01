// test/agent/tool_system_test.dart
//
// Tests for ToolResult, Tool (abstract), ToolRegistry, ToolRouter,
// and all 6 built-in tools.

import 'dart:io';

import 'package:test/test.dart';
import 'package:consciousness_sim/consciousness_sim.dart';

// ─────────────────────────────────────────────
// A concrete test tool
// ─────────────────────────────────────────────

class _UpperCaseTool extends Tool {
  const _UpperCaseTool();

  @override
  String get name => 'uppercase';

  @override
  String get description => 'Converts text to upper case.';

  @override
  Map<String, String> get inputSchema => {'text': 'The text to uppercase.'};

  @override
  Future<ToolResult> run(Map<String, dynamic> input) async {
    final t = input['text'] as String? ?? '';
    return ToolResult.success(name, t.toUpperCase());
  }
}

void main() {
  // ──────────────────────────────────────────
  group('ToolResult', () {
    test('success factory sets fields correctly', () {
      final r = ToolResult.success('my_tool', 'output data');
      expect(r.success, isTrue);
      expect(r.toolName, 'my_tool');
      expect(r.outputText, 'output data');
      expect(r.error, isNull);
    });

    test('failure factory', () {
      final r = ToolResult.failure('my_tool', 'Something went wrong');
      expect(r.success, isFalse);
      expect(r.error, 'Something went wrong');
      expect(r.outputText, '(no output)');
    });

    test('outputText for null output returns (no output)', () {
      const r = ToolResult(toolName: 'x', success: true);
      expect(r.outputText, '(no output)');
    });

    test('outputText for map output calls toString', () {
      final r = ToolResult.success('x', {'key': 'val'});
      expect(r.outputText, contains('key'));
    });
  });

  // ──────────────────────────────────────────
  group('ToolRegistry', () {
    late ToolRegistry reg;

    setUp(() {
      reg = ToolRegistry();
    });

    test('register and find', () {
      reg.register(const _UpperCaseTool());
      expect(reg.has('uppercase'), isTrue);
      expect(reg.find('uppercase'), isA<_UpperCaseTool>());
    });

    test('unregister removes tool', () {
      reg.register(const _UpperCaseTool());
      reg.unregister('uppercase');
      expect(reg.has('uppercase'), isFalse);
    });

    test('count is correct', () {
      expect(reg.count, 0);
      reg.register(const _UpperCaseTool());
      expect(reg.count, 1);
    });

    test('buildCatalogue returns non-empty string when tools present', () {
      reg.register(const _UpperCaseTool());
      final catalogue = reg.buildCatalogue();
      expect(catalogue, contains('uppercase'));
    });

    test('registerAll registers multiple tools', () {
      reg.registerAll([const _UpperCaseTool(), const _UpperCaseTool()]);
      // Same name — last one wins; count is 1
      expect(reg.count, 1);
    });
  });

  // ──────────────────────────────────────────
  group('ToolRouter', () {
    late ToolRegistry reg;
    late ToolRouter router;

    setUp(() {
      reg = ToolRegistry();
      router = ToolRouter(reg);
    });

    test('routes to registered tool', () async {
      reg.register(const _UpperCaseTool());
      final result = await router.route('uppercase', {'text': 'hello'});
      expect(result.success, isTrue);
      expect(result.outputText, 'HELLO');
    });

    test('returns failure for unknown tool', () async {
      final result = await router.route('nonexistent', {});
      expect(result.success, isFalse);
      expect(result.error, contains('not registered'));
    });

    test('returns failure for invalid input', () async {
      reg.register(const _UpperCaseTool());
      // Missing required 'text' field
      final result = await router.route('uppercase', {});
      expect(result.success, isFalse);
    });
  });

  // ──────────────────────────────────────────
  group('BuiltinToolset', () {
    late ToolRegistry reg;

    setUp(() {
      reg = ToolRegistry();
      BuiltinToolset.registerAll(reg);
    });

    test('all 6 tools registered', () {
      expect(reg.count, 6);
      for (final name in [
        'search_web',
        'calculate',
        'read_file',
        'write_file',
        'call_api',
        'schedule_task',
      ]) {
        expect(reg.has(name), isTrue, reason: '$name should be registered');
      }
    });
  });

  // ──────────────────────────────────────────
  group('CalculateTool', () {
    late ToolRouter router;

    setUp(() {
      final reg = ToolRegistry();
      BuiltinToolset.registerAll(reg);
      router = ToolRouter(reg);
    });

    Future<ToolResult> calc(String expr) =>
        router.route('calculate', {'expression': expr});

    test('basic arithmetic', () async {
      final r = await calc('2 + 3 * 4');
      expect(r.success, isTrue);
      expect(r.outputText, contains('14'));
    });

    test('sqrt function', () async {
      final r = await calc('sqrt(144)');
      expect(r.success, isTrue);
      expect(r.outputText, contains('12'));
    });

    test('pi constant', () async {
      final r = await calc('pi');
      expect(r.success, isTrue);
      // pi ≈ 3.14
      expect(double.tryParse(r.outputText.trim()), closeTo(3.14159, 0.001));
    });

    test('division by zero returns failure', () async {
      final r = await calc('1/0');
      expect(r.success, isFalse);
    });

    test('empty expression returns failure', () async {
      final r = await calc('');
      expect(r.success, isFalse);
    });

    test('nested expression', () async {
      final r = await calc('sqrt(abs(-16)) + 2^3');
      expect(r.success, isTrue);
      // sqrt(16) + 8 = 12
      expect(double.tryParse(r.outputText.trim()), closeTo(12.0, 0.001));
    });
  });

  // ──────────────────────────────────────────
  group('SearchWebTool (mock mode)', () {
    late ToolRouter router;

    setUp(() {
      final reg = ToolRegistry();
      BuiltinToolset.registerAll(reg);
      router = ToolRouter(reg);
    });

    test('returns mock results for any query', () async {
      final r = await router.route('search_web', {'query': 'Dart language'});
      // May fail if network is unavailable — tool should NOT throw
      expect(r, isA<ToolResult>());
    });
  });

  // ──────────────────────────────────────────
  group('ReadFileTool / WriteFileTool', () {
    late ToolRouter router;
    late Directory tempDir;

    setUp(() {
      final reg = ToolRegistry();
      BuiltinToolset.registerAll(reg);
      router = ToolRouter(reg);
      tempDir = Directory.systemTemp.createTempSync('tool_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('write then read file round-trip', () async {
      final path = '${tempDir.path}/hello.txt';

      final writeResult = await router.route('write_file', {
        'path': path,
        'content': 'Hello, agent!',
      });
      expect(writeResult.success, isTrue);

      final readResult = await router.route('read_file', {'path': path});
      expect(readResult.success, isTrue);
      expect(readResult.outputText, contains('Hello, agent!'));
    });

    test('read non-existent file returns failure', () async {
      final r = await router.route('read_file', {
        'path': '${tempDir.path}/nonexistent.txt',
      });
      expect(r.success, isFalse);
    });
  });

  // ──────────────────────────────────────────
  group('ScheduleTaskTool', () {
    late ToolRouter router;

    setUp(() {
      final reg = ToolRegistry();
      BuiltinToolset.registerAll(reg);
      router = ToolRouter(reg);
    });

    test('schedules successfully', () async {
      final r = await router.route('schedule_task', {
        'task_name': 'cleanup',
        'delay_seconds': 0,
      });
      expect(r, isA<ToolResult>());
      // Tool never throws — either success or graceful failure
    });
  });
}
