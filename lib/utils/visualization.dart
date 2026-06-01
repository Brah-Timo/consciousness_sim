// lib/utils/visualization.dart
// ASCII/text visualization utilities for the consciousness workspace.

import 'package:consciousness_sim/core/models.dart';
import 'package:consciousness_sim/reasoning/conceptual_graph.dart';

/// Produces human-readable ASCII representations of consciousness states,
/// concept graphs, and activation levels — useful for debugging and demos.
class ConsciousnessVisualizer {
  const ConsciousnessVisualizer({this.barWidth = 20});

  final int barWidth;

  // ── Workspace display ───────────────────────

  /// Renders a [ConsciousState] as a formatted ASCII panel.
  String renderState(ConsciousState state) {
    final buf = StringBuffer();
    buf.writeln('╔══════════════════════════════════════════════╗');
    buf.writeln('║          🧠  CONSCIOUS STATE                 ║');
    buf.writeln('╠══════════════════════════════════════════════╣');
    buf.writeln('║ Focus     : ${_pad(state.focusedConceptId, 33)}║');
    buf.writeln(
        '║ Coherence : ${_bar(state.coherence)} ${_pct(state.coherence).padLeft(6)} ║');
    buf.writeln(
        '║ Timestamp : ${_pad(state.timestamp.toIso8601String().substring(0, 19), 33)}║');
    buf.writeln('╠══════════════════════════════════════════════╣');
    buf.writeln('║  Active workspace (${state.workspace.length} concepts):            ║');

    for (final c in state.workspace) {
      final label = c.content.length > 18
          ? '${c.content.substring(0, 15)}...'
          : c.content;
      buf.writeln(
        '║  • ${label.padRight(18)} ${_bar(c.activationLevel)} ${_pct(c.activationLevel).padLeft(6)} ║',
      );
    }

    if (state.inferencesGenerated.isNotEmpty) {
      buf.writeln('╠══════════════════════════════════════════════╣');
      buf.writeln('║  Inferences (${state.inferencesGenerated.length}):                        ║');
      for (final i in state.inferencesGenerated.take(5)) {
        final text = i.conclusion.length > 36
            ? '${i.conclusion.substring(0, 33)}...'
            : i.conclusion;
        buf.writeln('║  → ${text.padRight(42)}║');
      }
    }

    buf.writeln('╚══════════════════════════════════════════════╝');
    return buf.toString();
  }

  // ── Activation map ──────────────────────────

  /// Renders an activation map as a horizontal bar chart.
  String renderActivationMap(Map<String, double> map) {
    final buf = StringBuffer();
    buf.writeln('── Activation Map ──────────────────────────────');
    final sorted = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in sorted) {
      final label = e.key.length > 20
          ? '${e.key.substring(0, 17)}...'
          : e.key;
      buf.writeln(
        '  ${label.padRight(21)} ${_bar(e.value)} ${_pct(e.value).padLeft(6)}',
      );
    }
    return buf.toString();
  }

  // ── Concept graph ───────────────────────────

  /// Renders an adjacency list view of the concept graph.
  String renderGraph(ConceptualGraph graph) {
    final buf = StringBuffer();
    buf.writeln('── Conceptual Graph ─────────────────────────────');
    buf.writeln('   Nodes: ${graph.nodeCount} | Edges: ${graph.edgeCount}');
    buf.writeln();

    for (final node in graph.getAllNodes().take(20)) {
      buf.writeln('  [${node.id.substring(0, 8)}] "${node.concept.content}"');
      for (final edge in node.edges.values.take(5)) {
        final target = graph.getNode(edge.targetId);
        final label = target?.concept.content ?? edge.targetId;
        buf.writeln(
            '       ──${edge.relationshipType.name}(${edge.strength.toStringAsFixed(2)})──▶ '
            '"$label"');
      }
    }

    if (graph.nodeCount > 20) {
      buf.writeln('  ... and ${graph.nodeCount - 20} more nodes');
    }

    return buf.toString();
  }

  // ── Memory summary ──────────────────────────

  /// Renders a summary of memory counts.
  String renderMemorySummary({
    required int episodicCount,
    required int semanticCount,
    required int workingCount,
  }) =>
      '''
── Memory Summary ───────────────────────────────
  Episodic  : $episodicCount   (specific events)
  Semantic  : $semanticCount   (general facts)
  Working   : $workingCount    (short-term buffer)
─────────────────────────────────────────────────''';

  // ── Private helpers ─────────────────────────

  String _bar(double value) {
    final filled = (value * barWidth).round().clamp(0, barWidth);
    return '[${('█' * filled).padRight(barWidth)}]';
  }

  String _pct(double value) => '${(value * 100).toStringAsFixed(0)}%';

  String _pad(String s, int width) =>
      s.length > width ? '${s.substring(0, width - 3)}...' : s.padRight(width);
}
