// test/memory_test.dart
// Unit tests for the memory subsystems.

import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'package:consciousness_sim/consciousness_sim.dart';

void main() {
  const uuid = Uuid();

  Perception makePercept({String input = 'test input'}) => Perception(
        id: uuid.v4(),
        rawInput: input,
        modality: PerceptionModality.linguistic,
      );

  Memory makeMemory({
    String content = 'test content',
    MemoryType type = MemoryType.episodic,
    double strength = 0.8,
    List<String>? associatedConceptIds,
  }) =>
      Memory(
        id: uuid.v4(),
        content: content,
        type: type,
        strength: strength,
        associatedConceptIds: associatedConceptIds ?? [],
      );

  // ─────────────────────────────────────────────
  group('EpisodicMemory', () {
    late EpisodicMemory episodic;

    setUp(() {
      episodic = EpisodicMemory(capacity: 10);
    });

    test('starts empty', () {
      expect(episodic.count, 0);
    });

    test('stores a perception as memory', () {
      final p = makePercept(input: 'cat on table');
      episodic.store(p);
      expect(episodic.count, 1);
    });

    test('search returns relevant memories', () {
      episodic.store(makePercept(input: 'cat is hungry'));
      episodic.store(makePercept(input: 'dog is running'));
      final results = episodic.search('cat hungry');
      expect(results, isNotEmpty);
      expect(results.first.content.toLowerCase(), contains('cat'));
    });

    test('search returns empty for unrelated query', () {
      episodic.store(makePercept(input: 'cat on table'));
      final results = episodic.search('spaceship moon');
      expect(results, isEmpty);
    });

    test('getMostRecent returns correct count', () {
      for (var i = 0; i < 5; i++) {
        episodic.store(makePercept(input: 'event $i'));
      }
      expect(episodic.getMostRecent(3).length, 3);
    });

    test('capacity enforcement: oldest evicted when full', () {
      final smallMemory = EpisodicMemory(capacity: 3);
      for (var i = 0; i < 5; i++) {
        smallMemory.store(makePercept(input: 'event $i'));
      }
      expect(smallMemory.count, lessThanOrEqualTo(3));
    });

    test('applyDecay does not drop fresh memories', () {
      episodic.store(makePercept(input: 'fresh event'));
      episodic.applyDecay(halfLifeHours: 1000.0);
      expect(episodic.count, 1); // Still there with long half-life
    });

    test('getStrongestMemories returns sorted by strength', () {
      episodic.storeMemory(makeMemory(content: 'weak', strength: 0.2));
      episodic.storeMemory(makeMemory(content: 'strong', strength: 0.9));
      final top = episodic.getStrongestMemories(2);
      expect(top.first.strength, greaterThanOrEqualTo(top.last.strength));
    });

    test('forget removes specific memory', () {
      final m = makeMemory(content: 'to forget');
      episodic.storeMemory(m);
      expect(episodic.count, 1);
      episodic.forget(m.id);
      expect(episodic.count, 0);
    });

    test('retrieveByConceptIds finds associated memories', () {
      final cid = uuid.v4();
      episodic.storeMemory(
        makeMemory(content: 'event with concept', associatedConceptIds: [cid]),
      );
      final results = episodic.retrieveByConceptIds([cid]);
      expect(results, isNotEmpty);
    });
  });

  // ─────────────────────────────────────────────
  group('SemanticMemory', () {
    late SemanticMemory semantic;

    setUp(() {
      semantic = SemanticMemory();
    });

    test('starts empty', () {
      expect(semantic.count, 0);
    });

    test('storeFact adds a new fact', () {
      semantic.storeFact(
        subject: 'cat',
        predicate: 'eats',
        object: 'fish',
        confidence: 0.8,
      );
      expect(semantic.count, 1);
    });

    test('storeFact reinforces duplicate facts', () {
      semantic.storeFact(
        subject: 'cat',
        predicate: 'eats',
        object: 'fish',
        confidence: 0.5,
      );
      final fact1 = semantic.storeFact(
        subject: 'cat',
        predicate: 'eats',
        object: 'fish',
        confidence: 0.5,
      );
      expect(semantic.count, 1); // Still one fact
      expect(fact1.occurrences, greaterThan(1));
    });

    test('factsAbout retrieves by subject', () {
      semantic.storeFact(
        subject: 'dog',
        predicate: 'barks',
        object: 'loudly',
        confidence: 0.9,
      );
      semantic.storeFact(
        subject: 'cat',
        predicate: 'meows',
        object: 'softly',
        confidence: 0.85,
      );
      final dogFacts = semantic.factsAbout('dog');
      expect(dogFacts.length, 1);
      expect(dogFacts.first.subject, 'dog');
    });

    test('search returns relevant results', () {
      semantic.storeFact(
        subject: 'fire',
        predicate: 'is',
        object: 'hot',
        confidence: 0.99,
      );
      final results = semantic.search('fire hot');
      expect(results, isNotEmpty);
    });

    test('getHighConfidenceFacts filters correctly', () {
      semantic.storeFact(
          subject: 'sky', predicate: 'is', object: 'blue', confidence: 0.95);
      semantic.storeFact(
          subject: 'maybe', predicate: 'is', object: 'perhaps', confidence: 0.3);
      final high = semantic.getHighConfidenceFacts(minConfidence: 0.7);
      expect(high.length, 1);
      expect(high.first.confidence, greaterThanOrEqualTo(0.7));
    });

    test('generaliseFromEpisodes creates semantic facts', () {
      final memories = [
        makeMemory(content: 'cats eat fish'),
        makeMemory(content: 'cats eat fish'),
        makeMemory(content: 'cats eat fish'),
      ];
      semantic.generaliseFromEpisodes(memories);
      expect(semantic.count, greaterThan(0));
    });

    test('forget removes fact', () {
      final fact = semantic.storeFact(
        subject: 'test',
        predicate: 'is',
        object: 'temporary',
        confidence: 0.5,
      );
      semantic.forget(fact.id);
      expect(semantic.factsAbout('test'), isEmpty);
    });
  });

  // ─────────────────────────────────────────────
  group('WorkingMemory', () {
    late WorkingMemory working;

    setUp(() {
      working = WorkingMemory(capacity: 3);
    });

    test('starts empty', () {
      expect(working.isEmpty, isTrue);
    });

    test('push adds item', () {
      working.push(makeMemory(content: 'active task'));
      expect(working.size, 1);
    });

    test('push displaces oldest when full', () {
      working.push(makeMemory(content: 'item 1'));
      working.push(makeMemory(content: 'item 2'));
      working.push(makeMemory(content: 'item 3'));
      working.push(makeMemory(content: 'item 4')); // Should displace item 1
      expect(working.size, 3);
    });

    test('peek returns most recent without removing', () {
      working.push(makeMemory(content: 'first'));
      working.push(makeMemory(content: 'second'));
      expect(working.peek()?.content, 'second');
      expect(working.size, 2);
    });

    test('pop removes most recent', () {
      working.push(makeMemory(content: 'first'));
      working.push(makeMemory(content: 'second'));
      final popped = working.pop();
      expect(popped?.content, 'second');
      expect(working.size, 1);
    });

    test('search finds items by token', () {
      working.push(makeMemory(content: 'the cat is hungry'));
      working.push(makeMemory(content: 'it is raining outside'));
      final results = working.search('cat hungry');
      expect(results, isNotEmpty);
    });

    test('clear empties the buffer', () {
      working.push(makeMemory(content: 'something'));
      working.clear();
      expect(working.isEmpty, isTrue);
    });
  });

  // ─────────────────────────────────────────────
  group('MemoryManager', () {
    late MemoryManager manager;

    setUp(() {
      manager = MemoryManager(
        enableLongTermLearning: true,
        workingCapacity: 4,
      );
    });

    test('initial stats are all zero', () {
      final stats = manager.getStats();
      expect(stats['episodic'], 0);
      expect(stats['semantic'], 0);
      expect(stats['working'], 0);
    });

    test('storeEpisode adds to episodic memory', () {
      final percept =
          makePercept(input: 'a big dog in the park');
      manager.storeEpisode(percept);
      expect(manager.episodic.count, 1);
    });

    test('retrieveByContext returns results from episodic', () {
      final percept = makePercept(input: 'cat is on the mat');
      manager.storeEpisode(percept);
      final results = manager.retrieveByContext('cat mat');
      expect(results, isNotEmpty);
    });

    test('reinforceAssociation updates association strength', () {
      manager.reinforceAssociation('cat', 'food', strength: 0.3);
      expect(manager.getAssociation('cat', 'food'), closeTo(0.3, 0.01));
    });

    test('reinforceAssociation accumulates correctly', () {
      manager.reinforceAssociation('dog', 'park', strength: 0.2);
      manager.reinforceAssociation('dog', 'park', strength: 0.2);
      expect(manager.getAssociation('dog', 'park'), closeTo(0.4, 0.01));
    });

    test('computeContextualRelevance returns baseline for unknown content', () {
      final relevance = manager.computeContextualRelevance('totally unknown xyz');
      expect(relevance, greaterThan(0.0));
      expect(relevance, lessThanOrEqualTo(1.0));
    });

    test('consolidateMemories runs without error', () async {
      manager.storeEpisode(makePercept(input: 'event to consolidate'));
      await expectLater(
        manager.consolidateMemories(),
        completes,
      );
    });

    test('storeRawEpisode with associatedConceptIds stores correctly', () {
      final cid = uuid.v4();
      manager.storeRawEpisode(
        'important event',
        associatedConceptIds: [cid],
        strength: 0.9,
      );
      final byContext = manager.retrieveByContext('important');
      expect(byContext, isNotEmpty);
    });
  });
}
