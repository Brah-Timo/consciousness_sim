// lib/perception/perception_buffer.dart
// Perception Buffer — pre-attentive sensory register.
//
// Modelled on the iconic memory (Sperling, 1960) and echoic memory concepts:
// a brief, high-capacity store that holds raw sensory impressions for a very
// short time before they are either selected for attention or lost.

import 'dart:collection';

import 'package:consciousness_sim/core/models.dart';
import 'package:consciousness_sim/utils/logger.dart';

// ─────────────────────────────────────────────
// PerceptionBuffer
// ─────────────────────────────────────────────

/// A short-lived, high-capacity pre-attentive buffer.
///
/// Raw [Perception] objects flow in here and are held for [retentionDuration].
/// The attention spotlight then selects which perceptions propagate further
/// into the global workspace.  Unattended perceptions decay and are lost.
class PerceptionBuffer {
  PerceptionBuffer({
    this.capacity = 50,
    this.retentionDuration = const Duration(seconds: 3),
    ConsciousnessLogger? logger,
  })  : assert(capacity > 0),
        _logger = logger ?? ConsciousnessLogger('PerceptionBuffer');

  final int capacity;

  /// How long a perception survives without being processed.
  final Duration retentionDuration;

  final ConsciousnessLogger _logger;
  final Queue<_BufferedPercept> _buffer = Queue();

  // ── Statistics ─────────────────────────────

  int _totalAdded = 0;
  int _totalDropped = 0;

  int get totalAdded => _totalAdded;
  int get totalDropped => _totalDropped;
  int get currentSize => _buffer.length;

  // ── Public API ─────────────────────────────

  /// Adds a [Perception] to the buffer.
  ///
  /// If the buffer is at capacity, the oldest perception is displaced.
  void add(Perception perception) {
    _pruneExpired();

    if (_buffer.length >= capacity) {
      final dropped = _buffer.removeFirst();
      _totalDropped++;
      _logger.debug(
          'Buffer overflow — dropped: '
          '"${_trunc(dropped.perception.rawInput)}"');
    }

    _buffer.addLast(_BufferedPercept(
      perception: perception,
      arrivedAt: DateTime.now(),
    ));
    _totalAdded++;

    _logger.debug(
        'Buffered [${perception.modality.name}]: '
        '"${_trunc(perception.rawInput)}" '
        '(buffer: ${_buffer.length}/$capacity)');
  }

  /// Adds multiple perceptions at once.
  void addAll(Iterable<Perception> perceptions) {
    for (final p in perceptions) {
      add(p);
    }
  }

  /// Drains and returns all non-expired perceptions.
  ///
  /// The buffer is emptied after this call.
  List<Perception> drain() {
    _pruneExpired();
    final result = _buffer.map((b) => b.perception).toList();
    _buffer.clear();
    _logger.debug('Drained ${result.length} perception(s)');
    return result;
  }

  /// Peeks at all current perceptions without removing them.
  List<Perception> peek() {
    _pruneExpired();
    return _buffer.map((b) => b.perception).toList();
  }

  /// Drains only perceptions of a specific [modality].
  List<Perception> drainByModality(PerceptionModality modality) {
    _pruneExpired();
    final matching = _buffer
        .where((b) => b.perception.modality == modality)
        .map((b) => b.perception)
        .toList();
    _buffer.removeWhere((b) => b.perception.modality == modality);
    return matching;
  }

  /// Returns how many perceptions are of each modality.
  Map<PerceptionModality, int> get modalityDistribution {
    final dist = <PerceptionModality, int>{};
    for (final b in _buffer) {
      dist[b.perception.modality] =
          (dist[b.perception.modality] ?? 0) + 1;
    }
    return dist;
  }

  /// True when the buffer has pending perceptions.
  bool get hasPending {
    _pruneExpired();
    return _buffer.isNotEmpty;
  }

  /// Clears the entire buffer (drop everything).
  void clear() {
    _totalDropped += _buffer.length;
    _buffer.clear();
    _logger.debug('Perception buffer cleared');
  }

  // ── Private helpers ─────────────────────────

  void _pruneExpired() {
    final cutoff = DateTime.now().subtract(retentionDuration);
    var pruned = 0;
    while (_buffer.isNotEmpty &&
        _buffer.first.arrivedAt.isBefore(cutoff)) {
      _buffer.removeFirst();
      _totalDropped++;
      pruned++;
    }
    if (pruned > 0) {
      _logger.debug('Pruned $pruned expired perception(s)');
    }
  }

  String _trunc(String s, [int n = 40]) =>
      s.length > n ? '${s.substring(0, n - 3)}...' : s;

  @override
  String toString() =>
      'PerceptionBuffer(size: ${_buffer.length}/$capacity, '
      'added: $_totalAdded, dropped: $_totalDropped)';
}

// ─────────────────────────────────────────────
// Internal helper
// ─────────────────────────────────────────────

class _BufferedPercept {
  const _BufferedPercept({
    required this.perception,
    required this.arrivedAt,
  });

  final Perception perception;
  final DateTime arrivedAt;
}
