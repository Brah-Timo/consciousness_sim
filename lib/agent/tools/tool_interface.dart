// lib/agent/tools/tool_interface.dart
//
// Tool system — base interface, registry, router, and result types.
//
// Architecture:
//   LLM decision (AgentDecision.useTool)
//     → ToolRouter.route()
//     → ToolExecutor.execute()
//     → ToolResult
//     → back into AgentContext as AgentObservation

import 'package:consciousness_sim/utils/logger.dart';

// ─────────────────────────────────────────────
// ToolResult
// ─────────────────────────────────────────────

/// The outcome of a tool execution.
class ToolResult {
  const ToolResult({
    required this.toolName,
    required this.success,
    this.output,
    this.error,
    this.metadata = const {},
    DateTime? executedAt,
  }) : executedAt = executedAt;

  /// Which tool produced this result.
  final String toolName;

  /// Whether execution succeeded without error.
  final bool success;

  /// The data returned by the tool.  May be a String, Map, List, or num.
  final dynamic output;

  /// Human-readable error if [success] is false.
  final String? error;

  /// Optional metadata about the execution (duration, source URL, etc.).
  final Map<String, dynamic> metadata;

  final DateTime? executedAt;

  /// Formats [output] as a compact string for LLM context injection.
  String get outputText {
    if (output == null) return '(no output)';
    if (output is String) return output as String;
    return output.toString();
  }

  /// Creates a failure result.
  factory ToolResult.failure(String toolName, String error) => ToolResult(
        toolName: toolName,
        success: false,
        error: error,
        executedAt: DateTime.now(),
      );

  /// Creates a success result.
  factory ToolResult.success(String toolName, dynamic output,
          {Map<String, dynamic>? metadata}) =>
      ToolResult(
        toolName: toolName,
        success: true,
        output: output,
        metadata: metadata ?? const {},
        executedAt: DateTime.now(),
      );

  @override
  String toString() =>
      'ToolResult($toolName, success: $success, '
      'output: "${_trunc(outputText)}")';

  String _trunc(String s, [int n = 80]) =>
      s.length > n ? '${s.substring(0, n - 3)}...' : s;
}

// ─────────────────────────────────────────────
// Tool (abstract)
// ─────────────────────────────────────────────

/// Base class for all agent tools.
///
/// ### Implementing a tool
/// ```dart
/// class MyTool extends Tool {
///   @override
///   String get name => 'my_tool';
///
///   @override
///   String get description => 'Does something useful.';
///
///   @override
///   Map<String, String> get inputSchema => {
///     'query': 'The input string to process.',
///   };
///
///   @override
///   Future<ToolResult> run(Map<String, dynamic> input) async {
///     final q = input['query'] as String? ?? '';
///     return ToolResult.success(name, 'Processed: $q');
///   }
/// }
/// ```
abstract class Tool {
  const Tool();

  /// Unique snake_case name the LLM uses to invoke this tool.
  String get name;

  /// One-sentence description included in the system prompt.
  String get description;

  /// Schema of expected input keys and their descriptions.
  Map<String, String> get inputSchema;

  /// Whether this tool can safely be retried on failure.
  bool get isIdempotent => true;

  /// Executes the tool with the given [input] map.
  ///
  /// Should never throw — return [ToolResult.failure] on errors.
  Future<ToolResult> run(Map<String, dynamic> input);

  /// Validates the input map against [inputSchema].
  ///
  /// Returns null on success, or a human-readable error string.
  String? validate(Map<String, dynamic> input) {
    final missing = inputSchema.keys
        .where((k) => !input.containsKey(k) || input[k] == null)
        .toList();
    if (missing.isEmpty) return null;
    return 'Missing required input(s): ${missing.join(", ")}';
  }

  @override
  String toString() => 'Tool($name)';
}

// ─────────────────────────────────────────────
// ToolRegistry
// ─────────────────────────────────────────────

/// A registry of all available [Tool] instances.
///
/// Tools are registered once and looked up by name at execution time.
class ToolRegistry {
  ToolRegistry({ConsciousnessLogger? logger})
      : _logger = logger ?? ConsciousnessLogger('ToolRegistry');

  final Map<String, Tool> _tools = {};
  final ConsciousnessLogger _logger;

  /// Registers [tool], overwriting any existing registration with the same name.
  void register(Tool tool) {
    _tools[tool.name] = tool;
    _logger.debug('Tool registered: ${tool.name}');
  }

  /// Registers multiple [tools] at once.
  void registerAll(Iterable<Tool> tools) {
    for (final t in tools) {
      register(t);
    }
  }

  /// Removes a tool by [name].
  void unregister(String name) {
    if (_tools.remove(name) != null) {
      _logger.debug('Tool unregistered: $name');
    }
  }

  /// Returns the [Tool] with [name], or null if not found.
  Tool? find(String name) => _tools[name];

  /// Whether [name] is registered.
  bool has(String name) => _tools.containsKey(name);

  /// All registered tool names.
  List<String> get names => List.unmodifiable(_tools.keys.toList());

  /// All registered tools.
  List<Tool> get all => List.unmodifiable(_tools.values.toList());

  /// Builds a compact tool catalogue for the system prompt.
  String buildCatalogue() {
    if (_tools.isEmpty) return '(no tools registered)';
    return _tools.values
        .map((t) => '• ${t.name}: ${t.description}')
        .join('\n');
  }

  int get count => _tools.length;

  @override
  String toString() => 'ToolRegistry(${_tools.length} tools: ${names.join(", ")})';
}

// ─────────────────────────────────────────────
// ToolRouter
// ─────────────────────────────────────────────

/// Routes a tool-call decision to the correct [Tool] in the [ToolRegistry].
class ToolRouter {
  const ToolRouter(this._registry, {ConsciousnessLogger? logger})
      : _logger = logger;

  final ToolRegistry _registry;
  final ConsciousnessLogger? _logger;

  /// Routes [toolName] to the registered tool and executes it with [input].
  ///
  /// Returns a [ToolResult] — never throws.
  Future<ToolResult> route(
    String toolName,
    Map<String, dynamic> input,
  ) async {
    final tool = _registry.find(toolName);

    if (tool == null) {
      _logger?.warning('Unknown tool requested: "$toolName"');
      return ToolResult.failure(
        toolName,
        'Tool "$toolName" is not registered. '
        'Available: ${_registry.names.join(", ")}',
      );
    }

    final validationError = tool.validate(input);
    if (validationError != null) {
      _logger?.warning('Tool "$toolName" validation failed: $validationError');
      return ToolResult.failure(toolName, validationError);
    }

    _logger?.info('Routing → $toolName | input: $input');

    try {
      final result = await tool.run(input);
      _logger?.info(
          'Tool "$toolName" → ${result.success ? "OK" : "FAIL"}: '
          '"${_trunc(result.outputText)}"');
      return result;
    } catch (e, st) {
      _logger?.error('Tool "$toolName" threw unexpectedly', e, st);
      return ToolResult.failure(toolName, 'Unexpected error: $e');
    }
  }

  String _trunc(String s, [int n = 80]) =>
      s.length > n ? '${s.substring(0, n - 3)}...' : s;
}
