// lib/agent/memory/agent_memory_store.dart
//
// AgentMemoryStore — long-term key-value + full-text memory for the agent.
//
// Responsibilities:
//   • Store decisions, observations, reflections, and goal summaries.
//   • Retrieve entries by semantic similarity (keyword overlap proxy)
//     and by composite score (importance × recency).
//   • Summarise recent history into a compact string for LLM context.
//   • Persist goal-completion records so future goals can learn from past runs.

import 'dart:collection';

import 'package:uuid/uuid.dart';

import 'package:consciousness_sim/agent/agent_models.dart';
import 'package:consciousness_sim/utils/logger.dart';

// ─────────────────────────────────────────────
// AgentMemoryStore
// ─────────────────────────────────────────────

/// A single flat store of [AgentMemoryEntry] objects for the agent framework.
///
/// Internally it maintains:
///   - a chronological list (`_entries`)
///   - an inverted word-to-entry index (`_index`) for fast text search
///   - a goal-completion archive for cross-goal learning
///
/// ### Usage
/// ```dart
/// final store = AgentMemoryStore();
///
/// store.remember(
///   content: 'Found weather API at https://wttr.in',
///   type: AgentMemoryType.observation,
///   goalId: 'g-001',
///   importance: 0.8,
/// );
///
/// final hits = store.retrieve('weather API', maxResults: 5);
/// print(store.summarise(maxEntries: 10));
/// ```
class AgentMemoryStore {
  AgentMemoryStore({
    this.capacity = 2000,
    ConsciousnessLogger? logger,
  }) : _logger = logger ?? ConsciousnessLogger('AgentMemoryStore');

  /// Maximum number of entries before the lowest-scoring ones are evicted.
  final int capacity;

  final ConsciousnessLogger _logger;
  final _uuid = const Uuid();

  // Internal storage
  final List<AgentMemoryEntry> _entries = [];

  // Inverted index: normalised word → set of entry IDs
  final Map<String, Set<String>> _index = {};

  // Goal-completion archive keyed by goalId
  final Map<String, List<AgentMemoryEntry>> _goalArchive = {};

  // ── PUBLIC API ──────────────────────────────

  /// Number of entries currently stored.
  int get size => _entries.length;

  /// Stores a new memory entry and indexes it.
  ///
  /// Returns the created [AgentMemoryEntry].
  AgentMemoryEntry remember({
    required String content,
    required AgentMemoryType type,
    String? goalId,
    String? taskId,
    double importance = 0.5,
    Map<String, dynamic>? metadata,
  }) {
    final entry = AgentMemoryEntry(
      id: _uuid.v4(),
      type: type,
      content: content,
      goalId: goalId,
      taskId: taskId,
      importance: importance,
      metadata: metadata,
    );

    _entries.add(entry);
    _indexEntry(entry);

    if (type == AgentMemoryType.goalCompletion && goalId != null) {
      _goalArchive.putIfAbsent(goalId, () => []).add(entry);
    }

    if (_entries.length > capacity) {
      _evict();
    }

    _logger.debug(
        'Memory stored [${type.name}]: "${_trunc(content)}" '
        '(importance: ${importance.toStringAsFixed(2)})');

    return entry;
  }

