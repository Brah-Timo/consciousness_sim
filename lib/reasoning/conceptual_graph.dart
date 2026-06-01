// lib/reasoning/conceptual_graph.dart
// ConceptualGraph — a directed, weighted semantic network.
//
// Implemented as an adjacency-list graph where nodes are [ConceptNode]
// objects and edges are typed, weighted [ConceptEdge] relationships.
// Supports BFS/DFS traversal, pattern discovery, and PageRank-style
// activation spreading.

import 'dart:collection';
import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import 'package:consciousness_sim/core/models.dart';
import 'package:consciousness_sim/utils/logger.dart';

// ─────────────────────────────────────────────
// ConceptualGraph
// ─────────────────────────────────────────────

/// A directed, weighted graph of concepts and their relationships.
///
/// Serves as the long-term semantic backbone of the consciousness system.
/// Concepts persist here even after they leave the short-term workspace.
class ConceptualGraph {
  ConceptualGraph({ConsciousnessLogger? logger})
      : _logger = logger ?? ConsciousnessLogger('ConceptualGraph');

  final ConsciousnessLogger _logger;
  final _uuid = const Uuid();

  final Map<String, ConceptNode> _nodes = {};

  // ── Basic graph operations ─────────────────

  /// Number of nodes in the graph.
  int get nodeCount => _nodes.length;

  /// Number of directed edges across all nodes.
  int get edgeCount =>
      _nodes.values.fold(0, (sum, n) => sum + n.edges.length);

  /// Adds or updates a [Concept] in the graph.
  void addConcept(String id, Concept concept) {
    if (_nodes.containsKey(id)) {
      // Concept already exists — reinforce its activation
      final existing = _nodes[id]!.concept;
      final reinforced = existing.copyWith(
        activationLevel: math.min(
          1.0,
          existing.activationLevel + 0.05,
        ),
      );
      _nodes[id] = ConceptNode(concept: reinforced);
    } else {
      _nodes[id] = ConceptNode(concept: concept);
      _logger.debug(
          'Added concept: "${concept.content}" (id: ${id.length > 8 ? id.substring(0, 8) : id})');
    }
  }

  /// Returns the node for [conceptId], or null if not found.
  ConceptNode? getNode(String conceptId) => _nodes[conceptId];

  /// Returns all nodes in the graph.
  List<ConceptNode> getAllNodes() => List.unmodifiable(_nodes.values);

  /// Returns true if a concept with [id] exists.
  bool hasNode(String id) => _nodes.containsKey(id);

  /// Creates a directed edge from [sourceId] to [targetId].
  ///
  /// If the edge already exists, its strength is reinforced.
  void linkConcepts(
    String sourceId,
    String targetId, {
    required RelationshipType relationshipType,
    required double strength,
    String label = '',
  }) {
    if (!_nodes.containsKey(sourceId) || !_nodes.containsKey(targetId)) {
      _logger.warning(
          'Cannot link: node(s) not found ($sourceId → $targetId)');
      return;
    }

    final sourceNode = _nodes[sourceId]!;
    final existing = sourceNode.edges[targetId];

    if (existing != null) {
      // Reinforce existing edge
      final newStrength =
          math.min(1.0, existing.strength + strength * 0.2);
      sourceNode.edges[targetId] = existing.copyWith(strength: newStrength);
    } else {
      sourceNode.addEdge(ConceptEdge(
        sourceId: sourceId,
        targetId: targetId,
        relationshipType: relationshipType,
        strength: strength.clamp(0.0, 1.0),
        label: label,
      ));
      _logger.debug(
          'Linked: "${_nodes[sourceId]!.concept.content}" '
          '─[${relationshipType.name}]→ '
          '"${_nodes[targetId]!.concept.content}" '
          '(strength: ${strength.toStringAsFixed(2)})');
    }
  }

  // ── Graph traversal ────────────────────────

  /// BFS: returns all nodes reachable from [startId] within [maxDepth] hops.
  ///
  /// Results are sorted by (depth + edge strength) for relevance ordering.
  List<ConceptNode> findRelatedConcepts(String startId, int maxDepth) {
    if (!_nodes.containsKey(startId)) return [];

    final visited = <String>{startId};
    final queue = Queue<_BFSEntry>();
    queue.addAll(_nodes[startId]!.edges.values.map(
      (e) => _BFSEntry(nodeId: e.targetId, depth: 1, strength: e.strength),
    ));

    final results = <_BFSEntry>[];

    while (queue.isNotEmpty) {
      final entry = queue.removeFirst();
      if (visited.contains(entry.nodeId)) continue;
      if (entry.depth > maxDepth) continue;

      visited.add(entry.nodeId);
      results.add(entry);

      final node = _nodes[entry.nodeId];
      if (node != null && entry.depth < maxDepth) {
        for (final edge in node.edges.values) {
          if (!visited.contains(edge.targetId)) {
            queue.addLast(_BFSEntry(
              nodeId: edge.targetId,
              depth: entry.depth + 1,
              strength: entry.strength * edge.strength,
            ));
          }
        }
      }
    }

    // Sort by accumulated strength descending
    results.sort((a, b) => b.strength.compareTo(a.strength));
    return results
        .map((e) => _nodes[e.nodeId])
        .whereType<ConceptNode>()
        .toList();
  }

