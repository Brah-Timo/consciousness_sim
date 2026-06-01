// lib/memory/semantic_memory.dart
// Semantic Memory — stores general facts, concepts, and knowledge.
//
// Semantic memory (Tulving, 1972) contains world knowledge that is
// context-independent: "cats eat fish", "fire is hot", "Paris is in France".
// It is built by generalising from multiple episodic experiences.

import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import 'package:consciousness_sim/core/models.dart';
import 'package:consciousness_sim/utils/logger.dart';

// ─────────────────────────────────────────────
// SemanticFact
// ─────────────────────────────────────────────

/// A generalised fact stored in semantic memory.
///
/// Semantic facts are derived from repeated episodic patterns.
class SemanticFact {
  SemanticFact({
    required this.id,
    required this.subject,
    required this.predicate,
    required this.object,
    double confidence = 0.5,
    int occurrences = 1,
    DateTime? firstSeen,
    DateTime? lastSeen,
    List<String>? supportingEpisodeIds,
  })  : assert(confidence >= 0.0 && confidence <= 1.0),
        confidence = confidence,
        occurrences = occurrences,
        firstSeen = firstSeen ?? DateTime.now(),
        lastSeen = lastSeen ?? DateTime.now(),
        supportingEpisodeIds = supportingEpisodeIds ?? [];

  final String id;
  final String subject;
  final String predicate;
  final String object;
  double confidence;
  int occurrences;
  final DateTime firstSeen;
  DateTime lastSeen;
  final List<String> supportingEpisodeIds;

  /// Natural-language rendering: "cats eat fish"
  String get statement => '$subject $predicate $object';

  /// Strengthen this fact when confirmed by new evidence.
  void reinforce({double amount = 0.1}) {
    confidence = math.min(1.0, confidence + amount);
    occurrences++;
    lastSeen = DateTime.now();
  }

  /// Weaken this fact when contradicted by evidence.
  void contradict({double amount = 0.1}) {
    confidence = math.max(0.0, confidence - amount);
  }

  @override
  String toString() =>
      'SemanticFact("$statement", '
      'conf: ${confidence.toStringAsFixed(2)}, '
      'seen: $occurrences×)';
}

// ─────────────────────────────────────────────
// SemanticMemory
// ─────────────────────────────────────────────

/// Stores, retrieves, and manages general world-knowledge facts.
class SemanticMemory {
  SemanticMemory({
    ConsciousnessLogger? logger,
  }) : _logger = logger ?? ConsciousnessLogger('SemanticMemory');

  final ConsciousnessLogger _logger;
  final _uuid = const Uuid();

  /// Triple store: subject → (predicate|object) → [SemanticFact]
  final Map<String, List<SemanticFact>> _bySubject = {};

  /// Flat id → fact for direct lookup.
  final Map<String, SemanticFact> _byId = {};

  // ── Public API ─────────────────────────────

  /// Number of facts in semantic memory.
  int get count => _byId.length;

  /// Stores or reinforces a subject–predicate–object fact.
  ///
  /// If an identical triple already exists it is reinforced.
  /// Returns the [SemanticFact] (new or updated).
  SemanticFact storeFact({
    required String subject,
    required String predicate,
    required String object,
    double confidence = 0.5,
    String? episodeId,
  }) {
    final subjectKey = subject.toLowerCase().trim();
    final facts = _bySubject[subjectKey] ??= [];

    // Check for duplicate
    final existing = facts.cast<SemanticFact?>().firstWhere(
          (f) =>
              f!.predicate.toLowerCase() == predicate.toLowerCase() &&
              f.object.toLowerCase() == object.toLowerCase(),
          orElse: () => null,
        );

    if (existing != null) {
      existing.reinforce(amount: confidence * 0.1);
      if (episodeId != null &&
          !existing.supportingEpisodeIds.contains(episodeId)) {
        existing.supportingEpisodeIds.add(episodeId);
      }
      _logger.debug('Reinforced fact: "${existing.statement}"');
      return existing;
    }

    final fact = SemanticFact(
      id: _uuid.v4(),
      subject: subjectKey,
      predicate: predicate.toLowerCase().trim(),
      object: object.toLowerCase().trim(),
      confidence: confidence,
      supportingEpisodeIds: episodeId != null ? [episodeId] : [],
    );

    facts.add(fact);
    _byId[fact.id] = fact;

    _logger.debug(
        'Stored fact: "${fact.statement}" '
        '(conf: ${confidence.toStringAsFixed(2)})');
    return fact;
  }

