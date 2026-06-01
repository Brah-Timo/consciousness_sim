// lib/core/models.dart
// Core data models shared across the consciousness_sim package.

import 'dart:math' as math;

// ─────────────────────────────────────────────
// Enumerations
// ─────────────────────────────────────────────

/// The modality through which a perception was received.
enum PerceptionModality {
  visual,
  auditory,
  tactile,
  olfactory,
  gustatory,
  proprioceptive,
  interoceptive,
  linguistic,
  abstract,
}

/// The nature of the relationship between two concepts.
enum RelationshipType {
  causal,       // A causes B
  temporal,     // A precedes B
  spatial,      // A is located near B
  categorical,  // A is a type of B
  property,     // A has property B
  sequential,   // A follows B in sequence
  associative,  // A is generally associated with B
  oppositional, // A is the opposite of B
  instrumental, // A is used for B
  partOf,       // A is part of B
}

/// The type of memory storage.
enum MemoryType {
  episodic,   // Specific events/experiences
  semantic,   // General facts/knowledge
  working,    // Short-term active buffer
  procedural, // How-to knowledge
}

/// The emotional valence of a concept or experience.
enum EmotionalValence {
  veryPositive,
  positive,
  neutral,
  negative,
  veryNegative,
}

// ─────────────────────────────────────────────
// Core Value Objects
// ─────────────────────────────────────────────

/// Immutable vector for semantic embeddings.
class SemanticVector {
  const SemanticVector(this.dimensions);

  final List<double> dimensions;

  int get length => dimensions.length;

  /// Cosine similarity between two vectors (0.0 – 1.0).
  double cosineSimilarity(SemanticVector other) {
    assert(dimensions.length == other.dimensions.length,
        'Vector dimensions must match');
    var dot = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    for (var i = 0; i < dimensions.length; i++) {
      dot += dimensions[i] * other.dimensions[i];
      normA += dimensions[i] * dimensions[i];
      normB += other.dimensions[i] * other.dimensions[i];
    }
    final denom = math.sqrt(normA) * math.sqrt(normB);
    return denom == 0 ? 0.0 : (dot / denom).clamp(0.0, 1.0);
  }

  /// Euclidean distance to another vector.
  double euclideanDistance(SemanticVector other) {
    assert(dimensions.length == other.dimensions.length,
        'Vector dimensions must match');
    var sum = 0.0;
    for (var i = 0; i < dimensions.length; i++) {
      final diff = dimensions[i] - other.dimensions[i];
      sum += diff * diff;
    }
    return math.sqrt(sum);
  }

  @override
  String toString() =>
      'SemanticVector(${dimensions.length}d, mag=${magnitude.toStringAsFixed(3)})';

  double get magnitude => math.sqrt(
        dimensions.fold(0.0, (prev, d) => prev + d * d),
      );
}

// ─────────────────────────────────────────────
// Concept
// ─────────────────────────────────────────────

/// A fundamental unit of knowledge or perception in the consciousness system.
///
/// Concepts are the atoms from which thoughts are built. Each concept carries
/// its own activation level, emotional weight, and semantic relationships.
class Concept {
  Concept({
    required this.id,
    required this.content,
    double activationLevel = 0.5,
    DateTime? creationTime,
    List<String>? relatedConceptIds,
    Map<String, dynamic>? properties,
    SemanticVector? embedding,
    this.emotionalValence = EmotionalValence.neutral,
    this.emotionalIntensity = 0.0,
    this.modality = PerceptionModality.abstract,
    this.familiarity = 0.5,
    this.contextualRelevance = 0.5,
  })  : assert(activationLevel >= 0.0 && activationLevel <= 1.0,
            'activationLevel must be in [0, 1]'),
        assert(emotionalIntensity >= 0.0 && emotionalIntensity <= 1.0,
            'emotionalIntensity must be in [0, 1]'),
        assert(familiarity >= 0.0 && familiarity <= 1.0,
            'familiarity must be in [0, 1]'),
        assert(contextualRelevance >= 0.0 && contextualRelevance <= 1.0,
            'contextualRelevance must be in [0, 1]'),
        activationLevel = activationLevel,
        creationTime = creationTime ?? DateTime.now(),
        relatedConceptIds = relatedConceptIds ?? const [],
        properties = properties ?? const {},
        embedding = embedding;

  /// Globally unique identifier for this concept.
  final String id;

  /// Human-readable content / label.
  final String content;

  /// Current activation level in the global workspace (0.0 – 1.0).
  double activationLevel;

  /// When this concept was first created / observed.
  final DateTime creationTime;

