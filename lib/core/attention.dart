// lib/core/attention.dart
// Attention Spotlight — the selective focus mechanism.
//
// Inspired by the spotlight metaphor in cognitive neuroscience (Posner, 1980;
// Treisman, 1980). The spotlight illuminates a narrow region of the global
// workspace with high-intensity processing while peripheral items receive
// reduced resources.

import 'dart:async';
import 'dart:math' as math;

import 'package:consciousness_sim/core/models.dart';
import 'package:consciousness_sim/utils/logger.dart';

// ─────────────────────────────────────────────
// AttentionEntry — tracks one attended concept
// ─────────────────────────────────────────────

class _AttentionEntry {
  _AttentionEntry({
    required this.conceptId,
    required this.weight,
    required this.enteredAt,
    this.isPrimary = false,
  });

  final String conceptId;
  double weight;
  final DateTime enteredAt;
  bool isPrimary;

  Duration get dwellTime => DateTime.now().difference(enteredAt);
}

// ─────────────────────────────────────────────
// AttentionSpotlight
// ─────────────────────────────────────────────

/// Models selective attention as a spotlight that illuminates concepts
/// according to their salience, emotional charge, and task relevance.
///
/// ### Spotlight dynamics
/// - **Focus**: One concept holds the primary spotlight.
/// - **Periphery**: Up to [peripherySize] concepts receive partial attention.
/// - **Wandering**: A background timer shifts attention over a list of targets.
/// - **Salience calculation**: Weighs novelty, relevance, recency, emotion.
class AttentionSpotlight {
  AttentionSpotlight({
    this.peripherySize = 4,
    this.attentionThreshold = 0.3,
    ConsciousnessLogger? logger,
  })  : assert(peripherySize >= 0 && peripherySize <= 10),
        assert(attentionThreshold >= 0.0 && attentionThreshold <= 1.0),
        _logger = logger ?? ConsciousnessLogger('AttentionSpotlight');

  // ── Configuration ──────────────────────────
  final int peripherySize;
  final double attentionThreshold;
  final ConsciousnessLogger _logger;

  // ── Internal state ─────────────────────────
  final Map<String, _AttentionEntry> _attended = {};
  String? _primaryFocusId;
  Timer? _wanderTimer;

  // ── Public API ─────────────────────────────

  /// The ID of the concept currently in the primary spotlight.
  String? get primaryFocusId => _primaryFocusId;

  /// All concept IDs currently under any level of attention.
  Set<String> get attendedIds => Set.unmodifiable(_attended.keys);

  /// Returns the attention weight for a specific concept (0.0 if absent).
  double weightOf(String conceptId) =>
      _attended[conceptId]?.weight ?? 0.0;

  /// Directs the spotlight to [targetId] with the given [intensity].
  ///
  /// Any previous primary focus is demoted to the periphery (if possible).
  void focus(String targetId, double intensity) {
    assert(intensity >= 0.0 && intensity <= 1.0,
        'intensity must be in [0, 1]');

    // Demote current primary to periphery
    if (_primaryFocusId != null && _primaryFocusId != targetId) {
      final prev = _attended[_primaryFocusId!];
      if (prev != null) {
        prev
          ..isPrimary = false
          ..weight = prev.weight * 0.5;
        _prunePeriphery();
      }
    }

    if (_attended.containsKey(targetId)) {
      _attended[targetId]!
        ..weight = intensity
        ..isPrimary = true;
    } else {
      _attended[targetId] = _AttentionEntry(
        conceptId: targetId,
        weight: intensity,
        enteredAt: DateTime.now(),
        isPrimary: true,
      );
    }

    _primaryFocusId = targetId;
    _logger.info(
        'Spotlight focused on "$targetId" '
        '(intensity: ${intensity.toStringAsFixed(2)})');
  }

  /// Adds a concept to the periphery of attention (lower weight).
  void addToPeriphery(String conceptId, double weight) {
    if (_attended.length >= peripherySize + 1) _prunePeriphery();

    if (!_attended.containsKey(conceptId)) {
      _attended[conceptId] = _AttentionEntry(
        conceptId: conceptId,
        weight: weight * 0.5, // Periphery gets half the weight
        enteredAt: DateTime.now(),
      );
    }
  }

