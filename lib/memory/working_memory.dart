// lib/memory/working_memory.dart
// Working Memory — the short-term active buffer.
//
// Working memory (Baddeley & Hitch, 1974) is the cognitive workspace
// for temporary information holding and manipulation.  It has:
//   • Very limited capacity (4 ± 1 chunks, Cowan 2001)
//   • Rapid decay (seconds to minutes without rehearsal)
//   • Central executive coordinating phonological loop / visuospatial sketch-pad

import 'dart:collection';

import 'package:consciousness_sim/core/models.dart';
import 'package:consciousness_sim/utils/logger.dart';

// ─────────────────────────────────────────────
// WorkingMemorySlot
// ─────────────────────────────────────────────

class _WorkingSlot {
  _WorkingSlot({required this.memory, required this.enteredAt});

  final Memory memory;
  final DateTime enteredAt;

  Duration get age => DateTime.now().difference(enteredAt);

  bool isExpired(Duration maxAge) => age > maxAge;
}

// ─────────────────────────────────────────────
// WorkingMemory
// ─────────────────────────────────────────────

/// A fixed-size, time-limited short-term memory buffer.
///
/// Items are stored in a circular queue.  The oldest item is displaced
/// when capacity is exceeded.  Items also expire after [maxItemAge].
class WorkingMemory {
  WorkingMemory({
    this.capacity = 4,
    this.maxItemAge = const Duration(minutes: 5),
    ConsciousnessLogger? logger,
  })  : assert(capacity >= 1 && capacity <= 20),
        _logger = logger ?? ConsciousnessLogger('WorkingMemory');

  final int capacity;
  final Duration maxItemAge;
  final ConsciousnessLogger _logger;

  final Queue<_WorkingSlot> _queue = Queue();

  // ── Public API ─────────────────────────────

  /// Number of items currently in working memory.
  int get size => _queue.length;

  /// True when working memory is full.
  bool get isFull => _queue.length >= capacity;

  /// True when working memory is empty.
  bool get isEmpty => _queue.isEmpty;

  /// Pushes a [memory] into the buffer.
  ///
  /// If at capacity the oldest item is displaced (circular queue).
  void push(Memory memory) {
    _pruneExpired();

    if (_queue.length >= capacity) {
      final displaced = _queue.removeFirst();
      _logger.debug(
          'WM displaced: "${_trunc(displaced.memory.content)}"');
    }

    _queue.addLast(_WorkingSlot(
      memory: memory,
      enteredAt: DateTime.now(),
    ));

    _logger.debug(
        'WM push: "${_trunc(memory.content)}" '
        '(size: ${_queue.length}/$capacity)');
  }

  /// Returns the most recently added [Memory], or null if empty.
  Memory? peek() {
    _pruneExpired();
    return _queue.isEmpty ? null : _queue.last.memory;
  }

  /// Removes and returns the most recently added [Memory] (LIFO pop).
  Memory? pop() {
    _pruneExpired();
    if (_queue.isEmpty) return null;
    return _queue.removeLast().memory;
  }

  /// Returns all current items in recency order (most recent first).
  List<Memory> getAll() {
    _pruneExpired();
    return _queue.map((s) => s.memory).toList().reversed.toList();
  }

  /// Searches working memory for items containing [query] tokens.
  List<Memory> search(String query) {
    _pruneExpired();
    final tokens = _tokenise(query);
    return _queue
        .map((s) => s.memory)
        .where((m) {
          final mTokens = _tokenise(m.content);
          return mTokens.intersection(tokens).isNotEmpty;
        })
        .toList()
        .reversed
        .toList();
  }

  /// "Rehearses" a memory, resetting its age timer (preventing decay).
  void rehearse(String memoryId) {
    final items = _queue.toList();
    _queue.clear();
    for (final slot in items) {
      if (slot.memory.id == memoryId) {
        _queue.addLast(_WorkingSlot(
          memory: slot.memory,
          enteredAt: DateTime.now(),
        ));
      } else {
        _queue.addLast(slot);
      }
    }
    _logger.debug('Rehearsed memory: $memoryId');
  }

  /// Removes a specific item from working memory.
  void remove(String memoryId) {
    _queue.removeWhere((s) => s.memory.id == memoryId);
  }

  /// Clears all working memory items.
  void clear() {
    _queue.clear();
    _logger.debug('Working memory cleared');
  }

  /// Returns how long the oldest item has been in working memory.
  Duration get oldestItemAge =>
      _queue.isEmpty ? Duration.zero : _queue.first.age;

  // ── Private helpers ─────────────────────────

  void _pruneExpired() {
    final before = _queue.length;
    _queue.removeWhere((s) => s.isExpired(maxItemAge));
    final pruned = before - _queue.length;
    if (pruned > 0) {
      _logger.debug('WM pruned $pruned expired item(s)');
    }
  }

  Set<String> _tokenise(String text) => text
      .toLowerCase()
      .split(RegExp(r'[\s,;.!?]+'))
      .where((t) => t.length > 1)
      .toSet();

  String _trunc(String s, [int n = 40]) =>
      s.length > n ? '${s.substring(0, n - 3)}...' : s;

  @override
  String toString() =>
      'WorkingMemory(size: $size/$capacity, maxAge: $maxItemAge)';
}
