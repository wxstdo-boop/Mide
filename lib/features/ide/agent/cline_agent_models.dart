// Shared types for the full Cline-SDK coding agent (sidecar bridge).
// Pure Dart on purpose: the Riverpod layer imports these plus the conditional
// facade (cline_agent.dart), so web builds never see dart:io.

/// Lifecycle of the sidecar process.
enum ClineAgentPhase { stopped, starting, ready, running, failed }

/// One streamed thing the agent did.
enum ClineStepKind { user, assistant, reasoning, tool, approval, notice }

/// A single line of the agent transcript.
class ClineStep {
  final ClineStepKind kind;
  final String text;

  /// Tool name for [ClineStepKind.tool] / [ClineStepKind.approval].
  final String? tool;

  /// Tool arguments (already JSON-decoded) for display.
  final Object? args;

  /// Tool result text once the call finished.
  final String? result;

  /// True while a tool call is in flight.
  final bool pending;

  /// Approval id, for [ClineStepKind.approval].
  final String? approvalId;

  /// Decision made for an approval step (null = still asking).
  final bool? decided;

  const ClineStep({
    required this.kind,
    required this.text,
    this.tool,
    this.args,
    this.result,
    this.pending = false,
    this.approvalId,
    this.decided,
  });

  ClineStep copyWith({
    String? text,
    String? result,
    bool? pending,
    bool? decided,
  }) => ClineStep(
    kind: kind,
    text: text ?? this.text,
    tool: tool,
    args: args,
    result: result ?? this.result,
    pending: pending ?? this.pending,
    approvalId: approvalId,
    decided: decided ?? this.decided,
  );
}

/// Event pushed by [ClineAgentBackend.events] while a run streams.
class ClineAgentEvent {
  final String type;
  final String? text;
  final String? name;
  final Object? input;
  final String? approvalId;
  final String? status;

  const ClineAgentEvent({
    required this.type,
    this.text,
    this.name,
    this.input,
    this.approvalId,
    this.status,
  });
}

/// What the sidecar reported about itself after startup.
class ClineAgentInfo {
  final String model;
  final String provider;
  final int port;
  final List<String> tools;
  final String workspace;

  const ClineAgentInfo({
    required this.model,
    required this.provider,
    required this.port,
    required this.tools,
    required this.workspace,
  });
}

class ClineAgentException implements Exception {
  final String message;
  const ClineAgentException(this.message);

  @override
  String toString() => message;
}

/// Free keyless OpenAI-compatible endpoint the sidecar is launched against.
const String kClineAgentBaseUrl =
    'https://oai.endpoints.kepler.ai.cloud.ovh.net/v1';
const String kClineAgentModel = 'gpt-oss-20b';
