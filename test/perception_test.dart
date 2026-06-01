// test/perception_test.dart
// Unit tests for the perception subsystem.

import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'package:consciousness_sim/consciousness_sim.dart';

void main() {
  const uuid = Uuid();

  // ─────────────────────────────────────────────
  group('FeatureExtractor', () {
    late FeatureExtractor extractor;

    setUp(() {
      extractor = FeatureExtractor();
    });

    test('extracts entities from simple sentence', () {
      final features = extractor.extract('The cat sits on the mat');
      expect(features.entities, isNotEmpty);
    });

    test('detects spatial relations', () {
      final features = extractor.extract('cat is on the table');
      expect(features.spatialRelations, contains('on'));
    });

    test('detects emotional words', () {
      final features = extractor.extract('the dog is hungry and tired');
      expect(features.emotionalCues, containsAll(['hungry', 'tired']));
    });

    test('detects causal cues', () {
      final features = extractor.extract('because it is cold');
      expect(features.causalCues, isNotEmpty);
    });

    test('detects negation', () {
      final features = extractor.extract('the cat is not hungry');
      expect(features.negations, isNotEmpty);
    });

    test('detects question format', () {
      final features = extractor.extract('what is the cat doing?');
      expect(features.questions, isTrue);
    });

    test('does not flag statement as question', () {
      final features = extractor.extract('the cat is eating fish');
      expect(features.questions, isFalse);
    });

    test('detects temporal markers', () {
      final features = extractor.extract('before the storm, the sky was clear');
      expect(features.temporalMarkers, isNotEmpty);
    });

    test('toProperties returns a map with expected keys', () {
      final features = extractor.extract('cat eats fish');
      final props = features.toProperties();
      expect(props.containsKey('entities'), isTrue);
      expect(props.containsKey('actions'), isTrue);
      expect(props.containsKey('spatial'), isTrue);
    });

    test('detectEmotionalValence identifies negative state', () {
      final valence =
          extractor.detectEmotionalValence(['afraid', 'pain', 'danger']);
      expect(
        valence,
        anyOf(
          EmotionalValence.negative,
          EmotionalValence.veryNegative,
        ),
      );
    });

    test('detectEmotionalValence identifies positive state', () {
      final valence = extractor.detectEmotionalValence(['happy', 'joy', 'safe']);
      expect(
        valence,
        anyOf(
          EmotionalValence.positive,
          EmotionalValence.veryPositive,
        ),
      );
    });

    test('detectEmotionalValence returns neutral for empty list', () {
      final valence = extractor.detectEmotionalValence([]);
      expect(valence, EmotionalValence.neutral);
    });

    test('estimateEmotionalIntensity is higher for exclamations', () {
      final calm = extractor.estimateEmotionalIntensity('the cat is there');
      final excited = extractor.estimateEmotionalIntensity('DANGER!! FIRE!!');
      expect(excited, greaterThanOrEqualTo(calm));
    });
  });

  // ─────────────────────────────────────────────
  group('PerceptionBuffer', () {
    late PerceptionBuffer buffer;

    Perception makeP(String input) => Perception(
          id: uuid.v4(),
          rawInput: input,
          modality: PerceptionModality.linguistic,
        );

    setUp(() {
      buffer = PerceptionBuffer(
        capacity: 5,
        retentionDuration: const Duration(seconds: 60),
      );
    });

    test('starts empty', () {
      expect(buffer.hasPending, isFalse);
      expect(buffer.currentSize, 0);
    });

    test('add stores perception', () {
      buffer.add(makeP('hello world'));
      expect(buffer.currentSize, 1);
      expect(buffer.hasPending, isTrue);
    });

    test('drain returns all and clears buffer', () {
      buffer.add(makeP('event 1'));
      buffer.add(makeP('event 2'));
      final drained = buffer.drain();
      expect(drained.length, 2);
      expect(buffer.currentSize, 0);
    });

    test('peek does not remove perceptions', () {
      buffer.add(makeP('peeked'));
      buffer.peek();
      expect(buffer.currentSize, 1);
    });

    test('overflow evicts oldest perception', () {
      for (var i = 0; i < 7; i++) {
        buffer.add(makeP('item $i'));
      }
      expect(buffer.currentSize, lessThanOrEqualTo(5));
      expect(buffer.totalDropped, greaterThan(0));
    });

    test('drainByModality only returns matching modality', () {
      buffer.add(Perception(
        id: uuid.v4(),
        rawInput: 'visual thing',
        modality: PerceptionModality.visual,
      ));
      buffer.add(Perception(
        id: uuid.v4(),
        rawInput: 'audio thing',
        modality: PerceptionModality.auditory,
      ));
      final visual = buffer.drainByModality(PerceptionModality.visual);
      expect(visual.length, 1);
      expect(visual.first.modality, PerceptionModality.visual);
    });

    test('modalityDistribution counts correctly', () {
      buffer.add(Perception(
        id: uuid.v4(),
        rawInput: 'v1',
        modality: PerceptionModality.visual,
      ));
      buffer.add(Perception(
        id: uuid.v4(),
        rawInput: 'v2',
        modality: PerceptionModality.visual,
      ));
      buffer.add(Perception(
        id: uuid.v4(),
        rawInput: 'a1',
        modality: PerceptionModality.auditory,
      ));
      final dist = buffer.modalityDistribution;
      expect(dist[PerceptionModality.visual], 2);
      expect(dist[PerceptionModality.auditory], 1);
    });

    test('clear empties buffer and counts drops', () {
      buffer.add(makeP('x'));
      buffer.add(makeP('y'));
      buffer.clear();
      expect(buffer.currentSize, 0);
    });

    test('addAll bulk loads perceptions', () {
      buffer.addAll([makeP('a'), makeP('b'), makeP('c')]);
      expect(buffer.currentSize, 3);
    });
  });

  // ─────────────────────────────────────────────
  group('SensoryInputProcessor', () {
    late SensoryInputProcessor processor;

    setUp(() {
      processor = SensoryInputProcessor();
    });

    test('process returns a valid Perception', () {
      final p = processor.process(
        'the cat is hungry',
        modality: PerceptionModality.linguistic,
        id: uuid.v4(),
      );
      expect(p, isA<Perception>());
      expect(p.rawInput, 'the cat is hungry');
      expect(p.modality, PerceptionModality.linguistic);
    });

    test('process populates features map', () {
      final p = processor.process(
        'cat is afraid of water',
        modality: PerceptionModality.linguistic,
      );
      expect(p.features, isNotEmpty);
      expect(p.features.containsKey('entities'), isTrue);
    });

    test('extractConcepts returns non-empty list', () {
      final p = processor.process(
        'a big hungry cat on the table',
        modality: PerceptionModality.linguistic,
      );
      final concepts = processor.extractConcepts(p, const Uuid());
      expect(concepts, isNotEmpty);
    });

    test('extractConcepts includes gestalt concept', () {
      final p = processor.process(
        'fire in the building',
        modality: PerceptionModality.visual,
      );
      final concepts = processor.extractConcepts(p, const Uuid());
      // Gestalt concept captures the full input
      final hasGestalt =
          concepts.any((c) => c.properties['source'] == 'gestalt');
      expect(hasGestalt, isTrue);
    });

    test('emotional input produces concept with non-neutral valence', () {
      final p = processor.process(
        'DANGER!! FIRE!! RUN AWAY!!',
        modality: PerceptionModality.linguistic,
      );
      final concepts = processor.extractConcepts(p, const Uuid());
      final gestalt =
          concepts.firstWhere((c) => c.properties['source'] == 'gestalt');
      expect(
        gestalt.emotionalValence,
        anyOf(
          EmotionalValence.negative,
          EmotionalValence.veryNegative,
        ),
      );
    });

    test('processBatch handles multiple inputs', () {
      final concepts = processor.processBatch(
        ['cat on table', 'cat is hungry', 'fish near cat'],
        PerceptionModality.linguistic,
        const Uuid(),
      );
      expect(concepts.length, greaterThan(3));
    });

    test('buffer is populated after processing', () {
      processor.process(
        'hello world',
        modality: PerceptionModality.linguistic,
      );
      expect(processor.buffer.hasPending, isTrue);
    });
  });

  // ─────────────────────────────────────────────
  group('Perception', () {
    test('tokens splits raw input correctly', () {
      final p = Perception(
        id: uuid.v4(),
        rawInput: 'The cat sat on the mat',
        modality: PerceptionModality.linguistic,
      );
      expect(p.tokens, contains('cat'));
      expect(p.tokens, contains('mat'));
    });

    test('confidence must be in [0, 1]', () {
      expect(
        () => Perception(
          id: uuid.v4(),
          rawInput: 'test',
          modality: PerceptionModality.linguistic,
          confidence: 1.5,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
