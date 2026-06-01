// lib/memory/episodic_memory.dart
// Episodic Memory — stores specific past events and experiences.
//
// Episodic memory (Tulving, 1972) is the memory of autobiographical events:
// times, places, and associated emotions. Unlike semantic memory, episodic
// memories are tied to a specific "when and where".

import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import 'package:consciousness_sim/core/models.dart';
import 'package:consciousness_sim/utils/logger.dart';

// ─────────────────────────────────────────────
// EpisodicMemory
// ─────────────────────────────────────────────

/// Stores and retrieves episodic memories — specific experiences and events.
///
/// ### Storage model
/// - Each [Memory] is stored with a strength that decays over time following
///   Ebbinghaus' forgetting curve.
/// - Repeated recall reinforces the memory (Hebbian consolidation).
/// - Memories below [pruneThreshold] are purged during consolidation.
class EpisodicMemory {
  EpisodicMemory({
    this.capacity = 500,
    this.pruneThreshold = 0.05,
    ConsciousnessLogger? logger,
  })  : assert(capacity > 0),
        assert(pruneThreshold >= 0.0 && pruneThreshold <= 1.0),
        _logger = logger ?? ConsciousnessLogger('EpisodicMemory');

  final int capacity;
  final double pruneThreshold;
  final ConsciousnessLogger _logger;
  final _uuid = const Uuid();

  final Map<String, Memory> _store = {}; // id → Memory
  final List<String> _insertionOrder = []; // LRU tracking

  // ── Public API ─────────────────────────────

  /// Number of stored episodic memories.
  int get count => _store.length;

  /// Stores a [Perception] as a new episodic memory.
  ///
  /// Returns the created [Memory] object.
  Memory store(
    Perception event, {
    Duration retention = const Duration(days: 7),
    double initialStrength = 1.0,
    Map<String, dynamic>? context,
  }) {
    if (_store.length >= capacity) _evictOldest();

    final memory = Memory(
      id: _uuid.v4(),
      content: event.rawInput,
      type: MemoryType.episodic,
      timestamp: event.timestamp,
      emotionalValence: EmotionalValence.neutral,
      strength: initialStrength,
      associatedConceptIds: event.tokens.take(10).toList(),
      context: context ?? {'modality': event.modality.name},
    );

    _store[memory.id] = memory;
    _insertionOrder.add(memory.id);

    _logger.debug(
        'Stored episode: "${_truncate(event.rawInput)}" '
        '(strength: ${initialStrength.toStringAsFixed(2)})');

    return memory;
  }

  /// Stores an arbitrary [Memory] directly.
  void storeMemory(Memory memory) {
    if (_store.length >= capacity) _evictOldest();
    _store[memory.id] = memory;
    _insertionOrder.add(memory.id);
  }

  /// Searches episodic memories whose content contains [query] tokens.
  ///
  /// Results are ranked by: strength × recency × recall frequency.
  List<Memory> search(String query, {int maxResults = 10}) {
    final tokens = _tokenise(query);
    if (tokens.isEmpty) return [];

    final scored = <MapEntry<Memory, double>>[];
    for (final memory in _store.values) {
      final score = _scoreMemory(memory, tokens);
      if (score > 0.0) scored.add(MapEntry(memory, score));
    }

    scored.sort((a, b) => b.value.compareTo(a.value));

    // Reinforce recalled memories
    final results = scored.take(maxResults).map((e) {
      e.key.reinforce(amount: 0.05);
      return e.key;
    }).toList();

    _logger.debug(
        'Episodic search "$query": ${results.length} result(s)');
    return results;
  }

  /// Retrieves memories associated with any of the given [conceptIds].
  List<Memory> retrieveByConceptIds(
    List<String> conceptIds, {
    int maxResults = 10,
  }) {
    return _store.values
        .where((m) => m.associatedConceptIds
            .any((cid) => conceptIds.contains(cid)))
        .toList()
      ..sort((a, b) => b.strength.compareTo(a.strength))
      ..take(maxResults);
  }

  /// Retrieves the [n] most recent episodic memories.
  List<Memory> getMostRecent(int n) {
    final all = _store.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return all.take(n).toList();
  }

  /// Applies Ebbinghaus temporal decay to all stored memories.
  ///
  /// Memories whose strength falls below [pruneThreshold] are removed.
  void applyDecay({double halfLifeHours = 24.0}) {
    var pruned = 0;
    final toRemove = <String>[];

    for (final memory in _store.values) {
      memory.applyDecay(halfLifeHours: halfLifeHours);
      if (memory.strength < pruneThreshold) {
        toRemove.add(memory.id);
        pruned++;
      }
    }

    for (final id in toRemove) {
      _store.remove(id);
      _insertionOrder.remove(id);
    }

    if (pruned > 0) {
      _logger.debug('Episodic decay pruned $pruned weak memories');
    }
  }

  /// Returns the [n] strongest memories (for consolidation into semantic).
  List<Memory> getStrongestMemories(int n) {
    final all = _store.values.toList()
      ..sort((a, b) => b.strength.compareTo(a.strength));
    return all.take(n).toList();
  }

  /// Returns all memories associated with a particular [modality].
  List<Memory> getByModality(String modalityName) => _store.values
      .where((m) => m.context['modality'] == modalityName)
      .toList();

  /// All stored memories as an unmodifiable list.
  List<Memory> getAll() => List.unmodifiable(_store.values);

  /// Removes a specific memory by ID.
  void forget(String memoryId) {
    _store.remove(memoryId);
    _insertionOrder.remove(memoryId);
  }

  // ── Private helpers ─────────────────────────

  double _scoreMemory(Memory memory, Set<String> queryTokens) {
    final contentTokens = _tokenise(memory.content);
    final intersection =
        contentTokens.intersection(queryTokens).length.toDouble();
    if (intersection == 0) return 0.0;

    final tokenScore = intersection / queryTokens.length;
    final recency = _recencyScore(memory.timestamp);
    return tokenScore * 0.6 + memory.strength * 0.3 + recency * 0.1;
  }

  double _recencyScore(DateTime ts) {
    final ageHours =
        DateTime.now().difference(ts).inMinutes / 60.0;
    return math.exp(-ageHours / 72.0).clamp(0.0, 1.0); // 72h half-life
  }

  Set<String> _tokenise(String text) => text
      .toLowerCase()
      .split(RegExp(r'[\s,;.!?]+'))
      .where((t) => t.length > 1)
      .toSet();

  void _evictOldest() {
    if (_insertionOrder.isEmpty) return;
    // Evict the oldest AND weakest if we have candidates
    final victim = _insertionOrder.first;
    _store.remove(victim);
    _insertionOrder.removeAt(0);
  }

  String _truncate(String s, [int maxLen = 50]) =>
      s.length > maxLen ? '${s.substring(0, maxLen - 3)}...' : s;

  @override
  String toString() =>
      'EpisodicMemory(count: $count/$capacity)';
}
