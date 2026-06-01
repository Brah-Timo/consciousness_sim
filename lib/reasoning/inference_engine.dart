// lib/reasoning/inference_engine.dart
// InferenceEngine — the core reasoning module.
//
// Combines:
//   • Rule-based forward chaining
//   • Graph-based relationship traversal
//   • Causal inference
//   • Pattern-driven prediction
//   • Natural-language thought synthesis

import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import 'package:consciousness_sim/core/models.dart';
import 'package:consciousness_sim/memory/memory_manager.dart';
import 'package:consciousness_sim/reasoning/causal_inference.dart';
import 'package:consciousness_sim/reasoning/conceptual_graph.dart';
import 'package:consciousness_sim/reasoning/pattern_recognizer.dart';
import 'package:consciousness_sim/utils/logger.dart';

// ─────────────────────────────────────────────
// InferenceEngine
// ─────────────────────────────────────────────

/// Derives new conclusions from active workspace concepts.
///
/// ### Inference types
/// 1. **Rule-based**: Forward chaining using [InferenceRule] instances.
/// 2. **Associative**: Concepts related in the graph trigger each other.
/// 3. **Causal**: Temporal + linguistic cues drive cause-effect inferences.
/// 4. **Pattern-based**: Recurring patterns predict the next concept.
/// 5. **Memory-driven**: Similar past memories suggest current context.
class InferenceEngine {
  InferenceEngine({
    required ConceptualGraph graph,
    required MemoryManager memory,
    ConsciousnessLogger? logger,
  })  : _graph = graph,
        _memory = memory,
        _logger = logger ?? ConsciousnessLogger('InferenceEngine'),
        _causal = CausalInferenceEngine(logger: logger),
        _patterns = PatternRecognizer(logger: logger) {
    _loadBuiltInRules();
  }

  final ConceptualGraph _graph;
  final MemoryManager _memory;
  final ConsciousnessLogger _logger;
  final CausalInferenceEngine _causal;
  final PatternRecognizer _patterns;
  final _uuid = const Uuid();

  final List<InferenceRule> _rules = [];

  // ── Rule management ────────────────────────

  /// Adds a custom [InferenceRule] to the engine.
  void addRule(InferenceRule rule) {
    _rules.add(rule);
    _logger.debug('Rule added: "${rule.name}"');
  }

  /// Removes a rule by its [ruleId].
  void removeRule(String ruleId) {
    _rules.removeWhere((r) => r.id == ruleId);
  }

  // ── Main inference cycle ───────────────────

  /// Runs a complete inference cycle over [activeConcepts].
  ///
  /// Returns all [Inference] objects produced, sorted by confidence.
  List<Inference> runInferenceCycle(List<Concept> activeConcepts) {
    if (activeConcepts.isEmpty) return [];

    _patterns.observeBatch(activeConcepts);

    final inferences = <Inference>[];

    // 1. Rule-based forward chaining
    inferences.addAll(_forwardChain(activeConcepts));

    // 2. Causal inference from concept pairs
    final causalRels = _causal.discoverFromConcepts(activeConcepts);
    for (final rel in causalRels) {
      final cause = activeConcepts.cast<Concept?>()
          .firstWhere((c) => c?.id == rel.causeConceptId, orElse: () => null);
      final effect = activeConcepts.cast<Concept?>()
          .firstWhere((c) => c?.id == rel.effectConceptId, orElse: () => null);
      if (cause != null && effect != null) {
        inferences.add(Inference(
          id: _uuid.v4(),
          conclusion:
              '"${cause.content}" leads to "${effect.content}"',
          premises: [cause.content, effect.content],
          confidence: rel.strength,
          inferenceType: 'causal',
          generatedAt: DateTime.now(),
        ));
      }
    }

    // 3. Graph-based associative inference
    inferences.addAll(_associativeInference(activeConcepts));

    // 4. Memory-driven inference
    inferences.addAll(_memoryDrivenInference(activeConcepts));

    // De-duplicate and sort
    final unique = _deduplicateInferences(inferences);
    unique.sort((a, b) => b.confidence.compareTo(a.confidence));

    _logger.debug(
        'Inference cycle: ${unique.length} unique inference(s) '
        'from ${activeConcepts.length} concepts');

    return unique;
  }

  // ── Thought synthesis ──────────────────────