  /// Last time this concept was activated.
  DateTime lastActivated = DateTime.now();

  /// IDs of concepts that are semantically or causally linked.
  final List<String> relatedConceptIds;

  /// Arbitrary key-value properties (e.g. colour, size, speed).
  final Map<String, dynamic> properties;

  /// Optional high-dimensional semantic embedding.
  final SemanticVector? embedding;

  /// Emotional valence associated with this concept.
  final EmotionalValence emotionalValence;

  /// Strength of the emotional charge (0.0 = flat, 1.0 = intense).
  final double emotionalIntensity;

  /// Primary sensory channel through which this concept was acquired.
  final PerceptionModality modality;

  /// How familiar this concept is (0.0 = brand new, 1.0 = very familiar).
  double familiarity;

  /// How relevant this concept is to the current context.
  double contextualRelevance;

  /// Access count — used to compute familiarity and importance.
  int accessCount = 0;

  // ── Derived computations ───────────────────

  /// Recency score: higher for recently created/activated concepts.
  double get recencyScore {
    final age = DateTime.now().difference(lastActivated);
    // Decay half-life ≈ 60 seconds
    return math.exp(-age.inMilliseconds / 60000.0).clamp(0.0, 1.0);
  }

  /// Novelty: inverse of familiarity.
  double get noveltyScore => (1.0 - familiarity).clamp(0.0, 1.0);

  /// Emotional weight contribution.
  double get emotionalWeight {
    final valenceMultiplier = switch (emotionalValence) {
      EmotionalValence.veryPositive => 1.0,
      EmotionalValence.positive => 0.7,
      EmotionalValence.neutral => 0.1,
      EmotionalValence.negative => 0.8,
      EmotionalValence.veryNegative => 1.0,
    };
    return emotionalIntensity * valenceMultiplier;
  }

  /// Composite salience score used by the attention spotlight.
  ///
  /// Formula (inspired by Baars' GWT):
  ///   S = (activation × 0.30) + (novelty × 0.20) + (relevance × 0.25) +
  ///       (recency   × 0.15) + (emotion × 0.10)
  double calculateSalience() =>
      (activationLevel * 0.30) +
      (noveltyScore * 0.20) +
      (contextualRelevance * 0.25) +
      (recencyScore * 0.15) +
      (emotionalWeight * 0.10);

  /// Returns a copy of this concept with updated fields.
  Concept copyWith({
    double? activationLevel,
    double? familiarity,
    double? contextualRelevance,
    List<String>? relatedConceptIds,
    Map<String, dynamic>? properties,
  }) =>
      Concept(
        id: id,
        content: content,
        activationLevel: activationLevel ?? this.activationLevel,
        creationTime: creationTime,
        relatedConceptIds: relatedConceptIds ?? this.relatedConceptIds,
        properties: properties ?? this.properties,
        embedding: embedding,
        emotionalValence: emotionalValence,
        emotionalIntensity: emotionalIntensity,
        modality: modality,
        familiarity: familiarity ?? this.familiarity,
        contextualRelevance: contextualRelevance ?? this.contextualRelevance,
      );

  @override
  String toString() =>
      'Concept(id: $id, content: "$content", '
      'activation: ${activationLevel.toStringAsFixed(2)}, '
      'salience: ${calculateSalience().toStringAsFixed(2)})';
}

// ─────────────────────────────────────────────
// ConceptNode — graph node wrapper
// ─────────────────────────────────────────────

/// A node in the [ConceptualGraph] holding a concept plus edge metadata.
class ConceptNode {
  ConceptNode({required this.concept});

  final Concept concept;

  /// outgoing edges: targetId → [ConceptEdge]
  final Map<String, ConceptEdge> edges = {};

  String get id => concept.id;

  void addEdge(ConceptEdge edge) => edges[edge.targetId] = edge;

  @override
  String toString() =>
      'ConceptNode(${concept.id}, edges: ${edges.length})';
}

// ─────────────────────────────────────────────
// ConceptEdge — directed relationship
// ─────────────────────────────────────────────

/// A directed, weighted relationship between two concepts.
class ConceptEdge {
  const ConceptEdge({
    required this.sourceId,
    required this.targetId,
    required this.relationshipType,
    required this.strength,
    this.label = '',
  })  : assert(strength >= 0.0 && strength <= 1.0,
            'Edge strength must be in [0, 1]');

  final String sourceId;
  final String targetId;
  final RelationshipType relationshipType;

  /// Connection strength (0.0 = weak, 1.0 = very strong).
  final double strength;

  /// Human-readable label for the relationship.
  final String label;

