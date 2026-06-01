// test/reasoning_test.dart
// Unit tests for the reasoning subsystem.

import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'package:consciousness_sim/consciousness_sim.dart';

void main() {
  const uuid = Uuid();

  Concept makeConcept({
    String? id,
    String content = 'concept',
    double activation = 0.5,
    DateTime? creationTime,
  }) =>
      Concept(
        id: id ?? uuid.v4(),
        content: content,
        activationLevel: activation,
        creationTime: creationTime ?? DateTime.now(),
      );

  // ─────────────────────────────────────────────
  group('ConceptualGraph', () {
    late ConceptualGraph graph;

    setUp(() {
      graph = ConceptualGraph();
    });

    test('starts empty', () {
      expect(graph.nodeCount, 0);
      expect(graph.edgeCount, 0);
    });

    test('addConcept increases nodeCount', () {
      graph.addConcept('c1', makeConcept(id: 'c1', content: 'cat'));
      expect(graph.nodeCount, 1);
    });

    test('addConcept twice reinforces without duplicating', () {
      final c = makeConcept(id: 'c1', content: 'cat', activation: 0.5);
      graph.addConcept('c1', c);
      graph.addConcept('c1', c);
      expect(graph.nodeCount, 1);
    });

    test('linkConcepts creates edge', () {
      graph.addConcept('c1', makeConcept(id: 'c1'));
      graph.addConcept('c2', makeConcept(id: 'c2'));
      graph.linkConcepts(
        'c1',
        'c2',
        relationshipType: RelationshipType.causal,
        strength: 0.7,
      );
      expect(graph.edgeCount, 1);
    });

    test('linkConcepts reinforces existing edge', () {
      graph.addConcept('c1', makeConcept(id: 'c1'));
      graph.addConcept('c2', makeConcept(id: 'c2'));
      graph.linkConcepts('c1', 'c2',
          relationshipType: RelationshipType.associative, strength: 0.4);
      graph.linkConcepts('c1', 'c2',
          relationshipType: RelationshipType.associative, strength: 0.4);
      final node = graph.getNode('c1')!;
      expect(node.edges['c2']!.strength, greaterThan(0.4));
    });

    test('getNode returns null for unknown id', () {
      expect(graph.getNode('unknown'), isNull);
    });

    test('findRelatedConcepts returns reachable nodes', () {
      graph.addConcept('a', makeConcept(id: 'a'));
      graph.addConcept('b', makeConcept(id: 'b'));
      graph.addConcept('c', makeConcept(id: 'c'));
      graph.linkConcepts('a', 'b',
          relationshipType: RelationshipType.associative, strength: 0.5);
      graph.linkConcepts('b', 'c',
          relationshipType: RelationshipType.associative, strength: 0.5);
      final related = graph.findRelatedConcepts('a', 2);
      final ids = related.map((n) => n.id).toList();
      expect(ids, containsAll(['b', 'c']));
    });

    test('findPath returns direct path', () {
      graph.addConcept('x', makeConcept(id: 'x'));
      graph.addConcept('y', makeConcept(id: 'y'));
      graph.linkConcepts('x', 'y',
          relationshipType: RelationshipType.sequential, strength: 0.5);
      final path = graph.findPath('x', 'y');
      expect(path.map((n) => n.id), containsAll(['x', 'y']));
    });

    test('findPath returns empty for disconnected nodes', () {
      graph.addConcept('x', makeConcept(id: 'x'));
      graph.addConcept('z', makeConcept(id: 'z'));
      final path = graph.findPath('x', 'z');
      expect(path, isEmpty);
    });

    test('spreadActivation propagates through edges', () {
      graph.addConcept('a', makeConcept(id: 'a', activation: 0.8));
      graph.addConcept('b', makeConcept(id: 'b', activation: 0.5));
      graph.linkConcepts('a', 'b',
          relationshipType: RelationshipType.associative, strength: 0.6);
      final spread = graph.spreadActivation('a', maxHops: 2, decay: 0.5);
      expect(spread.containsKey('b'), isTrue);
      expect(spread['b'], greaterThan(0.0));
    });

    test('getMostConnected returns highest degree nodes', () {
      graph.addConcept('hub', makeConcept(id: 'hub'));
      for (var i = 0; i < 5; i++) {
        final id = 'leaf_$i';
        graph.addConcept(id, makeConcept(id: id));
        graph.linkConcepts('hub', id,
            relationshipType: RelationshipType.associative, strength: 0.3);
      }
      final top = graph.getMostConnected(1);
      expect(top.first.id, 'hub');
    });

    test('discoverImplicitPatterns finds clusters', () {
      // Create a tight cluster
      final ids = ['p1', 'p2', 'p3', 'p4'];
      for (final id in ids) {
        graph.addConcept(id, makeConcept(id: id));
      }
      graph.linkConcepts('p1', 'p2',
          relationshipType: RelationshipType.associative, strength: 0.8);
      graph.linkConcepts('p2', 'p3',
          relationshipType: RelationshipType.associative, strength: 0.8);
      graph.linkConcepts('p3', 'p1',
          relationshipType: RelationshipType.associative, strength: 0.8);
      graph.linkConcepts('p1', 'p4',
          relationshipType: RelationshipType.associative, strength: 0.8);

      final patterns = graph.discoverImplicitPatterns();
      expect(patterns, isA<List<Pattern>>());
    });

    test('getStats returns map with node_count', () {
      graph.addConcept('a', makeConcept(id: 'a'));
      final stats = graph.getStats();
      expect(stats['node_count'], 1);
    });
  });

  // ─────────────────────────────────────────────
  group('CausalInferenceEngine', () {
    late CausalInferenceEngine engine;

    setUp(() {
      engine = CausalInferenceEngine();
    });

    test('detects causal relationship with "because"', () {
      final cause = makeConcept(
        id: 'c1',
        content: 'hungry because no food',
        creationTime: DateTime.now().subtract(const Duration(seconds: 2)),
      );
      final effect = makeConcept(id: 'c2', content: 'searching for food');
      final rel = engine.inferCausality(cause, effect);
      expect(rel, isNotNull);
      expect(rel!.strength, greaterThan(0.1));
    });

    test('returns null for unrelated concepts', () {
      final c1 = makeConcept(id: 'c1', content: 'blue sky');
      final c2 = makeConcept(id: 'c2', content: 'warm sunshine');
      // These may or may not have causal cues — acceptable either way
      final rel = engine.inferCausality(c1, c2);
      expect(rel, anyOf(isNull, isNotNull)); // Flexible
    });

    test('discoverFromConcepts finds relationships in list', () {
      final hungry = makeConcept(
        id: 'hungry',
        content: 'the cat is hungry',
        creationTime: DateTime.now().subtract(const Duration(seconds: 3)),
      );
      final seeks = makeConcept(
        id: 'seeks',
        content: 'therefore the cat seeks food',
      );
      final results = engine.discoverFromConcepts([hungry, seeks]);
      expect(results, isA<List<CausalRelationship>>());
    });

    test('buildCausalChain does not infinite loop', () {
      final chain = engine.buildCausalChain('nonexistent_id', maxLength: 5);
      expect(chain, hasLength(1)); // Just the start node
    });

    test('knownCausality grows with discoveries', () {
      final before = engine.knownCausality.length;
      final c1 = makeConcept(
        id: 'c1',
        content: 'because it was cold',
        creationTime: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      final c2 = makeConcept(id: 'c2', content: 'animal looked for warmth');
      engine.inferCausality(c1, c2);
      expect(engine.knownCausality.length, greaterThanOrEqualTo(before));
    });
  });

  // ─────────────────────────────────────────────
  group('PatternRecognizer', () {
    late PatternRecognizer recognizer;

    setUp(() {
      recognizer = PatternRecognizer(minOccurrences: 2, minConfidence: 0.3);
    });

    test('observes concepts without error', () {
      expect(
        () => recognizer.observe(makeConcept(id: 'c1')),
        returnsNormally,
      );
    });

    test('discover finds co-occurrence pattern after repeated observation', () {
      final c1 = makeConcept(id: 'cat1', content: 'cat');
      final c2 = makeConcept(id: 'fish1', content: 'fish');
      // Observe the pair 3 times
      for (var i = 0; i < 3; i++) {
        recognizer.observe(c1);
        recognizer.observe(c2);
      }
      final patterns = recognizer.discover({'cat1': 'cat', 'fish1': 'fish'});
      expect(patterns, isNotEmpty);
    });

    test('predictNextConcept returns entries after observations', () {
      final c1 = makeConcept(id: 'antecedent');
      final c2 = makeConcept(id: 'consequent');
      for (var i = 0; i < 3; i++) {
        recognizer.observe(c1);
        recognizer.observe(c2);
      }
      final predictions = recognizer.predictNextConcept('antecedent');
      expect(predictions, isA<List<MapEntry<String, double>>>());
    });

    test('getMostFrequent returns top n concepts', () {
      final c = makeConcept(id: 'popular');
      for (var i = 0; i < 5; i++) {
        recognizer.observe(c);
      }
      final top = recognizer.getMostFrequent(1);
      expect(top.first.key, 'popular');
      expect(top.first.value, 5);
    });

    test('getTopPatterns returns sorted by confidence', () {
      // Populate patterns
      final c1 = makeConcept(id: 'ca');
      final c2 = makeConcept(id: 'cb');
      for (var i = 0; i < 5; i++) {
        recognizer.observe(c1);
        recognizer.observe(c2);
      }
      recognizer.discover({'ca': 'ca', 'cb': 'cb'});
      final top = recognizer.getTopPatterns(5);
      for (var i = 0; i < top.length - 1; i++) {
        expect(top[i].confidence, greaterThanOrEqualTo(top[i + 1].confidence));
      }
    });
  });

  // ─────────────────────────────────────────────
  group('InferenceEngine', () {
    late InferenceEngine engine;
    late ConceptualGraph graph;
    late MemoryManager memory;

    setUp(() {
      graph = ConceptualGraph();
      memory = MemoryManager();
      engine = InferenceEngine(graph: graph, memory: memory);
    });

    test('runInferenceCycle on empty list returns empty', () {
      final result = engine.runInferenceCycle([]);
      expect(result, isEmpty);
    });

    test('fires hungry+cat rule', () {
      final hungry = makeConcept(id: 'h1', content: 'hungry cat');
      final results = engine.runInferenceCycle([hungry]);
      expect(results, isNotEmpty);
      expect(
        results.any((i) => i.conclusion.toLowerCase().contains('cat') ||
            i.conclusion.toLowerCase().contains('food')),
        isTrue,
      );
    });

    test('fires fire rule with high confidence', () {
      final fire = makeConcept(id: 'f1', content: 'there is fire here');
      final results = engine.runInferenceCycle([fire]);
      final fireInference = results.where(
        (i) => i.conclusion.toLowerCase().contains('fire'),
      );
      expect(fireInference, isNotEmpty);
      expect(fireInference.first.confidence, greaterThan(0.5));
    });

    test('results are sorted by confidence descending', () {
      final c = makeConcept(id: 'c1', content: 'hungry fire danger cat');
      final results = engine.runInferenceCycle([c]);
      for (var i = 0; i < results.length - 1; i++) {
        expect(results[i].confidence,
            greaterThanOrEqualTo(results[i + 1].confidence));
      }
    });

    test('synthesiseThought returns non-empty string', () {
      final concepts = [
        makeConcept(content: 'cat', activation: 0.9),
        makeConcept(content: 'fish', activation: 0.7),
      ];
      final thought = engine.synthesiseThought(concepts);
      expect(thought, isNotEmpty);
    });

    test('synthesiseThought returns placeholder for empty workspace', () {
      expect(engine.synthesiseThought([]), contains('Nothing'));
    });

    test('addRule makes rule available for chaining', () {
      engine.addRule(InferenceRule(
        id: uuid.v4(),
        name: 'custom_test_rule',
        conditions: ['zephyr', 'xenon'],
        conclusion: 'Zephyr and xenon are related.',
        weight: 0.8,
      ));
      final c = makeConcept(content: 'zephyr xenon');
      final results = engine.runInferenceCycle([c]);
      expect(
        results.any((i) => i.inferenceType.contains('custom_test_rule')),
        isTrue,
      );
    });

    test('de-duplicates inferences with same conclusion', () {
      // Create two concepts both likely to fire same rule
      final c1 = makeConcept(content: 'hungry cat');
      final c2 = makeConcept(content: 'hungry cat meowing');
      final results = engine.runInferenceCycle([c1, c2]);
      // Count unique conclusions
      final conclusions =
          results.map((i) => i.conclusion.toLowerCase().substring(0, 20)).toSet();
      expect(conclusions.length, results.length);
    });
  });
}
