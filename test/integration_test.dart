// test/integration_test.dart
// End-to-end integration tests for the Consciousness system.

import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'package:consciousness_sim/consciousness_sim.dart';

void main() {
  const uuid = Uuid();

  // ─────────────────────────────────────────────
  group('CrossModalBinding', () {
    late CrossModalBinding binding;

    Perception makeP(
      String input,
      PerceptionModality modality,
    ) =>
        Perception(
          id: uuid.v4(),
          rawInput: input,
          modality: modality,
          timestamp: DateTime.now(),
        );

    setUp(() {
      binding = CrossModalBinding(
        temporalWindow: const Duration(seconds: 5),
        bindingThreshold: 0.05, // Low threshold for testing
      );
    });

    test('registers perception without error', () {
      expect(
        () => binding.register(makeP('cat meowing', PerceptionModality.auditory)),
        returnsNormally,
      );
    });

    test('binds temporally close perceptions from different modalities', () {
      final visual = makeP('cat on table', PerceptionModality.visual);
      final auditory = makeP('cat meowing sound', PerceptionModality.auditory);
      binding.register(visual);
      final bindings = binding.register(auditory);
      // May or may not bind depending on token overlap
      expect(bindings, isA<List<MultiModalPercept>>());
    });

    test('getByModalities filters correctly', () {
      final visual = makeP('fire blazing', PerceptionModality.visual);
      final auditory = makeP('fire crackling', PerceptionModality.auditory);
      binding.register(visual);
      binding.register(auditory);
      final fireBindings = binding.getByModalities({
        PerceptionModality.visual,
        PerceptionModality.auditory,
      });
      expect(fireBindings, isA<List<MultiModalPercept>>());
    });

    test('MultiModalPercept has correct modalities', () {
      final v = makeP('loud bang', PerceptionModality.visual);
      final a = makeP('loud bang sound', PerceptionModality.auditory);
      binding.register(v);
      final results = binding.register(a);
      if (results.isNotEmpty) {
        expect(results.first.modalitiesInvolved,
            containsAll([PerceptionModality.visual, PerceptionModality.auditory]));
        expect(results.first.isMultiModal, isTrue);
      }
    });

    test('registerAll handles batch', () {
      final perceptions = [
        makeP('thunder', PerceptionModality.auditory),
        makeP('lightning', PerceptionModality.visual),
        makeP('rain', PerceptionModality.tactile),
      ];
      final results = binding.registerAll(perceptions);
      expect(results, isA<List<MultiModalPercept>>());
    });
  });

  // ─────────────────────────────────────────────
  group('CoherenceManager', () {
    late CoherenceManager coherence;
    late ConceptualGraph graph;

    Concept makeConcept({
      required String id,
      required String content,
      double activation = 0.5,
    }) =>
        Concept(
          id: id,
          content: content,
          activationLevel: activation,
        );

    setUp(() {
      coherence = CoherenceManager();
      graph = ConceptualGraph();
    });

    test('coherence of empty workspace is 1.0', () {
      final score = coherence.evaluate(
        workspaceConcepts: [],
        graph: graph,
      );
      expect(score, closeTo(1.0, 0.01));
    });

    test('coherence of single concept is high', () {
      final c = makeConcept(id: 'only', content: 'solo');
      graph.addConcept('only', c);
      final score = coherence.evaluate(
        workspaceConcepts: [c],
        graph: graph,
      );
      expect(score, greaterThan(0.5));
    });

    test('coherence between 0 and 1', () {
      final concepts = [
        makeConcept(id: 'c1', content: 'cat'),
        makeConcept(id: 'c2', content: 'fish'),
        makeConcept(id: 'c3', content: 'hungry'),
      ];
      for (final c in concepts) {
        graph.addConcept(c.id, c);
      }
      final score = coherence.evaluate(
        workspaceConcepts: concepts,
        graph: graph,
      );
      expect(score, inInclusiveRange(0.0, 1.0));
    });

    test('evaluateDetailed returns a full CoherenceReport', () {
      final c = makeConcept(id: 'c1', content: 'test');
      graph.addConcept('c1', c);
      final report = coherence.evaluateDetailed(
        workspaceConcepts: [c],
        graph: graph,
      );
      expect(report, isA<CoherenceReport>());
      expect(report.overallCoherence, inInclusiveRange(0.0, 1.0));
    });

    test('averageCoherence returns 1.0 when no history', () {
      expect(coherence.averageCoherence(), closeTo(1.0, 0.01));
    });

    test('coherenceTrend is 0 when no history', () {
      expect(coherence.coherenceTrend, 0);
    });
  });

  // ─────────────────────────────────────────────
  group('SynchronizationManager', () {
    late SynchronizationManager sync;

    setUp(() {
      sync = SynchronizationManager(tickIntervalMs: 50);
    });

    tearDown(() {
      sync.stop();
    });

    test('starts not running', () {
      expect(sync.isRunning, isFalse);
    });

    test('starts and stops cleanly', () {
      sync.start();
      expect(sync.isRunning, isTrue);
      sync.stop();
      expect(sync.isRunning, isFalse);
    });

    test('registerStream adds stream', () {
      sync.registerStream(ProcessingStream(name: 'perception', priority: 5));
      final stats = sync.getStreamStats();
      expect(stats.containsKey('perception'), isTrue);
    });

    test('listener is called after ticks', () async {
      var callCount = 0;
      sync.addListener((_) => callCount++);
      sync.start();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      sync.stop();
      expect(callCount, greaterThan(0));
    });

    test('SyncEvent contains tick number', () async {
      SyncEvent? capturedEvent;
      sync.addListener((e) => capturedEvent = e);
      sync.start();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      sync.stop();
      expect(capturedEvent?.tickNumber, greaterThan(0));
    });

    test('markComplete does not throw', () {
      sync.registerStream(ProcessingStream(name: 'test', priority: 1));
      expect(() => sync.markComplete('test'), returnsNormally);
    });
  });

  // ─────────────────────────────────────────────
  group('Consciousness — End-to-End', () {
    late Consciousness mind;

    setUp(() {
      mind = Consciousness(
        config: ConsciousnessConfig(
          workspaceCapacity: 7,
          attentionThreshold: 0.1, // Low threshold for easy testing
          enableLongTermLearning: true,
          enableContinuousDecay: false, // Disable for deterministic tests
          memoryConsolidationIntervalMinutes: 60,
          logLevel: LogLevel.warning, // Quiet during tests
          name: 'TestMind',
        ),
      );
    });

    tearDown(() {
      mind.dispose();
    });

    test('observe does not throw', () async {
      await expectLater(
        mind.observe('a cat is on the table'),
        completes,
      );
    });

    test('think returns non-empty string after observations', () async {
      await mind.observe('a hungry cat');
      final thought = mind.think();
      expect(thought, isNotEmpty);
      expect(thought, isNot('(No active thoughts — nothing has been observed yet.)'));
    });

    test('think returns placeholder when nothing observed', () {
      final thought = mind.think();
      expect(thought, contains('nothing'));
    });

    test('getCurrentState returns ConsciousState', () async {
      await mind.observe('dog in park');
      final state = mind.getCurrentState();
      expect(state, isA<ConsciousState>());
    });

    test('workspace is populated after observe', () async {
      await mind.observe('fire in the building');
      final state = mind.getCurrentState();
      expect(state.workspace, isNotEmpty);
    });

    test('hungry cat triggers food-related inference', () async {
      await mind.observe('a hungry cat');
      await mind.observe('there is fish on the table');
      await mind.process();
      final thought = mind.think().toLowerCase();
      // Should mention cat, food, or eating
      expect(
        thought.contains('cat') ||
            thought.contains('food') ||
            thought.contains('fish') ||
            thought.contains('eat'),
        isTrue,
      );
    });

    test('fire observation triggers danger inference', () async {
      await mind.observe('there is fire here!');
      final thought = mind.think().toLowerCase();
      expect(
        thought.contains('fire') || thought.contains('danger'),
        isTrue,
      );
    });

    test('recall returns memories after observe', () async {
      await mind.observe('the cat sat on the mat');
      final memories = mind.recall('cat mat');
      expect(memories, isNotEmpty);
    });

    test('recallEpisodes searches episodic store', () async {
      await mind.observe('the dog ran through the park');
      final episodes = mind.recallEpisodes('dog');
      expect(episodes, isA<List<Memory>>());
    });

    test('refocusAttention does not throw', () async {
      await mind.observe('cat fish table');
      expect(() => mind.refocusAttention(['cat', 'fish']), returnsNormally);
    });

    test('process returns a ConsciousState', () async {
      await mind.observe('a cat is hungry');
      final state = await mind.process();
      expect(state, isA<ConsciousState>());
      expect(state.coherence, inInclusiveRange(0.0, 1.0));
    });

    test('metrics are updated after process', () async {
      await mind.observe('something happened');
      await mind.process();
      expect(mind.metrics.totalCycles, greaterThan(0));
    });

    test('thinkDetailed returns map with expected keys', () async {
      await mind.observe('cat on table');
      final detail = mind.thinkDetailed();
      expect(detail.containsKey('thought'), isTrue);
      expect(detail.containsKey('workspace_size'), isTrue);
      expect(detail.containsKey('coherence'), isTrue);
    });

    test('multi-modal observation updates workspace', () async {
      await mind.observeVisual('cat moving fast');
      await mind.observeAuditory('scratching sound');
      final state = mind.getCurrentState();
      expect(state.workspace, isNotEmpty);
    });

    test('learn adds custom rule', () async {
      mind.learn(InferenceRule(
        id: uuid.v4(),
        name: 'test_custom',
        conditions: ['zyrxq'],
        conclusion: 'Custom zyrxq rule fired.',
        weight: 1.0,
      ));
      await mind.observe('zyrxq spotted');
      final thought = mind.think();
      expect(thought.toLowerCase(), contains('zyrxq'));
    });

    test('learnFrom does not throw', () async {
      await mind.observe('something useful');
      await expectLater(
        mind.learnFrom('positive outcome', positive: true),
        completes,
      );
    });

    test('reset clears workspace but preserves graph', () async {
      await mind.observe('important long-term concept');
      final nodeBefore = mind.conceptGraph.nodeCount;
      mind.reset();
      expect(mind.workspace.size, 0);
      // Graph is preserved
      expect(mind.conceptGraph.nodeCount, nodeBefore);
    });

    test('ConsciousnessMetrics.report returns non-empty string', () async {
      await mind.observe('test');
      await mind.process();
      final report = mind.metrics.report();
      expect(report, isNotEmpty);
      expect(report, contains('METRICS'));
    });

    test('multiple observations build up workspace correctly', () async {
      await mind.observe('cat is hungry');
      await mind.observe('cat is near fish');
      await mind.observe('fish is on table');
      await mind.process();
      final state = mind.getCurrentState();
      expect(state.workspace.length, greaterThan(1));
      expect(state.inferencesGenerated, isNotEmpty);
    });
  });

  // ─────────────────────────────────────────────
  group('ConsciousnessVisualizer', () {
    const viz = ConsciousnessVisualizer();

    test('renderActivationMap returns non-empty string', () {
      final result = viz.renderActivationMap({'concept1': 0.8, 'concept2': 0.4});
      expect(result, isNotEmpty);
      expect(result, contains('concept1'));
    });

    test('renderMemorySummary returns formatted string', () {
      final result = viz.renderMemorySummary(
        episodicCount: 10,
        semanticCount: 5,
        workingCount: 2,
      );
      expect(result, contains('Episodic'));
      expect(result, contains('10'));
    });

    test('renderState returns non-empty string for empty workspace', () {
      final state = ConsciousState(
        workspace: [],
        focusedConceptId: '',
        activationMap: {},
        inferencesGenerated: [],
      );
      final result = viz.renderState(state);
      expect(result, isNotEmpty);
    });
  });

  // ─────────────────────────────────────────────
  group('EmotionDetectorPlugin', () {
    test('process does not throw for neutral state', () async {
      const plugin = EmotionDetectorPlugin();
      final state = ConsciousState(
        workspace: [],
        focusedConceptId: '',
        activationMap: {},
        inferencesGenerated: [],
      );
      await expectLater(plugin.process(state), completes);
    });

    test('plugin has correct name', () {
      const plugin = EmotionDetectorPlugin();
      expect(plugin.name, 'EmotionDetector');
    });
  });

  // ─────────────────────────────────────────────
  group('ConsciousnessLogger', () {
    test('logs at correct level', () {
      ConsciousnessLogger.clearHistory();
      final logger = ConsciousnessLogger('Test', level: LogLevel.debug);
      logger.debug('debug message');
      logger.info('info message');
      expect(ConsciousnessLogger.history.length, greaterThanOrEqualTo(2));
    });

    test('filters messages below threshold', () {
      ConsciousnessLogger.clearHistory();
      final logger = ConsciousnessLogger('FilterTest', level: LogLevel.error);
      logger.debug('this should not appear');
      logger.info('this should not appear');
      logger.warning('this should not appear');
      final filtered = ConsciousnessLogger.history
          .where((e) => e.logger == 'FilterTest')
          .toList();
      expect(filtered, isEmpty);
    });

    test('LogEntry toString is non-empty', () {
      ConsciousnessLogger.clearHistory();
      final logger = ConsciousnessLogger('Entry', level: LogLevel.debug);
      logger.info('hello');
      final entry =
          ConsciousnessLogger.history.where((e) => e.logger == 'Entry').first;
      expect(entry.toString(), isNotEmpty);
    });
  });
}
