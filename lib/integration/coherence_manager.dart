// lib/integration/coherence_manager.dart
// CoherenceManager — evaluates and enforces internal consistency.
//
// Inspired by Global Workspace coherence models (Dehaene, 2014):
// a "coherent" workspace is one where all active concepts mutually
// reinforce each other rather than conflict.  Low coherence → confusion /
// fragmented attention.  High coherence → focused, consistent thought.

import 'dart:math' as math;

import 'package:consciousness_sim/core/models.dart';
import 'package:consciousness_sim/reasoning/conceptual_graph.dart';
import 'package:consciousness_sim/utils/logger.dart';

// ─────────────────────────────────────────────
// CoherenceReport
// ─────────────────────────────────────────────

/// Detailed breakdown of a coherence evaluation.
class CoherenceReport {
  const CoherenceReport({
    required this.overallCoherence,
    required this.semanticCoherence,
    required this.temporalCoherence,
    required this.activationCoherence,
    required this.conflictingPairs,
    required this.dominantTheme,
    required this.timestamp,
  });

  /// Overall coherence score (0.0 = chaos, 1.0 = perfect unity).
  final double overallCoherence;

  /// How well concepts are semantically related to each other.
  final double semanticCoherence;

  /// How temporally clustered recent concepts are.
  final double temporalCoherence;

  /// How similar activation levels are across the workspace.
  final double activationCoherence;

  /// Concept pairs that may be in conflict.
  final List<String> conflictingPairs;

  /// The concept that best unifies the workspace theme.
  final String? dominantTheme;
  final DateTime timestamp;

  bool get isHighCoherence => overallCoherence >= 0.7;
  bool get isLowCoherence => overallCoherence < 0.3;

  @override
  String toString() =>
      'CoherenceReport(overall: ${(overallCoherence * 100).toStringAsFixed(1)}%, '
      'semantic: ${(semanticCoherence * 100).toStringAsFixed(1)}%, '
      'temporal: ${(temporalCoherence * 100).toStringAsFixed(1)}%, '
      'theme: "$dominantTheme")';
}

// ─────────────────────────────────────────────
// CoherenceManager
// ─────────────────────────────────────────────

/// Evaluates the internal consistency of the global workspace and
/// produces [CoherenceReport] objects to guide attention management.
class CoherenceManager {
  CoherenceManager({ConsciousnessLogger? logger})
      : _logger = logger ?? ConsciousnessLogger('CoherenceManager');

  final ConsciousnessLogger _logger;

  /// History of coherence scores (most recent last).
  final List<double> _coherenceHistory = [];

  // ── Public API ─────────────────────────────

  /// Computes the overall coherence of [workspaceConcepts] given the [graph].
  ///
  /// Returns a scalar in [0, 1] suitable for [ConsciousState.coherence].
  double evaluate({
    required List<Concept> workspaceConcepts,
    required ConceptualGraph graph,
  }) {
    if (workspaceConcepts.isEmpty) return 1.0;
    if (workspaceConcepts.length == 1) return 0.9;

    final report = evaluateDetailed(
      workspaceConcepts: workspaceConcepts,
      graph: graph,
    );

    _coherenceHistory.add(report.overallCoherence);
    if (_coherenceHistory.length > 100) _coherenceHistory.removeAt(0);

    return report.overallCoherence;
  }

  /// Produces a full [CoherenceReport] for diagnostic purposes.
  CoherenceReport evaluateDetailed({
    required List<Concept> workspaceConcepts,
    required ConceptualGraph graph,
  }) {
    final semantic = _computeSemanticCoherence(workspaceConcepts, graph);
    final temporal = _computeTemporalCoherence(workspaceConcepts);
    final activation = _computeActivationCoherence(workspaceConcepts);
    final conflicts = _detectConflicts(workspaceConcepts);

    final overall = (semantic * 0.45) +
        (temporal * 0.25) +
        (activation * 0.20) +
        (conflicts.isEmpty ? 0.10 : 0.0);

    final theme = _findDominantTheme(workspaceConcepts, graph);

    final report = CoherenceReport(
      overallCoherence: overall.clamp(0.0, 1.0),
      semanticCoherence: semantic,
      temporalCoherence: temporal,
      activationCoherence: activation,
      conflictingPairs: conflicts,
      dominantTheme: theme,
      timestamp: DateTime.now(),
    );

    if (report.isLowCoherence) {
      _logger.warning(
          'Low coherence detected: ${(overall * 100).toStringAsFixed(1)}% '
          '(${workspaceConcepts.length} concepts)');
    }

    return report;
  }

