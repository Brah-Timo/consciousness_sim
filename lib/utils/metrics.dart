// lib/utils/metrics.dart
// Performance metrics tracking for consciousness_sim.

/// Collects and aggregates performance statistics across processing cycles.
class ConsciousnessMetrics {
  ConsciousnessMetrics();

  // ── Raw accumulators ───────────────────────
  int _totalCycles = 0;
  int _totalInferences = 0;
  int _totalBindings = 0;
  int _totalLatencyMs = 0;
  double _coherenceSum = 0.0;
  int _peakWorkspaceSize = 0;
  int _memoryRetrievals = 0;
  DateTime? _startTime;
  DateTime? _lastCycleTime;
  final List<int> _latencySamples = [];

  // ── Public counters ─────────────────────────

  /// Total processing cycles run.
  int get totalCycles => _totalCycles;

  /// Total inferences generated across all cycles.
  int get totalInferences => _totalInferences;

  /// Total binding operations performed.
  int get totalBindings => _totalBindings;

  /// Average inference latency in milliseconds.
  double get averageLatencyMs =>
      _totalCycles == 0 ? 0.0 : _totalLatencyMs / _totalCycles;

  /// Average workspace coherence across all cycles.
  double get averageCoherence =>
      _totalCycles == 0 ? 0.0 : _coherenceSum / _totalCycles;

  /// Peak number of concepts ever held in the workspace simultaneously.
  int get peakWorkspaceSize => _peakWorkspaceSize;

  /// Total memory retrieval operations.
  int get memoryRetrievals => _memoryRetrievals;

  /// P95 latency (milliseconds) based on recent samples.
  double get p95LatencyMs {
    if (_latencySamples.isEmpty) return 0.0;
    final sorted = List.of(_latencySamples)..sort();
    final idx = ((sorted.length - 1) * 0.95).round();
    return sorted[idx].toDouble();
  }

  /// Wall-clock uptime since first cycle.
  Duration get uptime =>
      _startTime == null ? Duration.zero : DateTime.now().difference(_startTime!);

  /// Time since last cycle.
  Duration get timeSinceLastCycle =>
      _lastCycleTime == null
          ? Duration.zero
          : DateTime.now().difference(_lastCycleTime!);

  // ── Recording methods ───────────────────────

  /// Records statistics for one complete processing cycle.
  void recordCycle({
    required int inferenceCount,
    required int bindingCount,
    required int latencyMs,
    required double coherence,
    int workspaceSize = 0,
  }) {
    _startTime ??= DateTime.now();
    _lastCycleTime = DateTime.now();

    _totalCycles++;
    _totalInferences += inferenceCount;
    _totalBindings += bindingCount;
    _totalLatencyMs += latencyMs;
    _coherenceSum += coherence;

    if (workspaceSize > _peakWorkspaceSize) {
      _peakWorkspaceSize = workspaceSize;
    }

    _latencySamples.add(latencyMs);
    if (_latencySamples.length > 1000) _latencySamples.removeAt(0);
  }

  /// Increments the memory retrieval counter.
  void recordMemoryRetrieval() => _memoryRetrievals++;

  /// Resets all metrics to zero.
  void reset() {
    _totalCycles = 0;
    _totalInferences = 0;
    _totalBindings = 0;
    _totalLatencyMs = 0;
    _coherenceSum = 0.0;
    _peakWorkspaceSize = 0;
    _memoryRetrievals = 0;
    _startTime = null;
    _lastCycleTime = null;
    _latencySamples.clear();
  }

  /// Returns a formatted metrics report.
  String report() => '''
╔══════════════════════════════════════════╗
║        CONSCIOUSNESS METRICS REPORT      ║
╠══════════════════════════════════════════╣
║ Uptime            : ${uptime.toString().padRight(28)}║
║ Total Cycles      : ${_totalCycles.toString().padRight(28)}║
║ Total Inferences  : ${_totalInferences.toString().padRight(28)}║
║ Total Bindings    : ${_totalBindings.toString().padRight(28)}║
║ Avg Latency       : ${averageLatencyMs.toStringAsFixed(2).padRight(25)}ms║
║ P95 Latency       : ${p95LatencyMs.toStringAsFixed(2).padRight(25)}ms║
║ Avg Coherence     : ${(averageCoherence * 100).toStringAsFixed(1).padRight(25)}%║
║ Peak WS Size      : ${_peakWorkspaceSize.toString().padRight(28)}║
║ Memory Retrievals : ${_memoryRetrievals.toString().padRight(28)}║
╚══════════════════════════════════════════╝''';

  @override
  String toString() =>
      'Metrics(cycles: $_totalCycles, '
      'avgLatency: ${averageLatencyMs.toStringAsFixed(1)}ms, '
      'coherence: ${(averageCoherence * 100).toStringAsFixed(1)}%)';
}