  /// Removes a concept from attention entirely.
  void withdraw(String conceptId) {
    _attended.remove(conceptId);
    if (_primaryFocusId == conceptId) {
      _primaryFocusId = _attended.isEmpty
          ? null
          : _attended.values
              .reduce((a, b) => a.weight >= b.weight ? a : b)
              .conceptId;
      if (_primaryFocusId != null) {
        _attended[_primaryFocusId!]!.isPrimary = true;
      }
    }
  }

  /// Calculates the salience of a [concept] given the current context.
  ///
  /// Salience = (novelty × 0.25) + (relevance × 0.35)
  ///          + (recency  × 0.20) + (emotion  × 0.20)
  double calculateSalience(Concept concept) {
    final novelty = concept.noveltyScore;
    final relevance = concept.contextualRelevance;
    final recency = concept.recencyScore;
    final emotion = concept.emotionalWeight;

    return (novelty * 0.25) +
        (relevance * 0.35) +
        (recency * 0.20) +
        (emotion * 0.20);
  }

  /// Evaluates a list of [candidates] and updates the spotlight to the
  /// most salient one that exceeds [attentionThreshold].
  ///
  /// Returns the ID of the newly focused concept, or null if none qualifies.
  String? evaluateAndFocus(List<Concept> candidates) {
    if (candidates.isEmpty) return null;

    Concept? best;
    var bestSalience = attentionThreshold; // Must exceed threshold

    for (final concept in candidates) {
      final s = calculateSalience(concept);
      if (s > bestSalience) {
        bestSalience = s;
        best = concept;
      }
    }

    if (best != null) {
      // Update context relevance for top candidates (lateral inhibition)
      for (final concept in candidates) {
        final s = calculateSalience(concept);
        if (s > attentionThreshold * 0.5) {
          addToPeriphery(concept.id, s);
        }
      }
      focus(best.id, bestSalience);
      return best.id;
    }
    return null;
  }

  /// Rebalances attention toward a list of [priorities] (concept IDs).
  ///
  /// Existing items not in [priorities] have their weights halved.
  void rebalance(List<String> priorities) {
    // Downweight existing non-priority items
    for (final entry in _attended.values) {
      if (!priorities.contains(entry.conceptId)) {
        entry.weight = (entry.weight * 0.5).clamp(0.0, 1.0);
      }
    }

    // Boost priority items
    final baseBoost = 1.0 / math.max(1, priorities.length);
    for (var i = 0; i < priorities.length; i++) {
      final id = priorities[i];
      final weight = baseBoost * (1.0 - i * 0.1).clamp(0.1, 1.0);
      if (i == 0) {
        focus(id, weight);
      } else {
        addToPeriphery(id, weight);
      }
    }

    _logger.info(
        'Attention rebalanced to priorities: '
        '${priorities.take(3).join(', ')}...');
  }

  /// Causes the spotlight to wander over [targets] with [dwellTime] per item.
  ///
  /// Useful for exploratory attention or mind-wandering simulation.
  /// Returns a [Future] that completes when the cycle finishes.
  Future<void> wanderAttention(
    List<String> targets,
    Duration dwellTime,
  ) async {
    _wanderTimer?.cancel();
    _logger.debug('Starting attention wander over ${targets.length} targets');

    for (final target in targets) {
      focus(target, 0.8);
      await Future<void>.delayed(dwellTime);
    }

    _logger.debug('Attention wander complete');
  }

  /// Cancels any ongoing attention wandering.
  void cancelWander() {
    _wanderTimer?.cancel();
    _wanderTimer = null;
  }

  /// Returns how long the current primary concept has been in focus.
  Duration get primaryFocusDwellTime {
    if (_primaryFocusId == null) return Duration.zero;
    final entry = _attended[_primaryFocusId!];
    return entry?.dwellTime ?? Duration.zero;
  }

  /// Exports a sorted list of (conceptId, weight) pairs for display.
  List<MapEntry<String, double>> get weightedFocus => _attended.entries
      .map((e) => MapEntry(e.key, e.value.weight))
      .toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  // ── Private helpers ─────────────────────────

  void _prunePeriphery() {
    final nonPrimary =
        _attended.entries.where((e) => !e.value.isPrimary).toList()
          ..sort((a, b) => a.value.weight.compareTo(b.value.weight));

    // Remove weakest non-primary entries until within periphery budget
    while (nonPrimary.length > peripherySize) {
      final victim = nonPrimary.removeAt(0);
      _attended.remove(victim.key);
    }
  }

  @override
  String toString() =>
      'AttentionSpotlight('
      'focus: $_primaryFocusId, '
      'attended: ${_attended.length})';
}