  ConceptEdge copyWith({double? strength}) => ConceptEdge(
        sourceId: sourceId,
        targetId: targetId,
        relationshipType: relationshipType,
        strength: strength ?? this.strength,
        label: label,
      );

  @override
  String toString() =>
      'Edge($sourceId → $targetId, '
      '${relationshipType.name}, strength: ${strength.toStringAsFixed(2)})';
}

// ─────────────────────────────────────────────
// Memory
// ─────────────────────────────────────────────

/// A stored memory unit — either episodic (event) or semantic (fact).
class Memory {
  Memory({
    required this.id,
    required this.content,
    required this.type,
    DateTime? timestamp,
    this.emotionalValence = EmotionalValence.neutral,
    this.emotionalIntensity = 0.0,
    double strength = 1.0,
    List<String>? associatedConceptIds,
    Map<String, dynamic>? context,
  })  : timestamp = timestamp ?? DateTime.now(),
        strength = strength,
        associatedConceptIds = associatedConceptIds ?? const [],
        context = context ?? const {};

  final String id;
  final String content;
  final MemoryType type;
  final DateTime timestamp;
  final EmotionalValence emotionalValence;
  final double emotionalIntensity;

  /// Memory strength / vividness (decays over time unless reinforced).
  double strength;

  /// Concepts that were active when this memory was formed.
  final List<String> associatedConceptIds;

  /// Contextual metadata (location, time-of-day, mood, etc.).
  final Map<String, dynamic> context;

  /// How many times this memory has been recalled.
  int recallCount = 0;

  /// Apply temporal decay to the memory strength.
  ///
  /// Uses Ebbinghaus forgetting curve: S(t) = S₀ × e^(−t/τ)
  void applyDecay({double halfLifeHours = 24.0}) {
    final ageHours =
        DateTime.now().difference(timestamp).inMinutes / 60.0;
    final tau = halfLifeHours / math.log(2);
    strength = (strength * math.exp(-ageHours / tau)).clamp(0.0, 1.0);
  }

  /// Reinforce the memory, increasing its strength.
  void reinforce({double amount = 0.2}) {
    strength = (strength + amount).clamp(0.0, 1.0);
    recallCount++;
  }

  @override
  String toString() =>
      'Memory(id: $id, type: ${type.name}, '
      'strength: ${strength.toStringAsFixed(2)}, '
      'content: "$content")';
}

// ─────────────────────────────────────────────
// Inference
// ─────────────────────────────────────────────

/// An inference derived by the [InferenceEngine].
class Inference {
  const Inference({
    required this.id,
    required this.conclusion,
    required this.premises,
    required this.confidence,
    required this.inferenceType,
    DateTime? generatedAt,
  })  : assert(confidence >= 0.0 && confidence <= 1.0),
        generatedAt = generatedAt;

  final String id;
  final String conclusion;
  final List<String> premises;

  /// How confident the system is in this inference (0.0 – 1.0).
  final double confidence;
  final String inferenceType;
  final DateTime? generatedAt;

  @override
  String toString() =>
      'Inference(conclusion: "$conclusion", '
      'confidence: ${confidence.toStringAsFixed(2)}, '
      'type: $inferenceType)';
}

// ─────────────────────────────────────────────
// Perception
// ─────────────────────────────────────────────

/// Raw sensory input after initial processing.
class Perception {
  Perception({
    required this.id,
    required this.rawInput,
    required this.modality,
    DateTime? timestamp,
    double confidence = 1.0,
    Map<String, dynamic>? features,
  })  : assert(confidence >= 0.0 && confidence <= 1.0),
        timestamp = timestamp ?? DateTime.now(),
        confidence = confidence,
        features = features ?? const {};

  final String id;
  final String rawInput;
  final PerceptionModality modality;
  final DateTime timestamp;
  final double confidence;
  final Map<String, dynamic> features;

  /// Extracted semantic tokens from raw input.
  List<String> get tokens =>
      rawInput.toLowerCase().split(RegExp(r'[\s,;.!?]+'))
        ..removeWhere((t) => t.isEmpty);

  @override
  String toString() =>
      'Perception(modality: ${modality.name}, '
      'input: "$rawInput", confidence: ${confidence.toStringAsFixed(2)})';
}

// ─────────────────────────────────────────────
// InferenceRule
// ─────────────────────────────────────────────

/// A declarative rule used by the [InferenceEngine].
///
/// Rules follow the pattern:  IF [conditions] THEN [action/conclusion].
class InferenceRule {
  const InferenceRule({
    required this.id,
    required this.name,
    required this.conditions,
    required this.conclusion,
    this.weight = 1.0,
  }) : assert(weight >= 0.0 && weight <= 1.0);

