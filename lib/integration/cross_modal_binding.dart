// lib/integration/cross_modal_binding.dart
// Cross-Modal Binding — unifies perceptions from different sensory channels.
//
// Addresses the "binding problem" across modalities: how does the mind
// combine a visual flash, an auditory bang, and a tactile shock into the
// unified percept of "lightning struck nearby"?
//
// Here we implement temporal coincidence + semantic coherence as the binding
// signal, mirroring gamma-oscillation synchrony theories in neuroscience.

import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import 'package:consciousness_sim/core/models.dart';
import 'package:consciousness_sim/utils/logger.dart';

// ─────────────────────────────────────────────
// MultiModalPercept
// ─────────────────────────────────────────────

/// A unified percept produced by binding perceptions from different modalities.
class MultiModalPercept {
  const MultiModalPercept({
    required this.id,
    required this.description,
    required this.componentPerceptionIds,
    required this.modalitiesInvolved,
    required this.bindingStrength,
    required this.unifiedConcept,
    required this.timestamp,
  });

  final String id;

  /// Natural-language description of the unified event.
  final String description;

  /// IDs of the [Perception] objects that were bound together.
  final List<String> componentPerceptionIds;

  /// Which modalities contributed.
  final Set<PerceptionModality> modalitiesInvolved;

  /// How strongly the cross-modal event is bound (0.0 – 1.0).
  final double bindingStrength;

  /// The synthesised [Concept] representing this multi-modal event.
  final Concept unifiedConcept;
  final DateTime timestamp;

  bool get isMultiModal => modalitiesInvolved.length > 1;

  @override
  String toString() =>
      'MultiModalPercept("$description", '
      'modalities: ${modalitiesInvolved.map((m) => m.name).join('+')}, '
      'strength: ${bindingStrength.toStringAsFixed(2)})';
}

// ─────────────────────────────────────────────
// CrossModalBinding
// ─────────────────────────────────────────────

/// Binds perceptions from multiple sensory channels into unified events.
///
/// ### Algorithm
/// 1. Collect incoming perceptions per modality.
/// 2. Detect temporal coincidence (within [temporalWindow]).
/// 3. Compute semantic coherence between concurrent perceptions.
/// 4. If coherence ≥ [bindingThreshold] → emit [MultiModalPercept].
class CrossModalBinding {
  CrossModalBinding({
    Duration temporalWindow = const Duration(milliseconds: 500),
    double bindingThreshold = 0.3,
    ConsciousnessLogger? logger,
  })  : _temporalWindow = temporalWindow,
        _bindingThreshold = bindingThreshold,
        _logger = logger ?? ConsciousnessLogger('CrossModalBinding');

  final Duration _temporalWindow;
  final double _bindingThreshold;
  final ConsciousnessLogger _logger;
  final _uuid = const Uuid();

  /// Incoming perceptions grouped by modality.
  final Map<PerceptionModality, List<_TimestampedPercept>> _buffers = {};

  /// All produced multi-modal percepts.
  final List<MultiModalPercept> _bound = [];

  // ── Public API ─────────────────────────────

  /// Registers an incoming [perception].
  ///
  /// Immediately attempts cross-modal binding with recent perceptions
  /// in the complementary modality buffers.
  List<MultiModalPercept> register(Perception perception) {
    _pruneExpired();

    final buffer = _buffers[perception.modality] ??= [];
    buffer.add(_TimestampedPercept(
      perception: perception,
      receivedAt: DateTime.now(),
    ));

    final newBindings = _attemptBinding(perception);
    if (newBindings.isNotEmpty) {
      _logger.info(
          'Cross-modal binding: ${newBindings.length} event(s) '
          'involving ${perception.modality.name}');
    }
    return newBindings;
  }

  /// Registers multiple perceptions and returns all bindings produced.
  List<MultiModalPercept> registerAll(List<Perception> perceptions) {
    final results = <MultiModalPercept>[];
    for (final p in perceptions) {
      results.addAll(register(p));
    }
    return results;
  }

  /// All multi-modal percepts produced so far.
  List<MultiModalPercept> get boundPercepts =>
      List.unmodifiable(_bound);

  /// Returns all percepts involving a specific combination of modalities.
  List<MultiModalPercept> getByModalities(
      Set<PerceptionModality> modalities) =>
      _bound
          .where((p) => p.modalitiesInvolved.containsAll(modalities))
          .toList();

  // ── Private implementation ─────────────────

  List<MultiModalPercept> _attemptBinding(Perception incoming) {
    final results = <MultiModalPercept>[];
    final now = DateTime.now();

    for (final entry in _buffers.entries) {
      if (entry.key == incoming.modality) continue;

      for (final candidate in entry.value) {
        final timeDelta = now.difference(candidate.receivedAt).abs();
        if (timeDelta > _temporalWindow) continue;

        final coherence = _computeCoherence(
          incoming,
          candidate.perception,
        );
        if (coherence < _bindingThreshold) continue;

        final mp = _synthesise(
          incoming,
          candidate.perception,
          coherence,
        );
        results.add(mp);
        _bound.add(mp);
      }
    }

    return results;
  }

  double _computeCoherence(Perception a, Perception b) {
    // Token overlap (Jaccard)
    final tA = a.tokens.toSet();
    final tB = b.tokens.toSet();
    if (tA.isEmpty || tB.isEmpty) return 0.0;

    final intersection = tA.intersection(tB).length.toDouble();
    final union = tA.union(tB).length.toDouble();
    final jaccard = intersection / union;

    // Temporal closeness bonus
    final age = DateTime.now().difference(a.timestamp).inMilliseconds;
    final recency = math.exp(-age / 1000.0).clamp(0.0, 1.0);

    return (jaccard * 0.7 + recency * 0.3).clamp(0.0, 1.0);
  }

  MultiModalPercept _synthesise(
    Perception primary,
    Perception secondary,
    double strength,
  ) {
    final description =
        '[${primary.modality.name} + ${secondary.modality.name}] '
        '"${primary.rawInput}" + "${secondary.rawInput}"';

    final unifiedContent =
        '${primary.rawInput} (also ${secondary.modality.name}: '
        '"${secondary.rawInput}")';

    final concept = Concept(
      id: _uuid.v4(),
      content: unifiedContent,
      activationLevel: math.min(1.0, strength + 0.1),
      modality: primary.modality, // Primary modality wins
      emotionalIntensity: 0.3,
      familiarity: 0.1,
      contextualRelevance: 0.7,
      properties: {
        'type': 'cross_modal',
        'primary_modality': primary.modality.name,
        'secondary_modality': secondary.modality.name,
        'binding_strength': strength,
      },
    );

    return MultiModalPercept(
      id: _uuid.v4(),
      description: description,
      componentPerceptionIds: [primary.id, secondary.id],
      modalitiesInvolved: {primary.modality, secondary.modality},
      bindingStrength: strength,
      unifiedConcept: concept,
      timestamp: DateTime.now(),
    );
  }

  void _pruneExpired() {
    final cutoff = DateTime.now().subtract(_temporalWindow * 3);
    for (final buffer in _buffers.values) {
      buffer.removeWhere((e) => e.receivedAt.isBefore(cutoff));
    }
  }
}

class _TimestampedPercept {
  const _TimestampedPercept({
    required this.perception,
    required this.receivedAt,
  });

  final Perception perception;
  final DateTime receivedAt;
}
