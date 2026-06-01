// lib/utils/logger.dart
// Structured logging system for consciousness_sim.

import 'dart:developer' as developer;

/// Verbosity levels for the consciousness logger.
enum LogLevel { debug, info, warning, error, none }

/// A lightweight, structured logger used throughout the consciousness_sim
/// package.  Wraps [developer.log] for IDE integration and supports
/// filterable verbosity levels.
class ConsciousnessLogger {
  ConsciousnessLogger(
    this.name, {
    this.level = LogLevel.info,
  });

  final String name;
  LogLevel level;

  static final List<LogEntry> _history = [];

  /// All log entries recorded since startup (across all loggers).
  static List<LogEntry> get history => List.unmodifiable(_history);

  /// Clear the global log history.
  static void clearHistory() => _history.clear();

  void debug(String message) => _log(LogLevel.debug, message);
  void info(String message) => _log(LogLevel.info, message);
  void warning(String message) => _log(LogLevel.warning, message);
  void error(String message, [Object? error, StackTrace? stack]) =>
      _log(LogLevel.error, message, error: error, stack: stack);

  void _log(
    LogLevel msgLevel,
    String message, {
    Object? error,
    StackTrace? stack,
  }) {
    if (msgLevel.index < level.index) return;

    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: msgLevel,
      logger: name,
      message: message,
      error: error,
      stackTrace: stack,
    );

    _history.add(entry);

    developer.log(
      message,
      name: '[$name]',
      level: _dartLogLevel(msgLevel),
      error: error,
      stackTrace: stack,
    );
  }

  int _dartLogLevel(LogLevel l) => switch (l) {
        LogLevel.debug => 300,
        LogLevel.info => 800,
        LogLevel.warning => 900,
        LogLevel.error => 1000,
        LogLevel.none => 0,
      };
}

/// A single log entry.
class LogEntry {
  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.logger,
    required this.message,
    this.error,
    this.stackTrace,
  });

  final DateTime timestamp;
  final LogLevel level;
  final String logger;
  final String message;
  final Object? error;
  final StackTrace? stackTrace;

  String get levelIcon => switch (level) {
        LogLevel.debug => '🔍',
        LogLevel.info => 'ℹ️ ',
        LogLevel.warning => '⚠️ ',
        LogLevel.error => '🔴',
        LogLevel.none => '  ',
      };

  @override
  String toString() =>
      '$levelIcon [${timestamp.toIso8601String()}] [$logger] $message';
}
