// lib/core/binding.dart
// Conceptual Binding Engine — weaves separate percepts into unified wholes.
//
// The binding problem (Treisman, 1996; Crick & Koch, 1990) asks how disparate
// neural processes combine into unified conscious experience.  Here we model
// binding as the creation of weighted edges in the concept graph, governed by
// temporal proximity, semantic overlap, and co-activation patterns.

import 'dart:math' as math;

import 'package:consciousness_sim/core/models.dart';
import 'package:consciousness_sim/utils/logger.dart';

// ─────────────────────────────────────────────
// BindingResult
// ─────────────────────────────────────────────

/// The result of a single binding operation between two concepts.
class BindingResult {
  const BindingResult({
    required this.conceptId1,
    required this.conceptId2,
    required this.strength,
    required this.relationshipType,
    required this.label,
    required this.wasReinforced,
  });

  final String conceptId1;
  final String conceptId2;
  final double strength;
  final RelationshipType relationshipType;
  final String label;

  /// True if a pre-existing edge was strengthened rather than created fresh.
  final bool wasReinforced;

  @override
  String toString() =>
      'BindingResult($conceptId1 ↔ $conceptId2, '
      'strength: ${strength.toStringAsFixed(2)}, '
      'type: ${relationshipType.name}, reinforced: $wasReinforced)';
}

// ─────────────────────────────────────────────
// BindingEngine
// ─────────────────────────────────────────────

/// Responsible for creating and reinforcing semantic bindings between concepts.
///
/// ### Binding rules
/// 1. **Temporal binding** — concepts observed within [temporalWindow] of each
///    other receive a [RelationshipType.temporal] link.
/// 2. **Semantic binding** — concepts sharing tokens in their content receive
///    an [RelationshipType.associative] link weighted by Jaccard similarity.
/// 3. **Causal binding** — concepts where one is detected as a cause of
///    another receive a [RelationshipType.causal] link.
/// 4. **Reinforcement** — repeated co-activation strengthens existing links
///    using a Hebbian-style update rule ("fire together → wire together").
class BindingEngine {
  BindingEngine({
    Duration temporalWindow = const Duration(seconds: 30),
    double baseBindingStrength = 0.4,
    double reinforcementRate = 0.1,
    ConsciousnessLogger? logger,
  })  : _temporalWindow = temporalWindow,
        _baseBindingStrength = baseBindingStrength,
        _reinforcementRate = reinforcementRate,
        _logger = logger ?? ConsciousnessLogger('BindingEngine');

  final Duration _temporalWindow;
  final double _baseBindingStrength;
  final double _reinforcementRate;
  final ConsciousnessLogger _logger;

  /// History of recently observed concepts for temporal binding.
  final List<_TimestampedConcept> _recentBuffer = [];

  // ── Public API ─────────────────────────────

  /// Registers a newly observed [concept] and attempts to bind it with
  /// recently observed concepts that are still within the temporal window.
  ///
  /// Returns the list of binding results produced.
  List<BindingResult> registerAndBind(
    Concept concept,
    List<ConceptNode> allNodes,
  ) {
    _pruneExpiredBuffer();

    final results = <BindingResult>[];

    // Attempt temporal & semantic binding with buffered concepts
    for (final recent in _recentBuffer) {
      if (recent.concept.id == concept.id) continue;

      final result = _computeBinding(concept, recent.concept, allNodes);
      if (result != null) results.add(result);
    }

    // Buffer the new concept
    _recentBuffer.add(_TimestampedConcept(
      concept: concept,
      observedAt: DateTime.now(),
    ));

    if (results.isNotEmpty) {
      _logger.info(
          'Binding produced ${results.length} link(s) for "${concept.content}"');
    }
    return results;
  }

  /// Explicitly binds [concept1] to [concept2] with a specified
  /// [relationshipType] and optional [strength].
  ///
  /// If [existingEdge] is non-null it is reinforced rather than replaced.
  BindingResult bindExplicit({
    required Concept concept1,
    required Concept concept2,
    required RelationshipType relationshipType,
    double? strength,
    ConceptEdge? existingEdge,
    String label = '',
  }) {
    if (existingEdge != null) {
      final reinforced = math.min(
        1.0,
        existingEdge.strength + _reinforcementRate,
      );
      _logger.debug(
          'Reinforced binding: ${concept1.id} ↔ ${concept2.id} '
          '(${existingEdge.strength.toStringAsFixed(2)} → '
          '${reinforced.toStringAsFixed(2)})');
      return BindingResult(
        conceptId1: concept1.id,
        conceptId2: concept2.id,
        strength: reinforced,
        relationshipType: relationshipType,
        label: label,
        wasReinforced: true,
      );
    }

    final s = strength ?? _baseBindingStrength;
    _logger.debug(
        'New binding: "${concept1.content}" ↔ "${concept2.content}" '
        '(${relationshipType.name}, ${s.toStringAsFixed(2)})');
    return BindingResult(
      conceptId1: concept1.id,
      conceptId2: concept2.id,
      strength: s,
      relationshipType: relationshipType,
      label: label,
      wasReinforced: false,
    );
  }

