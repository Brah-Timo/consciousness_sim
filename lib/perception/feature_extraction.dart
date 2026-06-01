// lib/perception/feature_extraction.dart
// Feature Extractor — converts raw sensory input into structured features.
//
// In cognitive science, feature extraction (pre-attentive processing) occurs
// automatically and in parallel, before focused attention is applied.

import 'dart:math' as math;

import 'package:consciousness_sim/core/models.dart';
import 'package:consciousness_sim/utils/logger.dart';

// ─────────────────────────────────────────────
// ExtractedFeatures
// ─────────────────────────────────────────────

/// Structured output of the feature extraction pipeline.
class ExtractedFeatures {
  const ExtractedFeatures({
    required this.entities,
    required this.actions,
    required this.attributes,
    required this.spatialRelations,
    required this.temporalMarkers,
    required this.emotionalCues,
    required this.causalCues,
    required this.quantifiers,
    required this.negations,
    required this.questions,
  });

  /// Named entities (nouns, subjects, objects).
  final List<String> entities;

  /// Action verbs detected.
  final List<String> actions;

  /// Descriptive attributes (adjectives).
  final List<String> attributes;

  /// Spatial relationship words.
  final List<String> spatialRelations;

  /// Temporal markers.
  final List<String> temporalMarkers;

  /// Words carrying emotional weight.
  final List<String> emotionalCues;

  /// Causal connectives and cue words.
  final List<String> causalCues;

  /// Quantifiers and numerics.
  final List<String> quantifiers;

  /// Negation words.
  final List<String> negations;

  /// Whether the input appears to be a question.
  final bool questions;

  /// All extracted tokens merged.
  List<String> get allTokens => [
        ...entities,
        ...actions,
        ...attributes,
        ...spatialRelations,
        ...temporalMarkers,
      ];

  /// Converts features to a property map for [Concept].
  Map<String, dynamic> toProperties() => {
        'entities': entities,
        'actions': actions,
        'attributes': attributes,
        'spatial': spatialRelations,
        'temporal': temporalMarkers,
        'emotional': emotionalCues,
        'causal': causalCues,
        'negated': negations.isNotEmpty,
        'is_question': questions,
      };

  @override
  String toString() =>
      'Features(entities: $entities, actions: $actions, '
      'attributes: $attributes)';
}

// ─────────────────────────────────────────────
// FeatureExtractor
// ─────────────────────────────────────────────

/// Analyses raw text input and extracts structured linguistic features.
///
/// The extractor uses a lexicon-based approach with heuristic rules.
/// For production use, this can be replaced with a full NLP pipeline.
class FeatureExtractor {
  FeatureExtractor({
    ConsciousnessLogger? logger,
  }) : _logger = logger ?? ConsciousnessLogger('FeatureExtractor');

  final ConsciousnessLogger _logger;

  // ── Lexicons ───────────────────────────────

  static const _spatialWords = {
    'on', 'above', 'below', 'under', 'over', 'next to', 'beside',
    'near', 'far', 'left', 'right', 'front', 'behind', 'between',
    'inside', 'outside', 'around', 'through', 'across', 'along',
    'top', 'bottom', 'up', 'down', 'here', 'there',
  };

  static const _temporalWords = {
    'before', 'after', 'during', 'when', 'while', 'then', 'now',
    'later', 'earlier', 'soon', 'yesterday', 'today', 'tomorrow',
    'always', 'never', 'sometimes', 'often', 'rarely', 'already',
    'still', 'just', 'recently', 'since', 'until', 'once',
  };

  static const _emotionalWords = {
    'happy', 'sad', 'angry', 'afraid', 'scared', 'excited', 'calm',
    'worried', 'hungry', 'thirsty', 'tired', 'cold', 'hot', 'pain',
    'love', 'hate', 'fear', 'joy', 'danger', 'safe', 'urgent',
    'frustrated', 'confused', 'surprised', 'disgusted', 'anxious',
  };

  static const _causalWords = {
    'because', 'therefore', 'since', 'so', 'thus', 'hence',
    'cause', 'result', 'effect', 'lead', 'trigger', 'produce',
    'due to', 'owing to', 'consequently', 'as a result',
  };

  static const _negationWords = {
    'not', "n't", 'no', 'never', 'neither', 'nor', 'nothing',
    'nobody', 'nowhere', 'without', 'lack', 'absent',
  };

  static const _quantifiers = {
    'all', 'every', 'each', 'some', 'few', 'many', 'most',
    'more', 'less', 'several', 'both', 'any', 'one', 'two',
    'three', 'multiple',
  };

  // Common English function words to skip when extracting entities
  static const _stopWords = {
    'the', 'a', 'an', 'is', 'are', 'was', 'were', 'be', 'been',
    'being', 'have', 'has', 'had', 'do', 'does', 'did', 'will',
    'would', 'could', 'should', 'may', 'might', 'shall', 'can',
    'to', 'of', 'in', 'for', 'on', 'with', 'at', 'by', 'from',
    'it', 'its', 'this', 'that', 'these', 'those', 'i', 'you',
    'he', 'she', 'we', 'they', 'what', 'which', 'who', 'how',
    'and', 'or', 'but', 'if', 'then', 'than', 'very', 'just',
  };