  final String id;
  final String name;
  final List<String> conditions;  // Keywords that must be present
  final String conclusion;
  final double weight;

  /// Returns true if all conditions appear in the active context.
  bool matches(Set<String> activeTokens) =>
      conditions.every((c) => activeTokens.any(
            (t) => t.toLowerCase().contains(c.toLowerCase()),
          ));

  @override
  String toString() =>
      'Rule("$name": IF ${conditions.join(' AND ')} THEN "$conclusion")';
}

// ─────────────────────────────────────────────
// Pattern
// ─────────────────────────────────────────────

/// A recurring pattern discovered in the concept graph.
class Pattern {
  const Pattern({
    required this.id,
    required this.description,
    required this.involvedConceptIds,
    required this.confidence,
    this.occurrenceCount = 1,
  });

  final String id;
  final String description;
  final List<String> involvedConceptIds;
  final double confidence;
  final int occurrenceCount;

  @override
  String toString() =>
      'Pattern("$description", confidence: '
      '${confidence.toStringAsFixed(2)}, '
      'occurrences: $occurrenceCount)';
}

// ─────────────────────────────────────────────
// CausalRelationship
// ─────────────────────────────────────────────

/// A discovered causal link between two concepts.
class CausalRelationship {
  const CausalRelationship({
    required this.causeConceptId,
    required this.effectConceptId,
    required this.description,
    required this.strength,
    this.temporalGap = Duration.zero,
  }) : assert(strength >= 0.0 && strength <= 1.0);

  final String causeConceptId;
  final String effectConceptId;
  final String description;
  final double strength;
  final Duration temporalGap;

  @override
  String toString() =>
      'Causal($causeConceptId → $effectConceptId, '
      'strength: ${strength.toStringAsFixed(2)})';
}

// ─────────────────────────────────────────────
// ConsciousState — snapshot of the workspace
// ─────────────────────────────────────────────

/// A point-in-time snapshot of the global workspace state.
///
/// Think of this as a "frame" of consciousness — what the system
/// is currently aware of, focused on, and concluding.
class ConsciousState {
  ConsciousState({
    required this.workspace,
    required this.focusedConceptId,
    required this.activationMap,
    required this.inferencesGenerated,
    DateTime? timestamp,
    double coherence = 1.0,
  })  : assert(coherence >= 0.0 && coherence <= 1.0),
        timestamp = timestamp ?? DateTime.now(),
        coherence = coherence;

  /// The set of concepts currently in the global workspace.
  final List<Concept> workspace;

  /// The concept currently holding the attention spotlight.
  final String focusedConceptId;

  /// Activation levels for all concepts keyed by their ID.
  final Map<String, double> activationMap;

  /// All inferences generated in this processing cycle.
  final List<Inference> inferencesGenerated;

  /// When this state was captured.
  final DateTime timestamp;

  /// Internal consistency of the workspace (0.0 = chaotic, 1.0 = coherent).
  final double coherence;

  /// Convenience: the [Concept] currently in focus (may be null if workspace empty).
  Concept? get focusedConcept => workspace
      .cast<Concept?>()
      .firstWhere((c) => c?.id == focusedConceptId, orElse: () => null);

  /// Summary of the most salient conclusion in this state.
  String? get primaryConclusion => inferencesGenerated.isNotEmpty
      ? inferencesGenerated
          .reduce((a, b) => a.confidence >= b.confidence ? a : b)
          .conclusion
      : null;

  void snapshot() {
    // ignore: avoid_print
    print('''
╔══════════════════════════════════════════╗
║        CONSCIOUS STATE SNAPSHOT          ║
╠══════════════════════════════════════════╣
║ Timestamp : $timestamp
║ Focus     : $focusedConceptId
║ Coherence : ${(coherence * 100).toStringAsFixed(1)}%
╠══════════════════════════════════════════╣
║ Workspace (${workspace.length} concepts):
${workspace.map((c) => '║   • ${c.content} [${(c.activationLevel * 100).toStringAsFixed(0)}%]').join('\n')}
╠══════════════════════════════════════════╣
║ Inferences (${inferencesGenerated.length}):
${inferencesGenerated.map((i) => '║   → ${i.conclusion} [${(i.confidence * 100).toStringAsFixed(0)}%]').join('\n')}
╚══════════════════════════════════════════╝
''');
  }

  @override
  String toString() =>
      'ConsciousState(focus: $focusedConceptId, '
      'workspace: ${workspace.length} concepts, '
      'coherence: ${coherence.toStringAsFixed(2)}, '
      'inferences: ${inferencesGenerated.length})';
}
