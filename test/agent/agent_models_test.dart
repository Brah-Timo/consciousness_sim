// test/agent/agent_models_test.dart
//
// Unit tests for all types in lib/agent/agent_models.dart

import 'package:test/test.dart';
import 'package:consciousness_sim/consciousness_sim.dart';

void main() {
  // ──────────────────────────────────────────
  group('AgentGoal', () {
    test('default priority and maxIterations', () {
      final g = AgentGoal(id: 'g1', description: 'Test goal');
      expect(g.priority, closeTo(0.5, 0.001));
      expect(g.maxIterations, 20);
      expect(g.isComplete, isFalse);
      expect(g.successCriteria, isEmpty);
    });

    test('copyWith updates fields', () {
      final g = AgentGoal(id: 'g2', description: 'Copy test');
      final g2 = g.copyWith(priority: 0.9, isComplete: true);
      expect(g2.priority, closeTo(0.9, 0.001));
      expect(g2.isComplete, isTrue);
      expect(g2.id, 'g2'); // immutable fields preserved
    });

    test('successCriteria stored correctly', () {
      final g = AgentGoal(
        id: 'g3',
        description: 'Criteria test',
        successCriteria: ['Condition A', 'Condition B'],
      );
      expect(g.successCriteria, hasLength(2));
      expect(g.successCriteria.first, 'Condition A');
    });

    test('priority out of range asserts', () {
      expect(
        () => AgentGoal(id: 'x', description: 'x', priority: 1.5),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  // ──────────────────────────────────────────
  group('AgentTask', () {
    test('created with pending status', () {
      final t = AgentTask(id: 't1', goalId: 'g1', description: 'Task one');
      expect(t.status, TaskStatus.pending);
      expect(t.retryCount, 0);
      expect(t.result, isNull);
    });

    test('duration is null before execution', () {
      final t = AgentTask(id: 't2', goalId: 'g1', description: 'Task two');
      expect(t.duration, isNull);
    });

    test('duration computed after start/finish', () {
      final t = AgentTask(id: 't3', goalId: 'g1', description: 'Timed');
      t.startedAt = DateTime.now().subtract(const Duration(milliseconds: 100));
      t.finishedAt = DateTime.now();
      expect(t.duration!.inMilliseconds, greaterThanOrEqualTo(0));
    });

    test('dependsOnIds defaults to empty', () {
      final t = AgentTask(id: 't4', goalId: 'g1', description: 'Dep test');
      expect(t.dependsOnIds, isEmpty);
    });
  });

  // ──────────────────────────────────────────
  group('TaskResult', () {
    test('success result', () {
      final r = TaskResult(
        taskId: 't1',
        success: true,
        output: 'hello',
        completedAt: DateTime.now(),
      );
      expect(r.success, isTrue);
      expect(r.output, 'hello');
      expect(r.error, isNull);
    });

    test('failure result', () {
      final r = TaskResult(
        taskId: 't2',
        success: false,
        error: 'Network error',
        completedAt: DateTime.now(),
      );
      expect(r.success, isFalse);
      expect(r.error, 'Network error');
    });
  });

  // ──────────────────────────────────────────
  group('AgentDecision', () {
    test('useTool factory sets correct fields', () {
      final d = AgentDecision.useTool(
        'search_web',
        {'query': 'Dart lang'},
        thought: 'Searching now',
      );
      expect(d.type, AgentDecisionType.useTool);
      expect(d.toolName, 'search_web');
      expect(d.toolInput, {'query': 'Dart lang'});
      expect(d.thought, 'Searching now');
    });

    test('think factory', () {
      final d = AgentDecision.think('I need more info', confidence: 0.7);
      expect(d.type, AgentDecisionType.think);
      expect(d.thought, 'I need more info');
      expect(d.confidence, closeTo(0.7, 0.001));
    });

    test('complete factory', () {
      final d = AgentDecision.complete('Goal achieved');
      expect(d.type, AgentDecisionType.complete);
      expect(d.thought, 'Goal achieved');
      expect(d.confidence, closeTo(1.0, 0.001));
    });

    test('replan factory', () {
      final d = AgentDecision.replan('API unavailable');
      expect(d.type, AgentDecisionType.replan);
      expect(d.replanReason, 'API unavailable');
    });

    test('confidence out of range asserts', () {
      expect(
        () => AgentDecision(type: AgentDecisionType.think, confidence: 1.5),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  // ──────────────────────────────────────────
  group('AgentContext', () {
    late AgentGoal goal;

    setUp(() {
      goal = AgentGoal(id: 'g1', description: 'Context test');
    });

    test('defaults to empty lists and iter 0', () {
      final ctx = AgentContext(goal: goal);
      expect(ctx.iterationNumber, 0);
      expect(ctx.activeTasks, isEmpty);
      expect(ctx.recentObservations, isEmpty);
      expect(ctx.workspaceConcepts, isEmpty);
      expect(ctx.retrievedMemories, isEmpty);
    });

    test('copyWith updates iterationNumber', () {
      final ctx = AgentContext(goal: goal);
      final ctx2 = ctx.copyWith(iterationNumber: 5);
      expect(ctx2.iterationNumber, 5);
      expect(ctx2.goal.id, 'g1'); // goal unchanged
    });

    test('copyWith updates observations', () {
      final ctx = AgentContext(goal: goal);
      final obs = [
        AgentObservation(
          id: 'o1',
          content: 'Hello',
          source: 'test',
        )
      ];
      final ctx2 = ctx.copyWith(recentObservations: obs);
      expect(ctx2.recentObservations, hasLength(1));
    });
  });

  // ──────────────────────────────────────────
  group('AgentMemoryEntry', () {
    test('recencyScore near 1.0 for fresh entry', () {
      final e = AgentMemoryEntry(
        id: 'm1',
        type: AgentMemoryType.observation,
        content: 'Fresh memory',
      );
      expect(e.recencyScore, closeTo(1.0, 0.01));
    });

    test('composite score = importance * recencyScore', () {
      final e = AgentMemoryEntry(
        id: 'm2',
        type: AgentMemoryType.decision,
        content: 'Score test',
        importance: 0.8,
      );
      expect(e.score, closeTo(e.importance * e.recencyScore, 0.001));
    });
  });

  // ──────────────────────────────────────────
  group('AgentRunResult', () {
    test('fields populated correctly', () {
      final r = AgentRunResult(
        goalId: 'g1',
        success: true,
        iterations: 5,
        tasksCompleted: 4,
        tasksFailed: 0,
        summary: 'All done',
        finishedAt: DateTime.now(),
      );
      expect(r.goalId, 'g1');
      expect(r.success, isTrue);
      expect(r.iterations, 5);
      expect(r.tasksCompleted, 4);
      expect(r.tasksFailed, 0);
      expect(r.summary, 'All done');
    });
  });
}