  // Simple verb suffixes for action detection
  static const _verbSuffixes = ['ing', 'ed', 'es', 's'];

  // ── Public API ─────────────────────────────

  /// Extracts features from a raw text [input].
  ExtractedFeatures extract(String input) {
    final lower = input.toLowerCase().trim();
    final tokens = _tokenise(lower);

    final entities = <String>[];
    final actions = <String>[];
    final attributes = <String>[];
    final spatial = <String>[];
    final temporal = <String>[];
    final emotional = <String>[];
    final causal = <String>[];
    final quantifiers = <String>[];
    final negations = <String>[];

    for (final token in tokens) {
      if (_negationWords.contains(token)) {
        negations.add(token);
      } else if (_causalWords.contains(token)) {
        causal.add(token);
      } else if (_spatialWords.contains(token)) {
        spatial.add(token);
      } else if (_temporalWords.contains(token)) {
        temporal.add(token);
      } else if (_emotionalWords.contains(token)) {
        emotional.add(token);
      } else if (_quantifiers.contains(token)) {
        quantifiers.add(token);
      } else if (!_stopWords.contains(token)) {
        // Heuristic: short tokens with verb suffixes → action
        if (_looksLikeVerb(token)) {
          actions.add(token);
        } else if (_looksLikeAdjective(token)) {
          attributes.add(token);
        } else if (token.length > 2) {
          entities.add(token);
        }
      }
    }

    final features = ExtractedFeatures(
      entities: entities,
      actions: actions,
      attributes: attributes,
      spatialRelations: spatial,
      temporalMarkers: temporal,
      emotionalCues: emotional,
      causalCues: causal,
      quantifiers: quantifiers,
      negations: negations,
      questions: lower.endsWith('?') || lower.startsWith('what') ||
          lower.startsWith('why') || lower.startsWith('how') ||
          lower.startsWith('who') || lower.startsWith('where'),
    );

    _logger.debug(
        'Extracted from "${_trunc(input)}": '
        '${entities.length} entities, '
        '${actions.length} actions, '
        '${emotional.length} emotional cues');

    return features;
  }

  /// Computes a simple emotional valence from detected cues.
  EmotionalValence detectEmotionalValence(List<String> emotionalCues) {
    if (emotionalCues.isEmpty) return EmotionalValence.neutral;

    const positiveWords = {
      'happy', 'joy', 'love', 'safe', 'excited', 'calm',
    };
    const negativeWords = {
      'sad', 'angry', 'afraid', 'scared', 'pain', 'danger',
      'hungry', 'tired', 'worried', 'frustrated', 'hate', 'fear',
    };

    var positiveCount = 0;
    var negativeCount = 0;
    for (final cue in emotionalCues) {
      if (positiveWords.contains(cue)) positiveCount++;
      if (negativeWords.contains(cue)) negativeCount++;
    }

    if (positiveCount == 0 && negativeCount == 0) {
      return EmotionalValence.neutral;
    }

    final balance = (positiveCount - negativeCount).toDouble();
    final total = (positiveCount + negativeCount).toDouble();
    final ratio = balance / total;

    if (ratio >= 0.6) return EmotionalValence.veryPositive;
    if (ratio >= 0.2) return EmotionalValence.positive;
    if (ratio <= -0.6) return EmotionalValence.veryNegative;
    if (ratio <= -0.2) return EmotionalValence.negative;
    return EmotionalValence.neutral;
  }

  /// Estimates emotional intensity from the input text.
  double estimateEmotionalIntensity(String input) {
    final exclamationCount = '!'.allMatches(input).length;
    final capsRatio =
        input.runes.where((r) => r >= 65 && r <= 90).length /
            math.max(1, input.length);
    final intensifiers =
        RegExp(r'\b(very|extremely|super|really|absolutely|totally)\b')
            .allMatches(input.toLowerCase())
            .length;

    final score = (exclamationCount * 0.3 +
            capsRatio * 0.3 +
            intensifiers * 0.2)
        .clamp(0.0, 1.0);
    return score;
  }

  // ── Private helpers ─────────────────────────

  List<String> _tokenise(String text) => text
      .split(RegExp(r'[\s,;.!?]+'))
      .where((t) => t.isNotEmpty)
      .toList();

  bool _looksLikeVerb(String token) {
    if (token.length < 4) return false;
    return _verbSuffixes.any((suf) =>
        token.endsWith(suf) && token.length - suf.length > 2);
  }

  bool _looksLikeAdjective(String token) {
    const adjSuffixes = ['ful', 'less', 'ous', 'ive', 'able', 'ible', 'al', 'ic'];
    return adjSuffixes.any((suf) => token.endsWith(suf));
  }

  String _trunc(String s, [int n = 50]) =>
      s.length > n ? '${s.substring(0, n - 3)}...' : s;
}
