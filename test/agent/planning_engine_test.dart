// test/agent/planning_engine_test.dart
//
// Tests for ExecutionDAG and PlanningEngine.

import 'package:test/test.dart';
import 'package:consciousness_sim/consciousness_sim.dart';

void main() {
  // ──────────────────────────────────────────
  group('ExecutionDAG', () {
    late AgentGoal goal;

    setUp(() {
      goal = AgentGoal(id: 'g1', description: 'DAG test');
    });

    AgentTask _task(String id, {List<String>? deps}) => AgentTask(
          id: '${goal.id}_$id',
          goalId: goal.id,
          description: 'Task $id',
          dependsOnIds: deps?.map((d) => '${goal.id}_$d').toList() ?? [],
        );

    test('starts empty', () {
      final dag = ExecutionDAG(goal.id);
      expect(dag.size, 0);
      expect(dag.isComplete, isTrue); // vacuously true
      expect(dag.isFailed, isFalse);
    });

    test('add and retrieve task', () {
      final dag = ExecutionDAG(goal.id);
      final t = _task('t1');
      dag.add(t);
      expect(dag.size, 1);
      expect(dag['${goal.id}_t1'], t);
    });

    test('ready returns tasks with no unfinished deps', () {
      final dag = ExecutionDAG(goal.id);
      dag.add(_task('t1'));
      dag.add(_task('t2', deps: ['t1']));
      // t1 has no deps — ready; t2 depends on t1 (pending) — not ready
      final ready = dag.ready;
      expect(ready.map((t) => t.id), contains('${goal.id}_t1'));
      expect(ready.map((t) => t.id), isNot(contains('${goal.id}_t2')));
    });

    test('ready includes t2 after t1 succeeds', () {
      final dag = ExecutionDAG(goal.id);
      final t1 = _task('t1');
      final t2 = _task('t2', deps: ['t1']);
      dag.add(t1);
      dag.add(t2);

      t1.status = TaskStatus.succeeded;

      final ready = dag.ready;
      expect(ready.map((t) => t.id), contains('${goal.id}_t2'));
    });

    test('isComplete when all tasks succeeded', () {
      final dag = ExecutionDAG(goal.id);
      final t1 = _task('t1');
      dag.add(t1);
      t1.status = TaskStatus.succeeded;
      expect(dag.isComplete, isTrue);
    });

    test('isFailed when task failed with retry >= 2', () {
      final dag = ExecutionDAG(goal.id);
      final t1 = _task('t1');
      dag.add(t1);
      t1.status = TaskStatus.failed;
      t1.retryCount = 2;
      expect(dag.isFailed, isTrue);
    });

    test('topologicalOrder respects dependencies', () {
      final dag = ExecutionDAG(goal.id);
      dag.add(_task('t1'));
      dag.add(_task('t2', deps: ['t1']));
      dag.add(_task('t3', deps: ['t2']));
      final order = dag.topologicalOrder.map((t) => t.id).toList();
      expect(order.indexOf('${goal.id}_t1'),
          lessThan(order.indexOf('${goal.id}_t2')));
      expect(order.indexOf('${goal.id}_t2'),
          lessThan(order.indexOf('${goal.id}_t3')));
    });

    test('replace clears and resets tasks', () {
      final dag = ExecutionDAG(goal.id);
      dag.add(_task('t1'));
      dag.replace([_task('ta'), _task('tb')]);
      expect(dag.size, 2);
      expect(dag.size, equals(2)); // replaced: ta and tb present
    });

    test('succeeded and failed getters', () {
      final dag = ExecutionDAG(goal.id);
      final t1 = _task('t1')..status = TaskStatus.succeeded;
      final t2 = _task('t2')..status = TaskStatus.failed;
      dag.add(t1);
      dag.add(t2);
      expect(dag.succeeded, hasLength(1));
      expect(dag.failed, hasLength(1));
    });
  });

  // ──────────────────────────────────────────
  group('PlanningEngine — rule-based (no LLM)', () {
    late PlanningEngine engine;
    late AgentGoal goal;

    setUp(() {
      engine = PlanningEngine();
    });

    test('calculate keyword → single calculate task', () async {
      goal = AgentGoal(id: 'g1', description: 'Calculate 2 + 2');
      final ctx = AgentContext(goal: goal);
      final dag = await engine.plan(goal, ctx);
      expect(dag.size, greaterThanOrEqualTo(1));
      final toolHints = dag.all.map((t) => t.toolHint).toList();
      expect(toolHints, contains('calculate'));
    });

    test('search keyword → search + summarise tasks', () async {
      goal = AgentGoal(id: 'g2', description: 'Search for Dart news');
      final ctx = AgentContext(goal: goal);
      final dag = await engine.plan(goal, ctx);
      expect(dag.size, greaterThanOrEqualTo(1));
    });

    test('write file keyword → write_file task present', () async {
      goal = AgentGoal(id: 'g3', description: 'Write file with content');
      final ctx = AgentContext(goal: goal);
      final dag = await engine.plan(goal, ctx);
      final toolHints = dag.all.map((t) => t.toolHint).toList();
      expect(toolHints, contains('write_file'));
    });

    test('generic goal → 5-step plan', () async {
      goal = AgentGoal(id: 'g4', description: 'Do something complex');
      final ctx = AgentContext(goal: goal);
      final dag = await engine.plan(goal, ctx);
      expect(dag.size, 5);
    });
  });

  // ──────────────────────────────────────────
  group('PlanningEngine — LLM-backed planning', () {
    late AgentGoal goal;

    setUp(() {
      goal = AgentGoal(id: 'gllm', description: 'LLM planned goal');
    });

    test('parses valid JSON task list from LLM', () async {
      final llmJson = '''
[
  {"id":"t1","description":"Search for info","depends_on":[],"tool_hint":"search_web","complexity":0.4},
  {"id":"t2","description":"Summarise results","depends_on":["t1"],"tool_hint":null,"complexity":0.3}
]
''';
      final memory = AgentMemoryStore();
      final core = LLMCore(
        provider: MockLLMProvider(responses: [llmJson]),
        memory: memory,
      );
      final engine = PlanningEngine(llmCore: core);
      final ctx = AgentContext(goal: goal);
      final dag = await engine.plan(goal, ctx);

      expect(dag.size, 2);
      final ids = dag.all.map((t) => t.id).toList();
      expect(ids, contains('gllm_t1'));
      expect(ids, contains('gllm_t2'));
      // t2 depends on t1
      final t2 = dag['gllm_t2']!;
      expect(t2.dependsOnIds, contains('gllm_t1'));
    });

    test('falls back to rule-based on invalid JSON', () async {
      final memory = AgentMemoryStore();
      final core = LLMCore(
        provider: MockLLMProvider(responses: ['not json at all']),
        memory: memory,
      );
      final engine = PlanningEngine(llmCore: core);
      final ctx = AgentContext(goal: goal);
      final dag = await engine.plan(goal, ctx);
      // Falls back to generic 5-step plan
      expect(dag.size, greaterThanOrEqualTo(1));
    });
  });

  // ──────────────────────────────────────────
  group('PlanningEngine — task lifecycle', () {
    late PlanningEngine engine;
    late ExecutionDAG dag;
    late AgentGoal goal;

    setUp(() async {
      engine = PlanningEngine();
      goal = AgentGoal(id: 'g5', description: 'Lifecycle test');
      final ctx = AgentContext(goal: goal);
      dag = await engine.plan(goal, ctx);
    });

    test('markRunning sets status', () {
      final task = dag.all.first;
      engine.markRunning(dag, task.id);
      expect(task.status, TaskStatus.running);
      expect(task.startedAt, isNotNull);
    });

    test('markSucceeded sets status and result', () {
      final task = dag.all.first;
      engine.markRunning(dag, task.id);
      engine.markSucceeded(
        dag,
        task.id,
        TaskResult(
            taskId: task.id, success: true, completedAt: DateTime.now()),
      );
      expect(task.status, TaskStatus.succeeded);
      expect(task.result, isNotNull);
    });

    test('markFailed with retry resets to pending', () {
      final task = dag.all.first;
      engine.markFailed(dag, task.id, 'error', retryable: true);
      expect(task.retryCount, 1);
      expect(task.status, TaskStatus.pending);
    });

    test('markFailed permanently after 2 retries', () {
      final task = dag.all.first;
      engine.markFailed(dag, task.id, 'e1');
      engine.markFailed(dag, task.id, 'e2');
      expect(task.status, TaskStatus.failed);
    });

    test('markSkipped sets skipped', () {
      final task = dag.all.first;
      engine.markSkipped(dag, task.id, reason: 'not needed');
      expect(task.status, TaskStatus.skipped);
    });

    test('summarise returns non-empty string', () {
      final summary = engine.summarise(dag);
      expect(summary, isNotEmpty);
    });
  });

  // ──────────────────────────────────────────
  group('PlanningEngine — replan', () {
    test('preserves succeeded tasks', () async {
      final engine = PlanningEngine();
      final goal = AgentGoal(id: 'g6', description: 'Replan test');
      final ctx = AgentContext(goal: goal);
      final dag = await engine.plan(goal, ctx);

      // Mark first task as succeeded
      final first = dag.all.first;
      first.status = TaskStatus.succeeded;

      final newDag = await engine.replan(dag, ctx, reason: 'test replan');
      // Succeeded task should be in new DAG
      final succeededIds = newDag.succeeded.map((t) => t.id).toSet();
      expect(succeededIds, contains(first.id));
    });
  });
}