  /// Stores a raw [Memory] object directly (non-triple form).
  void storeMemory(Memory memory) {
    // Extract a simple fact from the memory content
    final tokens = memory.content.split(RegExp(r'\s+'));
    if (tokens.length >= 3) {
      storeFact(
        subject: tokens.first,
        predicate: tokens.length > 2 ? tokens[1] : 'is',
        object: tokens.skip(2).join(' '),
        confidence: memory.strength,
      );
    }
  }

  /// Retrieves facts about a given [subject].
  List<SemanticFact> factsAbout(String subject) =>
      _bySubject[subject.toLowerCase().trim()] ?? [];

  /// Searches facts whose content contains [query] tokens.
  List<Memory> search(String query, {int maxResults = 10}) {
    final tokens = _tokenise(query);
    final scored = <MapEntry<SemanticFact, double>>[];

    for (final fact in _byId.values) {
      final score = _scoreFact(fact, tokens);
      if (score > 0) scored.add(MapEntry(fact, score));
    }

    scored.sort((a, b) => b.value.compareTo(a.value));

    return scored.take(maxResults).map((e) {
      final f = e.key;
      return Memory(
        id: f.id,
        content: f.statement,
        type: MemoryType.semantic,
        strength: f.confidence,
      );
    }).toList();
  }

  /// Returns all facts above a minimum [confidence] threshold.
  List<SemanticFact> getHighConfidenceFacts({double minConfidence = 0.7}) =>
      _byId.values
          .where((f) => f.confidence >= minConfidence)
          .toList()
        ..sort((a, b) => b.confidence.compareTo(a.confidence));

  /// Returns the [n] most frequently seen facts.
  List<SemanticFact> getMostFrequentFacts(int n) {
    final all = _byId.values.toList()
      ..sort((a, b) => b.occurrences.compareTo(a.occurrences));
    return all.take(n).toList();
  }

  /// Generalises from episodic [memories] into semantic facts.
  ///
  /// This is the core consolidation step:
  /// repeated episodic patterns → generalised semantic knowledge.
  int generaliseFromEpisodes(List<Memory> memories) {
    var newFacts = 0;

    for (final memory in memories) {
      final extracted = _extractTriples(memory.content);
      for (final triple in extracted) {
        final fact = storeFact(
          subject: triple.subject,
          predicate: triple.predicate,
          object: triple.object,
          confidence: memory.strength * 0.5,
          episodeId: memory.id,
        );
        if (fact.occurrences == 1) newFacts++;
      }
    }

    if (newFacts > 0) {
      _logger.info(
          'Generalised $newFacts new semantic fact(s) from episodes');
    }
    return newFacts;
  }

  /// All stored facts.
  List<SemanticFact> getAll() => List.unmodifiable(_byId.values);

  /// Removes a fact by ID.
  void forget(String factId) {
    final fact = _byId.remove(factId);
    if (fact != null) {
      _bySubject[fact.subject]?.removeWhere((f) => f.id == factId);
    }
  }

  // ── Private helpers ─────────────────────────

  double _scoreFact(SemanticFact fact, Set<String> tokens) {
    final factTokens = _tokenise(fact.statement);
    final overlap =
        factTokens.intersection(tokens).length.toDouble();
    if (overlap == 0) return 0.0;
    return (overlap / tokens.length) * 0.7 + fact.confidence * 0.3;
  }

  Set<String> _tokenise(String text) => text
      .toLowerCase()
      .split(RegExp(r'[\s,;.!?]+'))
      .where((t) => t.length > 1)
      .toSet();

  // Very simple triple extractor — can be upgraded with an NLP pipeline.
  List<_Triple> _extractTriples(String text) {
    final parts = text.trim().split(RegExp(r'\s+'));
    if (parts.length < 3) return [];
    return [
      _Triple(
        subject: parts[0],
        predicate: parts[1],
        object: parts.skip(2).join(' '),
      ),
    ];
  }

  @override
  String toString() => 'SemanticMemory(facts: $count)';
}

class _Triple {
  const _Triple({
    required this.subject,
    required this.predicate,
    required this.object,
  });

  final String subject;
  final String predicate;
  final String object;
}
