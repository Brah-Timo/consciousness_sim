// lib/integration/synchronization.dart
// Synchronization — coordinates parallel processing streams.
//
// In the brain, gamma-band synchronization (40 Hz) is thought to "glue"
// distributed neural assemblies into unified conscious percepts.
// Here we model synchronization as temporal coordination of asynchronous
// processing pipelines (perception, memory, inference).

import 'dart:async';

import 'package:consciousness_sim/utils/logger.dart';

// ─────────────────────────────────────────────
// ProcessingStream
// ─────────────────────────────────────────────

/// Represents one parallel processing channel.
class ProcessingStream {
  ProcessingStream({
    required this.name,
    required this.priority,
  });

  final String name;
  final int priority; // Higher = more urgent

  bool _isActive = false;
  DateTime? _lastSyncTime;
  int _cycleCount = 0;

  bool get isActive => _isActive;
  int get cycleCount => _cycleCount;
  Duration get timeSinceLastSync =>
      _lastSyncTime == null
          ? Duration.zero
          : DateTime.now().difference(_lastSyncTime!);

  void activate() {
    _isActive = true;
    _lastSyncTime = DateTime.now();
  }

  void deactivate() => _isActive = false;

  void markSynced() {
    _lastSyncTime = DateTime.now();
    _cycleCount++;
  }
}

// ─────────────────────────────────────────────
// SynchronizationManager
// ─────────────────────────────────────────────

/// Coordinates timing and synchronisation of multiple processing streams.
///
/// ### Responsibilities
/// - Ensures that perception, reasoning, and memory operations are
///   synchronised at appropriate tick rates.
/// - Prevents race conditions between concurrent workspace updates.
/// - Emits synchronisation events to registered listeners.
class SynchronizationManager {
  SynchronizationManager({
    this.tickIntervalMs = 100,
    ConsciousnessLogger? logger,
  })  : assert(tickIntervalMs >= 10),
        _logger = logger ?? ConsciousnessLogger('SynchronizationManager');

  final int tickIntervalMs;
  final ConsciousnessLogger _logger;

  final Map<String, ProcessingStream> _streams = {};
  final List<void Function(SyncEvent)> _listeners = [];

  Timer? _tickTimer;
  int _tickCount = 0;
  bool _isRunning = false;

  // ── Stream registration ────────────────────

  /// Registers a [ProcessingStream] with this synchronizer.
  void registerStream(ProcessingStream stream) {
    _streams[stream.name] = stream;
    _logger.debug('Registered stream: "${stream.name}"');
  }

  /// Unregisters a stream.
  void unregisterStream(String name) {
    _streams.remove(name);
  }

  // ── Lifecycle ──────────────────────────────

  /// Starts the synchronisation tick timer.
  void start() {
    if (_isRunning) return;
    _isRunning = true;

    _tickTimer = Timer.periodic(
      Duration(milliseconds: tickIntervalMs),
      (_) => _tick(),
    );

    _logger.info(
        'Synchronization started (${tickIntervalMs}ms ticks)');
  }

  /// Stops the tick timer.
  void stop() {
    _tickTimer?.cancel();
    _tickTimer = null;
    _isRunning = false;
    _logger.info('Synchronization stopped');
  }

  bool get isRunning => _isRunning;

  // ── Synchronisation API ────────────────────

  /// Marks a stream as having completed one processing step.
  void markComplete(String streamName) {
    final stream = _streams[streamName];
    if (stream == null) return;
    stream.markSynced();
  }

  /// Adds a listener that is called every synchronisation tick.
  void addListener(void Function(SyncEvent) listener) {
    _listeners.add(listener);
  }

  /// Removes a listener.
  void removeListener(void Function(SyncEvent) listener) {
    _listeners.remove(listener);
  }

  /// Awaits until all registered streams are synchronised.
  Future<void> waitForSync({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      if (_allSynced()) return;
      await Future<void>.delayed(Duration(milliseconds: tickIntervalMs));
    }

    _logger.warning('Sync timeout after ${timeout.inMilliseconds}ms');
  }

  /// Returns statistics for all streams.
  Map<String, Map<String, dynamic>> getStreamStats() => {
        for (final s in _streams.values)
          s.name: {
            'active': s.isActive,
            'cycles': s.cycleCount,
            'last_sync_ms': s.timeSinceLastSync.inMilliseconds,
            'priority': s.priority,
          },
      };

  // ── Private ────────────────────────────────

  void _tick() {
    _tickCount++;
    final event = SyncEvent(
      tickNumber: _tickCount,
      timestamp: DateTime.now(),
      activeStreams:
          _streams.values.where((s) => s.isActive).map((s) => s.name).toList(),
    );

    for (final listener in _listeners) {
      listener(event);
    }
  }

  bool _allSynced() {
    final threshold = Duration(milliseconds: tickIntervalMs * 5);
    return _streams.values
        .where((s) => s.isActive)
        .every((s) => s.timeSinceLastSync < threshold);
  }

  @override
  String toString() =>
      'SynchronizationManager('
      'streams: ${_streams.length}, '
      'running: $_isRunning, '
      'ticks: $_tickCount)';
}

// ─────────────────────────────────────────────
// SyncEvent
// ─────────────────────────────────────────────

/// Emitted by [SynchronizationManager] on each tick.
class SyncEvent {
  const SyncEvent({
    required this.tickNumber,
    required this.timestamp,
    required this.activeStreams,
  });

  final int tickNumber;
  final DateTime timestamp;
  final List<String> activeStreams;

  @override
  String toString() =>
      'SyncEvent(tick: $tickNumber, '
      'streams: ${activeStreams.join(', ')})';
}