  /// Synthesises a coherent natural-language thought from [active] concepts.
  ///
  /// Called when no inference rule fires — falls back to a descriptive
  /// combination of the most salient concepts.
  String synthesiseThought(List<Concept> active) {
    if (active.isEmpty) return '(Nothing is currently in focus.)';

    final sorted = List.of(active)
      ..sort((a, b) =>
          b.calculateSalience().compareTo(a.calculateSalience()));

    final primary = sorted.first;
    final secondary = sorted.length > 1 ? sorted[1] : null;
    final tertiary = sorted.length > 2 ? sorted[2] : null;

    // Check if the primary concept implies wanting something
    final wantsPattern = RegExp(
        r'\b(hungry|thirsty|tired|cold|hot|want|need|desire)\b',
        caseSensitive: false);
    final hasWant = wantsPattern.hasMatch(primary.content) ||
        (secondary != null && wantsPattern.hasMatch(secondary.content));

    // Check for spatial relationship
    final spatialPattern = RegExp(
        r'\b(on|above|below|near|beside|next to|over|under)\b',
        caseSensitive: false);
    final hasSpatial = spatialPattern.hasMatch(primary.content);

    // Check causal cues
    final causalChain = _causal.buildCausalChain(primary.id);

    if (causalChain.length > 1) {
      final labels = {
        for (final n in _graph.getAllNodes())
          n.id: n.concept.content,
      };
      final chainDesc =
          _causal.describeCausality(causalChain, labels);
      if (chainDesc.isNotEmpty) return chainDesc;
    }

    if (hasWant && secondary != null) {
      return '${_capitalise(primary.content)} wants '
          '${secondary.content}.';
    }

    if (hasSpatial && secondary != null) {
      return '${_capitalise(primary.content)} and '
          '${secondary.content} are spatially related.';
    }

    if (secondary != null && tertiary != null) {
      return '${_capitalise(primary.content)} involves '
          '${secondary.content} and ${tertiary.content}.';
    }

    if (secondary != null) {
      return '${_capitalise(primary.content)} is connected '
          'to ${secondary.content}.';
    }

    return _capitalise(primary.content) + '.';
  }

  /// Returns all built-in rules (useful for inspection/debugging).
  List<InferenceRule> get allRules => List.unmodifiable(_rules);

  /// Returns the pattern recognizer (for external inspection).
  PatternRecognizer get patternRecognizer => _patterns;

  /// Returns the causal engine (for external inspection).
  CausalInferenceEngine get causalEngine => _causal;

  // ── Private: forward chaining ──────────────

  List<Inference> _forwardChain(List<Concept> active) {
    final results = <Inference>[];
    final tokens = active
        .expand((c) => c.content.toLowerCase().split(RegExp(r'\s+')))
        .toSet();

    for (final rule in _rules) {
      if (!rule.matches(tokens)) continue;

      // Compute confidence from how many conditions fully match
      final matchCount = rule.conditions
          .where((cond) => tokens.any(
                (t) => t.contains(cond.toLowerCase()),
              ))
          .length;
      final confidence =
          (matchCount / rule.conditions.length) * rule.weight;

      if (confidence < 0.3) continue;

      results.add(Inference(
        id: _uuid.v4(),
        conclusion: rule.conclusion,
        premises: rule.conditions,
        confidence: confidence,
        inferenceType: 'rule:${rule.name}',
        generatedAt: DateTime.now(),
      ));

      _logger.debug(
          'Rule fired: "${rule.name}" → "${rule.conclusion}" '
          '(conf: ${confidence.toStringAsFixed(2)})');
    }

    return results;
  }

  // ── Private: associative inference ─────────

  List<Inference> _associativeInference(List<Concept> active) {
    final results = <Inference>[];

    for (final concept in active) {
      final related = _graph.findRelatedConcepts(concept.id, 2);
      if (related.isEmpty) continue;

      final top = related.first;
      // Only infer if the related concept is NOT already in workspace
      if (active.any((c) => c.id == top.id)) continue;

      final confidence = top.concept.activationLevel *
          concept.activationLevel *
          0.6; // Associative confidence is inherently weaker

      if (confidence < 0.2) continue;

      results.add(Inference(
        id: _uuid.v4(),
        conclusion:
            '"${concept.content}" implies "${top.concept.content}"',
        premises: [concept.content],
        confidence: confidence,
        inferenceType: 'associative',
        generatedAt: DateTime.now(),
      ));
    }

    return results;
  }

  // ── Private: memory-driven inference ───────