  /// DFS path from [startId] to [goalId]. Returns the node path or [].
  List<ConceptNode> findPath(String startId, String goalId) {
    final visited = <String>{};
    final path = <ConceptNode>[];

    bool dfs(String currentId) {
      if (visited.contains(currentId)) return false;
      visited.add(currentId);
      final node = _nodes[currentId];
      if (node == null) return false;
      path.add(node);
      if (currentId == goalId) return true;

      for (final edge in node.edges.values) {
        if (dfs(edge.targetId)) return true;
      }
      path.removeLast();
      return false;
    }

    dfs(startId);
    return path;
  }

  /// Returns concepts directly connected to [conceptId] by [type].
  List<ConceptNode> getNeighborsByType(
    String conceptId,
    RelationshipType type,
  ) {
    final node = _nodes[conceptId];
    if (node == null) return [];
    return node.edges.values
        .where((e) => e.relationshipType == type)
        .map((e) => _nodes[e.targetId])
        .whereType<ConceptNode>()
        .toList();
  }

  // ── Activation spreading ───────────────────

  /// Spreads activation from [sourceId] through its edges.
  ///
  /// Activation decays with distance: each hop multiplies by [decay].
  /// Returns a map of conceptId → spread activation.
  Map<String, double> spreadActivation(
    String sourceId, {
    int maxHops = 3,
    double decay = 0.5,
  }) {
    final result = <String, double>{};
    final source = _nodes[sourceId];
    if (source == null) return result;

    final initialActivation = source.concept.activationLevel;
    final queue = Queue<_SpreadEntry>();
    queue.add(_SpreadEntry(
      nodeId: sourceId,
      activation: initialActivation,
      hops: 0,
    ));

    final visited = <String>{};

    while (queue.isNotEmpty) {
      final entry = queue.removeFirst();
      if (visited.contains(entry.nodeId)) continue;
      if (entry.hops >= maxHops) continue;

      visited.add(entry.nodeId);
      result[entry.nodeId] = (result[entry.nodeId] ?? 0.0) + entry.activation;

      final node = _nodes[entry.nodeId];
      if (node != null) {
        for (final edge in node.edges.values) {
          final spreadAmt = entry.activation * edge.strength * decay;
          if (spreadAmt > 0.01) {
            queue.addLast(_SpreadEntry(
              nodeId: edge.targetId,
              activation: spreadAmt,
              hops: entry.hops + 1,
            ));
          }
        }
      }
    }

    result.remove(sourceId); // Don't return the source itself
    return result;
  }

  // ── Pattern discovery ──────────────────────

  /// Discovers implicit patterns: clusters of highly interconnected concepts.
  ///
  /// Uses a simple density-based heuristic — groups of ≥ 3 nodes where
  /// every pair has at least one path of length ≤ 2.
  List<Pattern> discoverImplicitPatterns() {
    final patterns = <Pattern>[];
    final nodes = _nodes.values.toList();
    final visited = <String>{};

    for (final node in nodes) {
      if (visited.contains(node.id)) continue;

      final cluster = [node.id];
      final neighbors = findRelatedConcepts(node.id, 2)
          .map((n) => n.id)
          .take(6)
          .toList();

      for (final neighbor in neighbors) {
        // Check if this neighbor is also connected back (bidirectional cluster)
        final backNeighbors =
            findRelatedConcepts(neighbor, 1).map((n) => n.id).toSet();
        if (backNeighbors.contains(node.id) ||
            backNeighbors.intersection(cluster.toSet()).isNotEmpty) {
          cluster.add(neighbor);
        }
      }

      if (cluster.length >= 3) {
        final conceptNames = cluster
            .map((id) => _nodes[id]?.concept.content ?? id)
            .take(5)
            .join(', ');
        patterns.add(Pattern(
          id: _uuid.v4(),
          description: 'Conceptual cluster: $conceptNames',
          involvedConceptIds: cluster,
          confidence: math.min(1.0, cluster.length / 10.0),
        ));
        visited.addAll(cluster);
      }
    }

    _logger.debug('Discovered ${patterns.length} implicit pattern(s)');
    return patterns;
  }

  // ── Graph statistics ───────────────────────

  /// Returns the [n] most connected (highest out-degree) concepts.
  List<ConceptNode> getMostConnected(int n) {
    final sorted = _nodes.values.toList()
      ..sort((a, b) => b.edges.length.compareTo(a.edges.length));
    return sorted.take(n).toList();
  }

  /// Returns the [n] most activated concepts.
  List<ConceptNode> getMostActivated(int n) {
    final sorted = _nodes.values.toList()
      ..sort((a, b) =>
          b.concept.activationLevel.compareTo(a.concept.activationLevel));
    return sorted.take(n).toList();
  }

  /// Returns overall graph statistics.
  Map<String, dynamic> getStats() => {
        'node_count': nodeCount,
        'edge_count': edgeCount,
        'avg_degree':
            nodeCount == 0 ? 0 : edgeCount / nodeCount,
        'most_connected': getMostConnected(3)
            .map((n) => n.concept.content)
            .toList(),
      };

  @override
  String toString() =>
      'ConceptualGraph(nodes: $nodeCount, edges: $edgeCount)';
}

// ─────────────────────────────────────────────
// Internal helpers
// ─────────────────────────────────────────────

class _BFSEntry {
  const _BFSEntry({
    required this.nodeId,
    required this.depth,
    required this.strength,
  });

  final String nodeId;
  final int depth;
  final double strength;
}

class _SpreadEntry {
  const _SpreadEntry({
    required this.nodeId,
    required this.activation,
    required this.hops,
  });

  final String nodeId;
  final double activation;
  final int hops;
}
