// lib/memory/memory_manager.dart
// MemoryManager — orchestrates all three memory subsystems.
//
// Handles:
//   • Encoding new perceptions into episodic memory
//   • Consolidation: episodic → semantic generalisation
//   • Context-sensitive retrieval across all stores
//   • Temporal decay and forgetting

import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import 'package:consciousness_sim/core/models.dart';
import 'package:consciousness_sim/memory/episodic_memory.dart';
import 'package:consciousness_sim/memory/semantic_memory.dart';
import 'package:consciousness_sim/memory/working_memory.dart';
import 'package:consciousness_sim/utils/logger.dart';

// ─────────────────────────────────────────────
// MemoryManager
// ─────────────────────────────────────────────

/// Central memory orchestrator integrating episodic, semantic, and working
/// memory into a unified retrieval and encoding interface.
///
/// ### Memory flow
/// ```
/// observe(input)
///   → working memory (immediate buffer)
///   → episodic memory (specific event storage)
///
/// consolidateMemories()
///   → episodic → semantic (generalisation)
///   → working → episodic (promotion of important items)
/// ```
class MemoryManager {
  MemoryManager({
    bool enableLongTermLearning = true,
    int episodicCapacity = 500,
    int workingCapacity = 4,
    Duration workingMemoryAge = const Duration(minutes: 5),
    ConsciousnessLogger? logger,
  })  : _enableLongTermLearning = enableLongTermLearning,
        _logger = logger ?? ConsciousnessLogger('MemoryManager'),
        episodic = EpisodicMemory(
          capacity: episodicCapacity,
          logger: logger,
        ),
        semantic = SemanticMemory(logger: logger),
        working = WorkingMemory(
          capacity: workingCapacity,
          maxItemAge: workingMemoryAge,
          logger: logger,
        );

  final bool _enableLongTermLearning;
  final ConsciousnessLogger _logger;
  final _uuid = const Uuid();

  // ── Sub-stores (public access for advanced use) ─

  /// Episodic memory: specific events and experiences.
  final EpisodicMemory episodic;

  /// Semantic memory: general world knowledge and facts.
  final SemanticMemory semantic;

  /// Working memory: short-term active buffer.
  final WorkingMemory working;

  // ── Association index ──────────────────────
  /// Tracks reinforcement weights between entity pairs.
  final Map<String, double> _associations = {};

  // ── PUBLIC API ─────────────────────────────

  /// Encodes a [Perception] event into episodic memory.
  Memory storeEpisode(
    Perception event, {
    Duration retention = const Duration(days: 7),
  }) {
    final memory = episodic.store(event, retention: retention);
    _logger.debug(
        'Episode stored: "${_trunc(event.rawInput)}"');
    return memory;
  }

  /// Stores an arbitrary string as an episodic memory.
  Memory storeRawEpisode(
    String content, {
    MemoryType type = MemoryType.episodic,
    double strength = 1.0,
    List<String>? associatedConceptIds,
  }) {
    final memory = Memory(
      id: _uuid.v4(),
      content: content,
      type: type,
      strength: strength,
      associatedConceptIds: associatedConceptIds ?? [],
    );
    episodic.storeMemory(memory);
    return memory;
  }

  /// Retrieves memories from all stores matching the [context] query.
  ///
  /// Results are merged and ranked by composite score.
  List<Memory> retrieveByContext(
    String context, {
    int maxResults = 15,
  }) {
    final episodics = episodic.search(context, maxResults: maxResults);
    final semantics = semantic.search(context, maxResults: maxResults);
    final workingMems = working.search(context);

    // Merge and de-duplicate by content
    final seen = <String>{};
    final all = [...workingMems, ...episodics, ...semantics];
    final unique = all.where((m) => seen.add(m.content)).toList();

    // Sort by composite score: strength × recency
    unique.sort((a, b) {
      final scoreA = a.strength * _recencyFactor(a.timestamp);
      final scoreB = b.strength * _recencyFactor(b.timestamp);
      return scoreB.compareTo(scoreA);
    });

    return unique.take(maxResults).toList();
  }

  /// Reinforces the association between two entities/concepts.
  ///
  /// [strength] can be negative to weaken the association.
  void reinforceAssociation(
    String entity1,
    String entity2, {
    double strength = 0.2,
  }) {
    final key = _associationKey(entity1, entity2);
    final current = _associations[key] ?? 0.0;
    _associations[key] = (current + strength).clamp(-1.0, 1.0);
    _logger.debug(
        'Association "$entity1" ↔ "$entity2": '
        '${_associations[key]!.toStringAsFixed(2)}');
  }

  /// Returns the association strength between two entities.
  double getAssociation(String entity1, String entity2) =>
      _associations[_associationKey(entity1, entity2)] ?? 0.0;

  /// Computes how contextually relevant a [content] string is,
  /// based on existing memories.
  ///
  /// Returns a score in [0, 1].
  double computeContextualRelevance(String content) {
    final memories = retrieveByContext(content, maxResults: 5);
    if (memories.isEmpty) return 0.2; // Baseline for novelty
    final avgStrength =
        memories.map((m) => m.strength).reduce((a, b) => a + b) /
            memories.length;
    return math.min(1.0, avgStrength * 0.8 + 0.2);
  }

  /// Runs full memory consolidation:
  ///   1. Promote working memory items to episodic.
  ///   2. Generalise strong episodic memories to semantic.
  ///   3. Apply decay to episodic store.
  Future<void> consolidateMemories() async {
    if (!_enableLongTermLearning) return;

    _logger.info('Starting memory consolidation...');

    // Step 1: Working → Episodic promotion
    final workingItems = working.getAll();
    for (final mem in workingItems) {
      if (mem.strength >= 0.6) {
        final promoted = Memory(
          id: _uuid.v4(),
          content: mem.content,
          type: MemoryType.episodic,
          strength: mem.strength * 0.9,
          associatedConceptIds: mem.associatedConceptIds,
        );
        episodic.storeMemory(promoted);
      }
    }

    // Step 2: Episodic → Semantic generalisation
    final strongEpisodic = episodic.getStrongestMemories(50);
    final newFacts =
        semantic.generaliseFromEpisodes(strongEpisodic);

    // Step 3: Episodic decay
    episodic.applyDecay(halfLifeHours: 48.0);

    _logger.info(
        'Consolidation complete: '
        'promoted ${workingItems.length} working items, '
        'generated $newFacts semantic facts, '
        'episodic count: ${episodic.count}');
  }

  /// Applies temporal decay to the episodic store.
  void applyTemporalDecay() => episodic.applyDecay();

  /// Returns a summary of memory statistics.
  Map<String, int> getStats() => {
        'episodic': episodic.count,
        'semantic': semantic.count,
        'working': working.size,
        'associations': _associations.length,
      };

  // ── Private helpers ─────────────────────────

  double _recencyFactor(DateTime ts) {
    final ageHours = DateTime.now().difference(ts).inMinutes / 60.0;
    return math.exp(-ageHours / 24.0).clamp(0.0, 1.0);
  }

  String _associationKey(String a, String b) {
    final sorted = [a, b]..sort();
    return '${sorted[0]}||${sorted[1]}';
  }

  String _trunc(String s, [int n = 50]) =>
      s.length > n ? '${s.substring(0, n - 3)}...' : s;

  @override
  String toString() =>
      'MemoryManager('
      'episodic: ${episodic.count}, '
      'semantic: ${semantic.count}, '
      'working: ${working.size})';
}