  List<Inference> _memoryDrivenInference(List<Concept> active) {
    final results = <Inference>[];
    if (active.isEmpty) return results;

    // Use the most salient concept as the query
    final query = active
        .reduce((a, b) =>
            a.calculateSalience() >= b.calculateSalience() ? a : b)
        .content;

    final memories = _memory.retrieveByContext(query, maxResults: 3);
    for (final mem in memories) {
      if (mem.strength < 0.4) continue;

      results.add(Inference(
        id: _uuid.v4(),
        conclusion:
            'Based on memory: "${_trunc(mem.content, 80)}"',
        premises: [query],
        confidence: mem.strength * 0.5,
        inferenceType: 'memory',
        generatedAt: DateTime.now(),
      ));
    }

    return results;
  }

  // ── Private: deduplication ─────────────────

  List<Inference> _deduplicateInferences(List<Inference> inferences) {
    final seen = <String>{};
    return inferences.where((i) {
      final key = i.conclusion.toLowerCase().substring(
            0,
            math.min(40, i.conclusion.length),
          );
      return seen.add(key);
    }).toList();
  }

  // ── Built-in rule library ──────────────────

  void _loadBuiltInRules() {
    final rules = [
      // Animal hunger rules
      InferenceRule(
        id: _uuid.v4(),
        name: 'hungry_animal_seeks_food',
        conditions: ['hungry', 'cat'],
        conclusion: 'The cat is looking for food.',
        weight: 0.9,
      ),
      InferenceRule(
        id: _uuid.v4(),
        name: 'animal_on_table_has_food',
        conditions: ['on', 'table', 'hungry'],
        conclusion: 'The animal on the table may want food there.',
        weight: 0.85,
      ),
      InferenceRule(
        id: _uuid.v4(),
        name: 'hungry_near_food',
        conditions: ['hungry', 'food'],
        conclusion: 'The hungry entity will try to eat the food.',
        weight: 0.95,
      ),
      InferenceRule(
        id: _uuid.v4(),
        name: 'cold_seeks_warmth',
        conditions: ['cold'],
        conclusion: 'The cold entity is seeking warmth.',
        weight: 0.8,
      ),
      InferenceRule(
        id: _uuid.v4(),
        name: 'danger_triggers_flee',
        conditions: ['danger'],
        conclusion: 'The entity is in danger and should seek safety.',
        weight: 0.95,
      ),
      InferenceRule(
        id: _uuid.v4(),
        name: 'fire_is_dangerous',
        conditions: ['fire'],
        conclusion: 'Fire is detected — this is dangerous!',
        weight: 1.0,
      ),
      InferenceRule(
        id: _uuid.v4(),
        name: 'rain_outdoor_seeking_shelter',
        conditions: ['rain', 'outside'],
        conclusion: 'It is raining outside — shelter should be sought.',
        weight: 0.8,
      ),
      InferenceRule(
        id: _uuid.v4(),
        name: 'thirsty_seeks_water',
        conditions: ['thirsty'],
        conclusion: 'The thirsty entity is looking for water.',
        weight: 0.9,
      ),
      InferenceRule(
        id: _uuid.v4(),
        name: 'happy_positive_outcome',
        conditions: ['happy'],
        conclusion: 'A positive emotional state has been detected.',
        weight: 0.7,
      ),
      InferenceRule(
        id: _uuid.v4(),
        name: 'tired_needs_rest',
        conditions: ['tired'],
        conclusion: 'The entity needs rest.',
        weight: 0.85,
      ),
      InferenceRule(
        id: _uuid.v4(),
        name: 'cat_fish_eating',
        conditions: ['cat', 'fish'],
        conclusion: 'The cat will likely try to eat the fish.',
        weight: 0.9,
      ),
      InferenceRule(
        id: _uuid.v4(),
        name: 'loud_sound_alert',
        conditions: ['loud', 'sound'],
        conclusion: 'A loud sound has been detected — attention required.',
        weight: 0.85,
      ),
      InferenceRule(
        id: _uuid.v4(),
        name: 'door_sound_visitor',
        conditions: ['door', 'sound'],
        conclusion: 'There may be a visitor at the door.',
        weight: 0.7,
      ),
      InferenceRule(
        id: _uuid.v4(),
        name: 'rain_wet_shelter',
        conditions: ['rain', 'wet'],
        conclusion: 'Rain is causing wetness — shelter is needed.',
        weight: 0.8,
      ),
      InferenceRule(
        id: _uuid.v4(),
        name: 'robot_obstacle_avoid',
        conditions: ['obstacle', 'moving'],
        conclusion: 'An obstacle is detected ahead — navigation adjustment needed.',
        weight: 0.9,
      ),
    ];

    _rules.addAll(rules);
    _logger.debug('Loaded ${_rules.length} built-in inference rules');
  }

  String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  String _trunc(String s, [int n = 60]) =>
      s.length > n ? '${s.substring(0, n - 3)}...' : s;
}
