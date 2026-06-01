// lib/perception/sensory_input.dart
// SensoryInputProcessor — the full perceptual processing pipeline.
//
// Models the two-stage model of perception:
//   Stage 1 (pre-attentive): fast, parallel, automatic feature detection.
//   Stage 2 (attentive): slower, serial, resource-intensive feature binding.

import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import 'package:consciousness_sim/core/models.dart';
import 'package:consciousness_sim/perception/feature_extraction.dart';
import 'package:consciousness_sim/perception/perception_buffer.dart';
import 'package:consciousness_sim/utils/logger.dart';

// ─────────────────────────────────────────────
// SensoryInputProcessor
// ─────────────────────────────────────────────

/// Converts raw input strings into [Perception] objects and extracts
/// [Concept] instances suitable for the global workspace.
///
/// ### Pipeline
/// ```
/// raw input
///   ↓
/// PerceptionBuffer.add()         — brief sensory register
///   ↓
/// FeatureExtractor.extract()     — pre-attentive feature detection
///   ↓
/// _buildConcepts()               — concept instantiation
///   ↓
/// List<Concept>                  — ready for attention & workspace
/// ```
class SensoryInputProcessor {
  SensoryInputProcessor({
    ConsciousnessLogger? logger,
    PerceptionBuffer? buffer,
    FeatureExtractor? extractor,
  })  : _logger = logger ?? ConsciousnessLogger('SensoryInputProcessor'),
        _buffer = buffer ??
            PerceptionBuffer(
              capacity: 100,
              retentionDuration: const Duration(seconds: 10),
            ),
        _extractor = extractor ?? FeatureExtractor();

  final ConsciousnessLogger _logger;
  final PerceptionBuffer _buffer;
  final FeatureExtractor _extractor;

  // ── Public API ─────────────────────────────

  /// Processes a raw [input] string and returns a [Perception].
  ///
  /// This is Stage 1 of the perceptual pipeline.
  Perception process(
    String input, {
    required PerceptionModality modality,
    String? id,
    double confidence = 1.0,
    Map<String, dynamic>? contextData,
  }) {
    final features = _extractor.extract(input);
    final valence = _extractor.detectEmotionalValence(features.emotionalCues);
    final intensity = _extractor.estimateEmotionalIntensity(input);

    final featureMap = {
      ...features.toProperties(),
      'emotional_valence': valence.name,
      'emotional_intensity': intensity,
      if (contextData != null) ...contextData,
    };

    final perception = Perception(
      id: id ?? const Uuid().v4(),
      rawInput: input,
      modality: modality,
      confidence: confidence,
      features: featureMap,
    );

    _buffer.add(perception);

    _logger.debug(
        'Processed [${modality.name}]: "${_trunc(input)}" '
        '(entities: ${features.entities.length}, '
        'emotional: ${valence.name})');

    return perception;
  }

  /// Extracts a list of [Concept] objects from a [Perception].
  ///
  /// This is Stage 2 — produces workspace-ready concepts.
  List<Concept> extractConcepts(Perception perception, Uuid uuid) {
    final features = _extractor.extract(perception.rawInput);
    final valence = _extractor.detectEmotionalValence(features.emotionalCues);
    final intensity = _extractor.estimateEmotionalIntensity(
        perception.rawInput);

    final concepts = <Concept>[];

    // 1. Create one concept per salient entity
    for (final entity in features.entities.take(5)) {
      concepts.add(_buildConcept(
        id: uuid.v4(),
        content: entity,
        modality: perception.modality,
        valence: valence,
        intensity: intensity * 0.5, // Entities carry partial emotion
        familiarity: 0.3,
        properties: {'source': 'entity', 'from': perception.id},
      ));
    }

    // 2. Create one concept per significant action
    for (final action in features.actions.take(3)) {
      concepts.add(_buildConcept(
        id: uuid.v4(),
        content: action,
        modality: perception.modality,
        valence: EmotionalValence.neutral,
        intensity: 0.0,
        familiarity: 0.4,
        properties: {'source': 'action', 'from': perception.id},
      ));
    }

    // 3. Create one aggregate concept for the whole perception
    // (captures the gestalt)
    final shortInput = _trunc(perception.rawInput, 60);
    concepts.add(_buildConcept(
      id: uuid.v4(),
      content: shortInput,
      modality: perception.modality,
      valence: valence,
      intensity: intensity,
      familiarity: 0.2,
      properties: {
        'source': 'gestalt',
        'from': perception.id,
        'full_input': perception.rawInput,
        'is_question': features.questions,
        'has_negation': features.negations.isNotEmpty,
        'causal': features.causalCues.isNotEmpty,
        'spatial': features.spatialRelations,
        'temporal': features.temporalMarkers,
      },
    ));

    _logger.debug(
        'Extracted ${concepts.length} concept(s) from perception '
        '"${_trunc(perception.rawInput)}"');

    return concepts;
  }

  /// Processes a batch of raw inputs and returns all extracted concepts.
  List<Concept> processBatch(
    List<String> inputs,
    PerceptionModality modality,
    Uuid uuid,
  ) {
    final concepts = <Concept>[];
    for (final input in inputs) {
      final p = process(input, modality: modality, id: uuid.v4());
      concepts.addAll(extractConcepts(p, uuid));
    }
    return concepts;
  }

  /// Exposes the underlying buffer (for draining or peeking).
  PerceptionBuffer get buffer => _buffer;

  // ── Private helpers ─────────────────────────

  Concept _buildConcept({
    required String id,
    required String content,
    required PerceptionModality modality,
    required EmotionalValence valence,
    required double intensity,
    required double familiarity,
    required Map<String, dynamic> properties,
  }) {
    // Initial activation = confidence-weighted importance
    final activation = _estimateInitialActivation(content, valence, intensity);

    return Concept(
      id: id,
      content: content,
      activationLevel: activation,
      modality: modality,
      emotionalValence: valence,
      emotionalIntensity: intensity,
      familiarity: familiarity,
      contextualRelevance: 0.5, // Will be updated by memory lookup
      properties: Map.unmodifiable(properties),
    );
  }

  double _estimateInitialActivation(
    String content,
    EmotionalValence valence,
    double intensity,
  ) {
    var base = 0.5;

    // Longer / more specific content starts with higher activation
    final lengthFactor = math.min(1.0, content.split(' ').length / 5.0);
    base += lengthFactor * 0.1;

    // Emotional content boosts activation
    final emotionalBoost = switch (valence) {
      EmotionalValence.veryPositive => 0.2,
      EmotionalValence.positive => 0.1,
      EmotionalValence.neutral => 0.0,
      EmotionalValence.negative => 0.15,
      EmotionalValence.veryNegative => 0.25,
    };
    base += emotionalBoost + intensity * 0.1;

    return base.clamp(0.1, 0.95);
  }

  String _trunc(String s, [int n = 50]) =>
      s.length > n ? '${s.substring(0, n - 3)}...' : s;
}
