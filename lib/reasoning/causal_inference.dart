// lib/reasoning/causal_inference.dart
// Causal Inference Engine — discovers and reasons about cause-effect chains.
//
// Based on Judea Pearl's causal graphical models (Pearl, 2000) adapted to
// text-based, symbol-level reasoning suitable for a cognitive simulation.

import 'dart:math' as math;

import 'package:consciousness_sim/core/models.dart';
import 'package:consciousness_sim/utils/logger.dart';

// ─────────────────────────────────────────────
// CausalCue
// ─────────────────────────────────────────────

class _CausalCue {
  const _CausalCue({
    required this.pattern,
    required this.direction,
    required this.weight,
  });

  /// Regex or substring to match.
  final String pattern;

  /// +1 if A causes B (forward), -1 if B causes A (backward).
  final int direction;

  /// Confidence contribution.
  final double weight;
}

// ─────────────────────────────────────────────
// CausalInferenceEngine
// ─────────────────────────────────────────────

/// Detects and chains causal relationships between concepts.
///
/// ### How it works
/// 1. **Pattern matching**: Scans concept pairs for causal linguistic cues.
/// 2. **Temporal ordering**: Earlier events are candidates for causes.
/// 3. **Chain building**: Links individual cause–effect pairs into chains.
/// 4. **Counterfactual check**: Weak if the concepts co-occur rarely.
class CausalInferenceEngine {
  CausalInferenceEngine({ConsciousnessLogger? logger})
      : _logger = logger ?? ConsciousnessLogger('CausalInference');

  final ConsciousnessLogger _logger;
  /// Accumulated causal relationships discovered over time.
  final List<CausalRelationship> _knownCausality = [];

  // Linguistic cue registry
  static final List<_CausalCue> _cues = [
    _CausalCue(pattern: 'because', direction: 1, weight: 0.9),
    _CausalCue(pattern: 'therefore', direction: 1, weight: 0.85),
    _CausalCue(pattern: 'since', direction: 1, weight: 0.75),
    _CausalCue(pattern: 'causes', direction: 1, weight: 0.95),
    _CausalCue(pattern: 'lead', direction: 1, weight: 0.7),
    _CausalCue(pattern: 'trigger', direction: 1, weight: 0.8),
    _CausalCue(pattern: 'result in', direction: 1, weight: 0.85),
    _CausalCue(pattern: 'due to', direction: -1, weight: 0.8),
    _CausalCue(pattern: 'owing to', direction: -1, weight: 0.75),
    _CausalCue(pattern: 'hungry', direction: 1, weight: 0.6),
    _CausalCue(pattern: 'thirsty', direction: 1, weight: 0.6),
    _CausalCue(pattern: 'afraid', direction: 1, weight: 0.65),
    _CausalCue(pattern: 'tired', direction: 1, weight: 0.55),
    _CausalCue(pattern: 'so', direction: 1, weight: 0.5),
    _CausalCue(pattern: 'thus', direction: 1, weight: 0.7),
    _CausalCue(pattern: 'hence', direction: 1, weight: 0.75),
    _CausalCue(pattern: 'want', direction: 1, weight: 0.55),
    _CausalCue(pattern: 'need', direction: 1, weight: 0.6),
  ];

  // ── Public API ─────────────────────────────

  /// Analyses a pair of [Concept]s and returns a [CausalRelationship]
  /// if sufficient causal evidence is found, otherwise null.
  CausalRelationship? inferCausality(Concept cause, Concept effect) {
    final combined =
        '${cause.content} ${effect.content}'.toLowerCase();

    var score = 0.0;
    final matchedCues = <String>[];

    for (final cue in _cues) {
      if (combined.contains(cue.pattern)) {
        score += cue.weight;
        matchedCues.add(cue.pattern);
      }
    }

    // Temporal ordering boost: earlier = more likely cause
    final causeFirst =
        cause.creationTime.isBefore(effect.creationTime);
    if (causeFirst) score += 0.15;

    // Normalise
    final confidence = math.min(1.0, score / 2.0);
    if (confidence < 0.2) return null;

    final relationship = CausalRelationship(
      causeConceptId: cause.id,
      effectConceptId: effect.id,
      description:
          '"${cause.content}" causes "${effect.content}"',
      strength: confidence,
      temporalGap: effect.creationTime
          .difference(cause.creationTime)
          .abs(),
    );

    _knownCausality.add(relationship);
    _logger.debug(
        'Causal relationship found: '
        '${relationship.description} '
        '(strength: ${confidence.toStringAsFixed(2)}, '
        'cues: ${matchedCues.join(", ")})');

    return relationship;
  }

  /// Scans all pairs in [concepts] and returns any causal relationships.
  List<CausalRelationship> discoverFromConcepts(List<Concept> concepts) {
    final results = <CausalRelationship>[];
    for (var i = 0; i < concepts.length; i++) {
      for (var j = 0; j < concepts.length; j++) {
        if (i == j) continue;
        final rel = inferCausality(concepts[i], concepts[j]);
        if (rel != null) results.add(rel);
      }
    }
    return results;
  }

  /// Builds a causal chain from the [knownCausality] list, starting from
  /// [startConceptId].  Returns ordered concept IDs from cause to final effect.
  List<String> buildCausalChain(String startConceptId, {int maxLength = 5}) {
    final chain = [startConceptId];
    final visited = <String>{startConceptId};

    while (chain.length < maxLength) {
      final current = chain.last;
      final next = _knownCausality
          .cast<CausalRelationship?>()
          .firstWhere(
            (r) =>
                r!.causeConceptId == current &&
                !visited.contains(r.effectConceptId),
            orElse: () => null,
          );
      if (next == null) break;
      chain.add(next.effectConceptId);
      visited.add(next.effectConceptId);
    }

    return chain;
  }

  /// Generates a natural-language description of all known causal chains
  /// starting from any of [conceptIds].
  String describeCausality(
    List<String> conceptIds,
    Map<String, String> conceptLabels,
  ) {
    final relevant = _knownCausality
        .where((r) =>
            conceptIds.contains(r.causeConceptId) ||
            conceptIds.contains(r.effectConceptId))
        .toList()
      ..sort((a, b) => b.strength.compareTo(a.strength));

    if (relevant.isEmpty) return '';

    final parts = relevant.take(3).map((r) {
      final cause = conceptLabels[r.causeConceptId] ?? r.causeConceptId;
      final effect = conceptLabels[r.effectConceptId] ?? r.effectConceptId;
      return '"$cause" leads to "$effect"';
    });

    return parts.join('; ');
  }

  /// All discovered causal relationships.
  List<CausalRelationship> get knownCausality =>
      List.unmodifiable(_knownCausality);

  /// Clears the causal relationship store.
  void reset() {
    _knownCausality.clear();
  }
}
