// lib/core/workspace.dart
// Global Workspace Manager — the central "broadcast medium" of consciousness.
//
// Based on Bernard Baars' Global Workspace Theory (1988):
// The workspace is a limited-capacity "theatre" where specialised processors
// compete and cooperate. Only the most salient information is broadcast to
// all other processors simultaneously, creating the experience of awareness.

import 'dart:math' as math;

import 'package:consciousness_sim/core/models.dart';
import 'package:consciousness_sim/utils/logger.dart';

/// Manages the Global Workspace — the central broadcast medium.
///
/// Key constraints (mirroring cognitive science findings):
/// - Capacity limited to [capacity] concepts (default 7 ± 2, Miller 1956).
/// - Concepts decay in activation if not reinforced.
/// - The most salient concept always wins the "spotlight".
class WorkspaceManager {
  WorkspaceManager({
    this.capacity = 7,
    double decayRate = 0.05,
    ConsciousnessLogger? logger,
  })  : assert(capacity > 0 && capacity <= 20,
            'Workspace capacity must be between 1 and 20'),
        assert(decayRate >= 0.0 && decayRate <= 1.0,
            'Decay rate must be in [0, 1]'),
        _decayRate = decayRate,
        _logger = logger ?? ConsciousnessLogger('WorkspaceManager');

  // ── Configuration ─────────────────────────
  /// Maximum number of concepts held simultaneously (Miller's 7 ± 2).
  final int capacity;

  final double _decayRate;
  final ConsciousnessLogger _logger;

  // ── State ──────────────────────────────────
  final List<Concept> _buffer = [];
  final Map<String, double> _activationLevels = {};

  /// Timestamp of last full decay pass.
  DateTime _lastDecayPass = DateTime.now();

  // ── Public API ─────────────────────────────

  /// Broadcasts a [concept] into the global workspace.
  ///
  /// If the workspace is at capacity the least salient concept is evicted
  /// to make room (winner-takes-most dynamics).
  void broadcast(Concept concept) {
    _applyDecayIfNeeded();

    if (_buffer.any((c) => c.id == concept.id)) {
      // Re-activate existing concept
      _reinforceConcept(concept.id, 0.15);
      _logger.debug('Reinforced existing concept: "${concept.content}"');
      return;
    }

    if (_buffer.length >= capacity) {
      _evictLeastSalient();
    }

    final activated = concept.copyWith(
      activationLevel: math.min(1.0, concept.activationLevel + 0.1),
    );
    _buffer.add(activated);
    _activationLevels[activated.id] = activated.activationLevel;

    _logger.info(
        'Broadcast concept: "${activated.content}" '
        '(activation: ${activated.activationLevel.toStringAsFixed(2)})');
  }

  /// Suppresses and removes a concept from the workspace.
  void suppress(String conceptId) {
    _buffer.removeWhere((c) => c.id == conceptId);
    _activationLevels.remove(conceptId);
    _logger.debug('Suppressed concept: $conceptId');
  }

  /// Returns the currently active concepts, sorted by salience descending.
  List<Concept> getActiveWorkspace() {
    _applyDecayIfNeeded();
    return List.unmodifiable(
      _buffer..sort((a, b) => b.calculateSalience().compareTo(a.calculateSalience())),
    );
  }

  /// Returns the concept with the highest salience — the "spotlight" focus.
  Concept? getSpotlightFocus() {
    if (_buffer.isEmpty) return null;
    return _buffer.reduce(
      (a, b) => a.calculateSalience() >= b.calculateSalience() ? a : b,
    );
  }

  /// Computes pairwise interaction strengths between active concepts.
  ///
  /// Two concepts interact strongly when they share related concept IDs or
  /// when they co-occur in the workspace. Returns a map of
  /// `"conceptId1|conceptId2"` → strength.
  Map<String, double> computeInteractions() {
    final interactions = <String, double>{};
    final active = getActiveWorkspace();

    for (var i = 0; i < active.length; i++) {
      for (var j = i + 1; j < active.length; j++) {
        final a = active[i];
        final b = active[j];

        // Co-occurrence base strength
        var strength = (a.activationLevel + b.activationLevel) / 2;

        // Boost if they are explicitly related
        if (a.relatedConceptIds.contains(b.id) ||
            b.relatedConceptIds.contains(a.id)) {
          strength = math.min(1.0, strength + 0.25);
        }

        // Semantic similarity via embedding if available
        if (a.embedding != null && b.embedding != null) {
          final sim = a.embedding!.cosineSimilarity(b.embedding!);
          strength = math.min(1.0, strength + sim * 0.15);
        }

        interactions['${a.id}|${b.id}'] = strength;
      }
    }
    return interactions;
  }

  /// Computes the overall coherence of the current workspace.
  ///
  /// Coherence is high when concepts are strongly related to each other.
  double computeCoherence() {
    if (_buffer.length < 2) return 1.0;
    final interactions = computeInteractions();
    if (interactions.isEmpty) return 0.5;
    final avgStrength =
        interactions.values.reduce((a, b) => a + b) / interactions.length;
    return avgStrength.clamp(0.0, 1.0);
  }

  /// Returns a snapshot map: conceptId → activation level.
  Map<String, double> get activationSnapshot =>
      Map.unmodifiable(_activationLevels);

  /// Whether the workspace contains a concept with the given ID.
  bool contains(String conceptId) =>
      _buffer.any((c) => c.id == conceptId);

  /// Number of concepts currently in the workspace.
  int get size => _buffer.length;

  /// True if the workspace is at maximum capacity.
  bool get isFull => _buffer.length >= capacity;

  /// Clears the entire workspace (global reset).
  void clear() {
    _buffer.clear();
    _activationLevels.clear();
    _logger.info('Workspace cleared');
  }

  // ── Private helpers ────────────────────────

  void _reinforceConcept(String conceptId, double amount) {
    final idx = _buffer.indexWhere((c) => c.id == conceptId);
    if (idx == -1) return;
    final concept = _buffer[idx];
    final newLevel = math.min(1.0, concept.activationLevel + amount);
    _buffer[idx] = concept.copyWith(activationLevel: newLevel);
    _activationLevels[conceptId] = newLevel;
  }

  void _evictLeastSalient() {
    if (_buffer.isEmpty) return;
    final victim = _buffer.reduce(
      (a, b) => a.calculateSalience() <= b.calculateSalience() ? a : b,
    );
    _logger.debug(
        'Evicting least salient: "${victim.content}" '
        '(salience: ${victim.calculateSalience().toStringAsFixed(2)})');
    suppress(victim.id);
  }

  void _applyDecayIfNeeded() {
    final now = DateTime.now();
    final elapsed =
        now.difference(_lastDecayPass).inMilliseconds / 1000.0; // seconds
    if (elapsed < 1.0) return; // throttle to once per second

    final toRemove = <String>[];
    for (var i = 0; i < _buffer.length; i++) {
      final concept = _buffer[i];
      final decayed =
          concept.activationLevel * math.exp(-_decayRate * elapsed);
      if (decayed < 0.05) {
        toRemove.add(concept.id);
      } else {
        _buffer[i] = concept.copyWith(activationLevel: decayed);
        _activationLevels[concept.id] = decayed;
      }
    }
    for (final id in toRemove) {
      suppress(id);
    }
    _lastDecayPass = now;
  }

  @override
  String toString() =>
      'WorkspaceManager(size: $size/$capacity, '
      'coherence: ${computeCoherence().toStringAsFixed(2)})';
}