  /// Computes all possible bindings within a list of [active] concepts
  /// (e.g. the current workspace) and returns the results.
  List<BindingResult> bindWorkspace(
    List<Concept> active,
    List<ConceptNode> allNodes,
  ) {
    final results = <BindingResult>[];
    for (var i = 0; i < active.length; i++) {
      for (var j = i + 1; j < active.length; j++) {
        final r = _computeBinding(active[i], active[j], allNodes);
        if (r != null) results.add(r);
      }
    }
    return results;
  }

  // ── Private helpers ─────────────────────────

  BindingResult? _computeBinding(
    Concept c1,
    Concept c2,
    List<ConceptNode> allNodes,
  ) {
    // 1. Temporal binding
    final temporalScore = _temporalOverlap(c1, c2);

    // 2. Semantic / token similarity
    final semanticScore = _semanticSimilarity(c1, c2);

    // 3. Causal indicators in text
    final causalScore = _detectCausality(c1.content, c2.content);

    // 4. Combine scores
    final combinedScore =
        (temporalScore * 0.3) + (semanticScore * 0.5) + (causalScore * 0.2);

    if (combinedScore < 0.15) return null; // Below binding threshold

    final type = causalScore > 0.5
        ? RelationshipType.causal
        : temporalScore > semanticScore
            ? RelationshipType.temporal
            : RelationshipType.associative;

    // Check for reinforcement opportunity
    final node1 = allNodes.cast<ConceptNode?>()
        .firstWhere((n) => n?.id == c1.id, orElse: () => null);
    final existing = node1?.edges[c2.id];

    return bindExplicit(
      concept1: c1,
      concept2: c2,
      relationshipType: type,
      strength: combinedScore,
      existingEdge: existing,
      label: _generateLabel(c1, c2, type),
    );
  }

  double _temporalOverlap(Concept c1, Concept c2) {
    final delta = c1.creationTime.difference(c2.creationTime).abs();
    if (delta > _temporalWindow) return 0.0;
    return 1.0 - (delta.inMilliseconds / _temporalWindow.inMilliseconds);
  }

  double _semanticSimilarity(Concept c1, Concept c2) {
    // If embeddings are available use cosine similarity
    if (c1.embedding != null && c2.embedding != null) {
      return c1.embedding!.cosineSimilarity(c2.embedding!);
    }
    // Fall back to Jaccard token similarity
    return _jaccardTokenSimilarity(c1.content, c2.content);
  }

  double _jaccardTokenSimilarity(String s1, String s2) {
    final tokens1 = _tokenise(s1);
    final tokens2 = _tokenise(s2);
    if (tokens1.isEmpty && tokens2.isEmpty) return 1.0;
    if (tokens1.isEmpty || tokens2.isEmpty) return 0.0;
    final intersection = tokens1.intersection(tokens2).length;
    final union = tokens1.union(tokens2).length;
    return intersection / union;
  }

  double _detectCausality(String s1, String s2) {
    // Heuristic: check for causal cue words
    const causalCues = [
      'because', 'therefore', 'since', 'cause', 'result',
      'lead', 'trigger', 'produce', 'effect', 'due to',
      'hungry', 'thirsty', 'fear', 'wants', 'needs',
    ];
    final combined = (s1 + ' ' + s2).toLowerCase();
    var hits = 0;
    for (final cue in causalCues) {
      if (combined.contains(cue)) hits++;
    }
    return math.min(1.0, hits / 3.0);
  }

  Set<String> _tokenise(String text) => text
      .toLowerCase()
      .split(RegExp(r'[\s,;.!?]+'))
      .where((t) => t.length > 2)
      .toSet();

  String _generateLabel(
    Concept c1,
    Concept c2,
    RelationshipType type,
  ) {
    return switch (type) {
      RelationshipType.causal => '${c1.content} causes ${c2.content}',
      RelationshipType.temporal => '${c1.content} before ${c2.content}',
      RelationshipType.associative =>
        '${c1.content} associated with ${c2.content}',
      _ => '${c1.content} → ${c2.content}',
    };
  }

  void _pruneExpiredBuffer() {
    final cutoff = DateTime.now().subtract(_temporalWindow);
    _recentBuffer.removeWhere((e) => e.observedAt.isBefore(cutoff));
  }
}

// ─────────────────────────────────────────────
// Internal helper
// ─────────────────────────────────────────────

class _TimestampedConcept {
  const _TimestampedConcept({
    required this.concept,
    required this.observedAt,
  });

  final Concept concept;
  final DateTime observedAt;
}