  /// Running average coherence over the last [n] cycles.
  double averageCoherence({int n = 10}) {
    if (_coherenceHistory.isEmpty) return 1.0;
    final samples = _coherenceHistory.reversed.take(n).toList();
    return samples.reduce((a, b) => a + b) / samples.length;
  }

  /// Whether coherence is trending up (+1), down (-1), or stable (0).
  int get coherenceTrend {
    if (_coherenceHistory.length < 5) return 0;
    final recent = _coherenceHistory.last;
    final prev = _coherenceHistory[_coherenceHistory.length - 5];
    if (recent - prev > 0.05) return 1;
    if (prev - recent > 0.05) return -1;
    return 0;
  }

  // ── Private computation ────────────────────

  double _computeSemanticCoherence(
    List<Concept> concepts,
    ConceptualGraph graph,
  ) {
    if (concepts.length < 2) return 1.0;

    var connectedPairs = 0;
    var totalPairs = 0;

    for (var i = 0; i < concepts.length; i++) {
      for (var j = i + 1; j < concepts.length; j++) {
        totalPairs++;
        final nodeA = graph.getNode(concepts[i].id);
        final nodeB = graph.getNode(concepts[j].id);

        if (nodeA == null || nodeB == null) continue;

        // Check if directly or indirectly connected (depth 2)
        final related = graph
            .findRelatedConcepts(concepts[i].id, 2)
            .map((n) => n.id)
            .toSet();

        if (related.contains(concepts[j].id) ||
            nodeA.edges.containsKey(concepts[j].id)) {
          connectedPairs++;
        }
      }
    }

    return totalPairs == 0 ? 0.5 : connectedPairs / totalPairs;
  }

  double _computeTemporalCoherence(List<Concept> concepts) {
    if (concepts.length < 2) return 1.0;

    final timestamps = concepts.map((c) => c.creationTime).toList()..sort();
    final first = timestamps.first;
    final last = timestamps.last;

    final spread = last.difference(first).inMilliseconds.toDouble();
    if (spread <= 0) return 1.0;

    // Tighter temporal clustering = higher coherence
    // We consider a 60-second window as "coherent"
    const coherentWindow = 60000.0; // 60 seconds in ms
    return math.exp(-spread / coherentWindow).clamp(0.0, 1.0);
  }

  double _computeActivationCoherence(List<Concept> concepts) {
    if (concepts.length < 2) return 1.0;

    final levels = concepts.map((c) => c.activationLevel).toList();
    final mean = levels.reduce((a, b) => a + b) / levels.length;
    final variance =
        levels.map((l) => math.pow(l - mean, 2)).reduce((a, b) => a + b) /
            levels.length;
    final stdDev = math.sqrt(variance);

    // Low standard deviation = similar activation = higher coherence
    return math.max(0.0, 1.0 - stdDev * 2);
  }

  List<String> _detectConflicts(List<Concept> concepts) {
    final conflicts = <String>[];

    // Simple heuristic: opposite emotional valences are conflicting
    for (var i = 0; i < concepts.length; i++) {
      for (var j = i + 1; j < concepts.length; j++) {
        final a = concepts[i].emotionalValence;
        final b = concepts[j].emotionalValence;

        final isOpposite = (a == EmotionalValence.veryPositive &&
                (b == EmotionalValence.negative ||
                    b == EmotionalValence.veryNegative)) ||
            (a == EmotionalValence.veryNegative &&
                (b == EmotionalValence.positive ||
                    b == EmotionalValence.veryPositive));

        if (isOpposite) {
          conflicts.add(
              '${concepts[i].content} ↔ ${concepts[j].content}');
        }
      }
    }
    return conflicts;
  }

  String? _findDominantTheme(
    List<Concept> concepts,
    ConceptualGraph graph,
  ) {
    if (concepts.isEmpty) return null;

    // Find the concept with the most connections to other workspace concepts
    var bestId = '';
    var bestCount = 0;

    for (final concept in concepts) {
      final related = graph
          .findRelatedConcepts(concept.id, 2)
          .map((n) => n.id)
          .toSet();

      final localConnections = concepts
          .where((c) => c.id != concept.id && related.contains(c.id))
          .length;

      if (localConnections > bestCount) {
        bestCount = localConnections;
        bestId = concept.id;
      }
    }

    if (bestId.isEmpty) {
      // Fall back to most activated
      return concepts
          .reduce((a, b) =>
              a.activationLevel >= b.activationLevel ? a : b)
          .content;
    }

    return concepts
        .cast<Concept?>()
        .firstWhere((c) => c?.id == bestId, orElse: () => null)
        ?.content;
  }
}
