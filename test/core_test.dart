// test/core_test.dart
// Unit tests for the core subsystems: models, workspace, attention, binding.

import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'package:consciousness_sim/consciousness_sim.dart';

void main() {
  const uuid = Uuid();

  // ── Helper factories ─────────────────────────

  Concept makeConcept({
    String? id,
    String content = 'test concept',
    double activation = 0.5,
    double familiarity = 0.3,
    double relevance = 0.5,
    EmotionalValence valence = EmotionalValence.neutral,
    double intensity = 0.0,
  }) =>
      Concept(
        id: id ?? uuid.v4(),
        content: content,
        activationLevel: activation,
        familiarity: familiarity,
        contextualRelevance: relevance,
        emotionalValence: valence,
        emotionalIntensity: intensity,
      );

  // ─────────────────────────────────────────────
  group('Concept', () {
    test('novelty score is inverse of familiarity', () {
      final c = makeConcept(familiarity: 0.3);
      expect(c.noveltyScore, closeTo(0.7, 0.01));
    });

    test('salience is weighted combination of factors', () {
      final c = makeConcept(familiarity: 0.2, relevance: 0.8);
      final salience = c.calculateSalience();
      expect(salience, greaterThan(0.0));
      expect(salience, lessThanOrEqualTo(1.0));
    });

    test('emotional boost raises salience for negative concepts', () {
      final neutral = makeConcept(valence: EmotionalValence.neutral);
      final scary = makeConcept(
        valence: EmotionalValence.veryNegative,
        intensity: 0.9,
      );
      expect(
        scary.calculateSalience(),
        greaterThan(neutral.calculateSalience()),
      );
    });

    test('copyWith preserves all fields except updated ones', () {
      final original = makeConcept(content: 'original', activation: 0.4);
      final copy = original.copyWith(activationLevel: 0.9);
      expect(copy.content, 'original');
      expect(copy.activationLevel, closeTo(0.9, 0.01));
      expect(copy.id, original.id);
    });

    test('recency score is high for freshly created concepts', () {
      final fresh = makeConcept();
      expect(fresh.recencyScore, greaterThan(0.9));
    });
  });

  // ─────────────────────────────────────────────
  group('SemanticVector', () {
    test('cosine similarity of identical vectors is 1.0', () {
      const v = SemanticVector([1.0, 0.0, 0.0]);
      expect(v.cosineSimilarity(v), closeTo(1.0, 0.001));
    });

    test('cosine similarity of orthogonal vectors is 0.0', () {
      const v1 = SemanticVector([1.0, 0.0]);
      const v2 = SemanticVector([0.0, 1.0]);
      expect(v1.cosineSimilarity(v2), closeTo(0.0, 0.001));
    });

    test('euclidean distance of identical vectors is 0', () {
      const v = SemanticVector([1.0, 2.0, 3.0]);
      expect(v.euclideanDistance(v), closeTo(0.0, 0.001));
    });

    test('magnitude is computed correctly', () {
      const v = SemanticVector([3.0, 4.0]);
      expect(v.magnitude, closeTo(5.0, 0.001)); // 3-4-5 triangle
    });
  });

  // ─────────────────────────────────────────────
  group('WorkspaceManager', () {
    late WorkspaceManager workspace;

    setUp(() {
      workspace = WorkspaceManager(capacity: 4);
    });

    test('workspace starts empty', () {
      expect(workspace.size, 0);
    });

    test('broadcasts concept into workspace', () {
      final c = makeConcept(id: 'c1', content: 'cat');
      workspace.broadcast(c);
      expect(workspace.contains('c1'), isTrue);
      expect(workspace.size, 1);
    });

    test('reinforces existing concept without duplicating', () {
      final c = makeConcept(id: 'c1', content: 'cat');
      workspace.broadcast(c);
      workspace.broadcast(c);
      expect(workspace.size, 1);
    });

    test('evicts least salient when at capacity', () {
      for (var i = 0; i < 5; i++) {
        workspace.broadcast(makeConcept(
          id: 'c$i',
          content: 'concept$i',
          activation: 0.1 + i * 0.1,
        ));
      }
      // Capacity is 4, so one should be evicted
      expect(workspace.size, lessThanOrEqualTo(4));
    });

    test('suppresses concept by id', () {
      final c = makeConcept(id: 'c1');
      workspace.broadcast(c);
      workspace.suppress('c1');
      expect(workspace.contains('c1'), isFalse);
    });

    test('spotlight returns highest-salience concept', () {
      workspace.broadcast(makeConcept(id: 'low', activation: 0.1));
      workspace.broadcast(makeConcept(id: 'high', activation: 0.9));
      final focus = workspace.getSpotlightFocus();
      expect(focus?.id, 'high');
    });

    test('coherence is between 0 and 1', () {
      workspace.broadcast(makeConcept(id: 'a'));
      workspace.broadcast(makeConcept(id: 'b'));
      expect(workspace.computeCoherence(), inInclusiveRange(0.0, 1.0));
    });

    test('interactions map is populated for multiple concepts', () {
      workspace.broadcast(makeConcept(id: 'a'));
      workspace.broadcast(makeConcept(id: 'b'));
      final interactions = workspace.computeInteractions();
      expect(interactions, isNotEmpty);
    });
  });

  // ─────────────────────────────────────────────
  group('AttentionSpotlight', () {
    late AttentionSpotlight spotlight;

    setUp(() {
      spotlight = AttentionSpotlight(attentionThreshold: 0.2);
    });

    test('focus sets primary focus id', () {
      spotlight.focus('concept_1', 0.8);
      expect(spotlight.primaryFocusId, 'concept_1');
    });

    test('weight of focused concept matches intensity', () {
      spotlight.focus('concept_1', 0.75);
      expect(spotlight.weightOf('concept_1'), closeTo(0.75, 0.01));
    });

    test('withdrawing focus clears primary', () {
      spotlight.focus('concept_1', 0.8);
      spotlight.withdraw('concept_1');
      expect(spotlight.primaryFocusId, isNot('concept_1'));
    });

    test('evaluateAndFocus picks most salient concept', () {
      final low = makeConcept(id: 'low', activation: 0.1, relevance: 0.1);
      final high = makeConcept(id: 'high', activation: 0.9, relevance: 0.9);
      final result = spotlight.evaluateAndFocus([low, high]);
      expect(result, 'high');
    });

    test('rebalance boosts listed priorities', () {
      spotlight.focus('a', 0.5);
      spotlight.focus('b', 0.5);
      spotlight.rebalance(['b']);
      expect(spotlight.weightOf('b'), greaterThanOrEqualTo(0.4));
    });

    test('salience calculation is within bounds', () {
      final c = makeConcept(relevance: 0.7, familiarity: 0.2, intensity: 0.5);
      final salience = spotlight.calculateSalience(c);
      expect(salience, inInclusiveRange(0.0, 1.0));
    });
  });

  // ─────────────────────────────────────────────
  group('BindingEngine', () {
    late BindingEngine engine;

    setUp(() {
      engine = BindingEngine();
    });

    test('explicit binding returns correct relationship type', () {
      final c1 = makeConcept(id: 'c1', content: 'cat');
      final c2 = makeConcept(id: 'c2', content: 'hungry');
      final result = engine.bindExplicit(
        concept1: c1,
        concept2: c2,
        relationshipType: RelationshipType.causal,
        strength: 0.7,
      );
      expect(result.relationshipType, RelationshipType.causal);
      expect(result.strength, closeTo(0.7, 0.01));
      expect(result.wasReinforced, isFalse);
    });

    test('explicit binding reinforces existing edge', () {
      final c1 = makeConcept(id: 'c1', content: 'cat');
      final c2 = makeConcept(id: 'c2', content: 'food');
      final existingEdge = ConceptEdge(
        sourceId: 'c1',
        targetId: 'c2',
        relationshipType: RelationshipType.associative,
        strength: 0.5,
      );
      final result = engine.bindExplicit(
        concept1: c1,
        concept2: c2,
        relationshipType: RelationshipType.associative,
        existingEdge: existingEdge,
      );
      expect(result.wasReinforced, isTrue);
      expect(result.strength, greaterThan(0.5));
    });

    test('workspace binding produces results for semantically similar concepts',
        () {
      final c1 = makeConcept(id: 'c1', content: 'cat hungry');
      final c2 = makeConcept(id: 'c2', content: 'cat food');
      final results = engine.bindWorkspace([c1, c2], []);
      // Expect at least one binding between the cat-related concepts
      expect(results, isNotEmpty);
    });

    test('register and bind fills recent buffer', () {
      final c1 = makeConcept(id: 'c1', content: 'cat');
      final c2 = makeConcept(id: 'c2', content: 'hungry');
      engine.registerAndBind(c1, []);
      final results = engine.registerAndBind(c2, []);
      // Both registered — possible binding
      expect(results, isA<List<BindingResult>>());
    });
  });

  // ─────────────────────────────────────────────
  group('InferenceRule', () {
    test('matches returns true when all conditions present', () {
      final rule = InferenceRule(
        id: '1',
        name: 'test_rule',
        conditions: ['cat', 'hungry'],
        conclusion: 'cat seeks food',
        weight: 0.9,
      );
      expect(rule.matches({'cat', 'hungry', 'table'}), isTrue);
    });

    test('matches returns false when condition missing', () {
      final rule = InferenceRule(
        id: '1',
        name: 'test_rule',
        conditions: ['cat', 'hungry'],
        conclusion: 'cat seeks food',
        weight: 0.9,
      );
      expect(rule.matches({'cat', 'fish'}), isFalse);
    });

    test('weight must be in [0, 1]', () {
      expect(
        () => InferenceRule(
          id: '1',
          name: 'bad',
          conditions: [],
          conclusion: '',
          weight: 1.5,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  // ─────────────────────────────────────────────
  group('ConsciousState', () {
    test('primaryConclusion returns highest-confidence inference', () {
      final concepts = [makeConcept(id: 'c1')];
      final inferences = [
        Inference(
          id: '1',
          conclusion: 'low confidence',
          premises: [],
          confidence: 0.3,
          inferenceType: 'test',
        ),
        Inference(
          id: '2',
          conclusion: 'high confidence',
          premises: [],
          confidence: 0.9,
          inferenceType: 'test',
        ),
      ];
      final state = ConsciousState(
        workspace: concepts,
        focusedConceptId: 'c1',
        activationMap: {'c1': 0.8},
        inferencesGenerated: inferences,
        coherence: 0.7,
      );
      expect(state.primaryConclusion, 'high confidence');
    });

    test('focusedConcept returns correct concept', () {
      final c = makeConcept(id: 'focal');
      final state = ConsciousState(
        workspace: [c],
        focusedConceptId: 'focal',
        activationMap: {'focal': 0.9},
        inferencesGenerated: [],
      );
      expect(state.focusedConcept?.id, 'focal');
    });
  });

  // ─────────────────────────────────────────────
  group('Memory', () {
    test('decay reduces strength over time', () {
      final memory = Memory(
        id: 'test',
        content: 'something happened',
        type: MemoryType.episodic,
        strength: 1.0,
        // Backdate the timestamp to simulate age
        timestamp: DateTime.now().subtract(const Duration(hours: 24)),
      );
      memory.applyDecay(halfLifeHours: 24.0);
      expect(memory.strength, lessThan(1.0));
    });

    test('reinforce increases strength', () {
      final memory = Memory(
        id: 'test',
        content: 'recalled memory',
        type: MemoryType.episodic,
        strength: 0.5,
      );
      memory.reinforce(amount: 0.3);
      expect(memory.strength, greaterThan(0.5));
      expect(memory.recallCount, 1);
    });

    test('reinforce does not exceed 1.0', () {
      final memory = Memory(
        id: 'test',
        content: 'strong memory',
        type: MemoryType.episodic,
        strength: 0.9,
      );
      memory.reinforce(amount: 0.5);
      expect(memory.strength, lessThanOrEqualTo(1.0));
    });
  });
}