  /// Retrieves up to [maxResults] entries relevant to [query].
  ///
  /// Uses a two-phase approach:
  ///   1. Keyword intersection to find candidate entries.
  ///   2. Sort candidates by composite score × keyword-overlap bonus.
  List<AgentMemoryEntry> retrieve(
    String query, {
    int maxResults = 10,
    AgentMemoryType? filterType,
    String? filterGoalId,
  }) {
    final queryTokens = _tokenise(query);
    if (queryTokens.isEmpty) {
      return _topByScore(
        maxResults,
        filterType: filterType,
        filterGoalId: filterGoalId,
      );
    }

    // Candidate set: union of index hits for each query token
    final candidateIds = <String>{};
    for (final token in queryTokens) {
      final hits = _index[token];
      if (hits != null) candidateIds.addAll(hits);
    }

    // Score candidates
    final candidates = _entries
        .where((e) =>
            candidateIds.contains(e.id) &&
            (filterType == null || e.type == filterType) &&
            (filterGoalId == null || e.goalId == filterGoalId))
        .map((e) {
      final overlap = _overlapScore(queryTokens, _tokenise(e.content));
      return _ScoredEntry(entry: e, score: e.score * (1.0 + overlap));
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final result = candidates.take(maxResults).map((s) {
      s.entry.retrievalCount++;
      return s.entry;
    }).toList();

    _logger.debug(
        'Retrieve "${_trunc(query)}" → ${result.length} hit(s) '
        '(candidates: ${candidateIds.length})');

    return result;
  }

  /// Returns memories for a specific goal, sorted newest-first.
  List<AgentMemoryEntry> forGoal(String goalId) =>
      _entries.where((e) => e.goalId == goalId).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  /// Returns memories for a specific task.
  List<AgentMemoryEntry> forTask(String taskId) =>
      _entries.where((e) => e.taskId == taskId).toList();

  /// Returns all goal-completion summaries for learning from past runs.
  List<AgentMemoryEntry> get completedGoals =>
      UnmodifiableListView(_goalArchive.values.expand((v) => v).toList());

  /// Produces a compact multi-line summary of the most recent [maxEntries]
  /// entries, suitable for injection into an LLM prompt.
  String summarise({int maxEntries = 15, String? goalId}) {
    final pool = goalId != null ? forGoal(goalId) : List.of(_entries);
    pool.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final slice = pool.take(maxEntries).toList();

    if (slice.isEmpty) return '(No memories recorded yet.)';

    final buf = StringBuffer();
    for (final e in slice) {
      final ts = _fmtTime(e.timestamp);
      buf.writeln('[${e.type.name.toUpperCase()}][$ts] ${e.content}');
    }
    return buf.toString().trimRight();
  }

  /// Boosts the importance of an entry (e.g. when the user flags it useful).
  void reinforce(String entryId, {double amount = 0.15}) {
    final entry = _entries.cast<AgentMemoryEntry?>().firstWhere(
          (e) => e?.id == entryId,
          orElse: () => null,
        );
    if (entry == null) return;
    entry.importance = (entry.importance + amount).clamp(0.0, 1.0);
    _logger.debug('Entry $entryId reinforced → ${entry.importance}');
  }

  /// Clears all entries (used for testing or full reset).
  void clear() {
    _entries.clear();
    _index.clear();
    _goalArchive.clear();
  }

  /// Statistics snapshot.
  Map<String, int> get stats => {
        'total': _entries.length,
        'goals_archived': _goalArchive.length,
        'index_tokens': _index.length,
        for (final t in AgentMemoryType.values)
          t.name: _entries.where((e) => e.type == t).length,
      };

  // ── Private helpers ─────────────────────────

  void _indexEntry(AgentMemoryEntry entry) {
    for (final token in _tokenise(entry.content)) {
      _index.putIfAbsent(token, () => {}).add(entry.id);
    }
  }

  List<AgentMemoryEntry> _topByScore(
    int n, {
    AgentMemoryType? filterType,
    String? filterGoalId,
  }) {
    final pool = _entries
        .where((e) =>
            (filterType == null || e.type == filterType) &&
            (filterGoalId == null || e.goalId == filterGoalId))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return pool.take(n).toList();
  }

  /// Evict the [capacity ~/ 10] lowest-scoring entries.
  void _evict() {
    final toRemove = (_entries.length - capacity).clamp(1, capacity ~/ 10);
    _entries.sort((a, b) => a.score.compareTo(b.score));
    final removed = _entries.sublist(0, toRemove);
    _entries.removeRange(0, toRemove);

    // Clean up index
    for (final e in removed) {
      for (final token in _tokenise(e.content)) {
        _index[token]?.remove(e.id);
      }
    }
    _logger.debug('Evicted $toRemove low-score entries (cap: $capacity)');
  }

  Set<String> _tokenise(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((t) => t.length > 2)
      .toSet();

  double _overlapScore(Set<String> queryTokens, Set<String> entryTokens) {
    if (queryTokens.isEmpty || entryTokens.isEmpty) return 0.0;
    final intersection = queryTokens.intersection(entryTokens).length;
    return intersection / queryTokens.length;
  }

  String _fmtTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';

  String _trunc(String s, [int n = 60]) =>
      s.length > n ? '${s.substring(0, n - 3)}...' : s;

  @override
  String toString() => 'AgentMemoryStore(size: $size, cap: $capacity)';
}

// ─────────────────────────────────────────────
// _ScoredEntry (private helper)
// ─────────────────────────────────────────────

class _ScoredEntry {
  const _ScoredEntry({required this.entry, required this.score});
  final AgentMemoryEntry entry;
  final double score;
}
