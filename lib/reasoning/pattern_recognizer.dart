// lib/reasoning/pattern_recognizer.dart
// Pattern Recognizer — discovers recurring structures across concepts.
//
// Uses frequency-based and structural analysis to identify:
//   • Co-occurrence patterns (frequent concept pairs)
//   • Sequential patterns (concept chains over time)
//   • Analogical patterns (structural similarity)

import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import 'package:consciousness_sim/core/models.dart';
import 'package:consciousness_sim/utils/logger.dart';

// ─────────────────────────────────────────────
// PatternRecognizer
// ─────────────────────────────────────────────

/// Discovers recurring patterns in the concept stream.
///
/// Patterns are identified by:
/// - **Co-occurrence**: Which concepts appear together frequently.
/// - **Sequence**: Which concepts follow which in the observation stream.
/// - **Analogy**: Which concepts have structurally similar neighbourhoods.
class PatternRecognizer {
  PatternRecognizer({
    this.minOccurrences = 2,
    this.minConfidence = 0.4,
    ConsciousnessLogger? logger,
  })  : assert(minOccurrences >= 1),
        assert(minConfidence >= 0.0 && minConfidence <= 1.0),
        _logger = logger ?? ConsciousnessLogger('PatternRecognizer');

  final int minOccurrences;
  final double minConfidence;
  final ConsciousnessLogger _logger;
  final _uuid = const Uuid();

  // ── Frequency counters ─────────────────────
  /// Single-concept occurrence count.
  final Map<String, int> _conceptFreq = {};

  /// Co-occurrence count for concept pairs.
  final Map<String, int> _coOccurrence = {};

  /// Sequence pairs: (antecedent, consequent).
  final Map<String, int> _sequences = {};

  /// All discovered patterns.
  final List<Pattern> _discoveredPatterns = [];

  // ── Window for sequence tracking ───────────
  final List<String> _sequenceWindow = [];
  static const _windowSize = 10;

  // ── Public API ─────────────────────────────

  /// Registers a new [concept] observation.
  ///
  /// Updates frequency, co-occurrence, and sequence counters.
  void observe(Concept concept) {
    _conceptFreq[concept.id] = (_conceptFreq[concept.id] ?? 0) + 1;

    // Sequence: record transitions from previous window item
    if (_sequenceWindow.isNotEmpty) {
      final prev = _sequenceWindow.last;
      final seqKey = '$prev→${concept.id}';
      _sequences[seqKey] = (_sequences[seqKey] ?? 0) + 1;
    }

    // Co-occurrence with all items currently in window
    for (final prevId in _sequenceWindow) {
      final coKey = _coKey(prevId, concept.id);
      _coOccurrence[coKey] = (_coOccurrence[coKey] ?? 0) + 1;
    }

    _sequenceWindow.add(concept.id);
    if (_sequenceWindow.length > _windowSize) {
      _sequenceWindow.removeAt(0);
    }
  }

  /// Observes a batch of concepts (e.g. a full workspace snapshot).
  void observeBatch(List<Concept> concepts) {
    for (final c in concepts) {
      observe(c);
    }
  }

  /// Discovers all patterns that exceed [minOccurrences] and [minConfidence].
  ///
  /// Returns newly discovered [Pattern] objects.
  List<Pattern> discover(Map<String, String> conceptLabels) {
    final newPatterns = <Pattern>[];

    // 1. Co-occurrence patterns
    for (final entry in _coOccurrence.entries) {
      if (entry.value < minOccurrences) continue;

      final ids = _splitCoKey(entry.key);
      if (ids.length != 2) continue;

      final freq1 = _conceptFreq[ids[0]] ?? 1;
      final freq2 = _conceptFreq[ids[1]] ?? 1;
      final support = entry.value / math.max(freq1, freq2);

      if (support >= minConfidence) {
        final label1 = conceptLabels[ids[0]] ?? ids[0].substring(0, 8);
        final label2 = conceptLabels[ids[1]] ?? ids[1].substring(0, 8);
        final p = Pattern(
          id: _uuid.v4(),
          description: 'Co-occurrence: "$label1" with "$label2"',
          involvedConceptIds: ids,
          confidence: support,
          occurrenceCount: entry.value,
        );
        if (!_isDuplicate(p)) {
          newPatterns.add(p);
          _discoveredPatterns.add(p);
        }
      }
    }

    // 2. Sequence patterns
    for (final entry in _sequences.entries) {
      if (entry.value < minOccurrences) continue;

      final parts = entry.key.split('→');
      if (parts.length != 2) continue;

      final antecedent = parts[0];
      final consequent = parts[1];
      final antFreq = _conceptFreq[antecedent] ?? 1;
      final confidence = entry.value / antFreq;

      if (confidence >= minConfidence) {
        final lA = conceptLabels[antecedent] ?? antecedent.substring(0, 8);
        final lB = conceptLabels[consequent] ?? consequent.substring(0, 8);
        final p = Pattern(
          id: _uuid.v4(),
          description: 'Sequence: "$lA" is followed by "$lB"',
          involvedConceptIds: [antecedent, consequent],
          confidence: confidence,
          occurrenceCount: entry.value,
        );
        if (!_isDuplicate(p)) {
          newPatterns.add(p);
          _discoveredPatterns.add(p);
        }
      }
    }

    if (newPatterns.isNotEmpty) {
      _logger.info(
          'Discovered ${newPatterns.length} new pattern(s) '
          '(total: ${_discoveredPatterns.length})');
    }

    return newPatterns;
  }

  /// Returns all discovered patterns sorted by confidence descending.
  List<Pattern> getAllPatterns() {
    return List.of(_discoveredPatterns)
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
  }

  /// Returns the top [n] most confident patterns.
  List<Pattern> getTopPatterns(int n) => getAllPatterns().take(n).toList();

  /// Predicts what concept is likely to follow [conceptId] based on
  /// observed sequences. Returns a list of (conceptId, confidence) pairs.
  List<MapEntry<String, double>> predictNextConcept(String conceptId) {
    final predictions = <MapEntry<String, double>>[];
    final antFreq = _conceptFreq[conceptId] ?? 1;

    for (final entry in _sequences.entries) {
      final parts = entry.key.split('→');
      if (parts.length != 2) continue;
      if (parts[0] != conceptId) continue;

      final confidence = entry.value / antFreq;
      if (confidence >= 0.1) {
        predictions.add(MapEntry(parts[1], confidence));
      }
    }

    predictions.sort((a, b) => b.value.compareTo(a.value));
    return predictions;
  }

  /// Returns the [n] most frequently occurring concepts.
  List<MapEntry<String, int>> getMostFrequent(int n) {
    final sorted = _conceptFreq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(n).toList();
  }

  /// Resets all counters (but not discovered patterns).
  void resetCounters() {
    _conceptFreq.clear();
    _coOccurrence.clear();
    _sequences.clear();
    _sequenceWindow.clear();
  }

  // ── Private helpers ─────────────────────────

  String _coKey(String a, String b) {
    final sorted = [a, b]..sort();
    return '${sorted[0]}⊕${sorted[1]}';
  }

  List<String> _splitCoKey(String key) => key.split('⊕');

  bool _isDuplicate(Pattern p) => _discoveredPatterns
      .any((existing) => existing.description == p.description);
}
