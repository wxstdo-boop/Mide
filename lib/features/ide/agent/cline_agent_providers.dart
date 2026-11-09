// Riverpod state for the full coding agent (Cline SDK sidecar).
// Web-safe: only talks to the conditional facade, never to dart:io directly.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cline_agent.dart';

class ClineAgentState {
  final ClineAgentPhase phase;
  final List<ClineStep> steps;
  final ClineAgentInfo? info;
  final String? error;

  const ClineAgentState({
    this.phase = ClineAgentPhase.stopped,
    this.steps = const [],
    this.info,
    this.error,
  });

  bool get busy => phase == ClineAgentPhase.running;
  bool get live =>
      phase == ClineAgentPhase.ready || phase == ClineAgentPhase.running;

  ClineStep? get awaitingApproval {
    for (final s in steps.reversed) {
      if (s.kind == ClineStepKind.approval && s.decided == null) return s;
    }
    return null;
  }

  ClineAgentState copyWith({
    ClineAgentPhase? phase,
    List<ClineStep>? steps,
    ClineAgentInfo? info,
    String? error,
    bool clearError = false,
  }) =>
      ClineAgentState(
        phase: phase ?? this.phase,
        steps: steps ?? this.steps,
        info: info ?? this.info,
        error: clearError ? null : (error ?? this.error),
      );
}

class ClineAgentNotifier extends Notifier<ClineAgentState> {
  final List<ClineStep> _steps = [];

  @override
  ClineAgentState build() {
    final sub = ClineAgentBackend.instance.events.listen(_onEvent);
    ref.onDispose(() {
      sub.cancel();
      unawaited(ClineAgentBackend.instance.shutdown());
    });
    return const ClineAgentState();
  }

  /// Start the sidecar for [workspace] (the folder currently open in the IDE).
  Future<void> start(String workspace, {String? nodePath}) async {
    if (state.live) return;
    state = state.copyWith(phase: ClineAgentPhase.starting, clearError: true);
    try {
      final info = await ClineAgentBackend.instance
          .start(workspace: workspace, nodePath: nodePath);
      state = state.copyWith(
        phase: ClineAgentPhase.ready,
        info: info,
        clearError: true,
      );
      _push(const ClineStep(
        kind: ClineStepKind.notice,
        text: 'Агент на связи',
      ));
    } on ClineAgentException catch (e) {
      state = state.copyWith(
        phase: ClineAgentPhase.failed,
        error: e.message,
      );
    } catch (e) {
      state = state.copyWith(
        phase: ClineAgentPhase.failed,
        error: '$e',
      );
    }
  }

  Future<void> ask(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.busy) return;
    if (!state.live) {
      state = state.copyWith(
        error: 'Сначала нажми «Запустить» — агент поднимает свой процесс на ПК.',
      );
      return;
    }
    _push(ClineStep(kind: ClineStepKind.user, text: trimmed));
    state = state.copyWith(phase: ClineAgentPhase.running, clearError: true);
    try {
      await ClineAgentBackend.instance.send(trimmed);
    } catch (_) {
      // Already surfaced as an `error` event; keep the transcript readable.
    }
    if (state.phase == ClineAgentPhase.running) {
      state = state.copyWith(phase: ClineAgentPhase.ready);
    }
  }

  /// Answer a tool-approval request from the agent.
  Future<void> decide(bool ok) async {
    final pending = state.awaitingApproval;
    if (pending?.approvalId == null) return;
    await ClineAgentBackend.instance.approve(pending!.approvalId!, ok);
    _replace(pending, pending.copyWith(decided: ok));
  }

  Future<void> interrupt() => ClineAgentBackend.instance.interrupt();

  Future<void> clear() async {
    await ClineAgentBackend.instance.reset();
    _steps.clear();
    state = state.copyWith(steps: List.unmodifiable(_steps));
  }

  Future<void> shutdown() async {
    await ClineAgentBackend.instance.shutdown();
    state = state.copyWith(phase: ClineAgentPhase.stopped);
  }

  void _onEvent(ClineAgentEvent ev) {
    switch (ev.type) {
      case 'text':
        _appendText(ClineStepKind.assistant, ev.text);
      case 'reasoning':
        _appendText(ClineStepKind.reasoning, ev.text);
      case 'tool_start':
        _push(ClineStep(
          kind: ClineStepKind.tool,
          text: ev.name ?? '?',
          tool: ev.name,
          args: ev.input,
          pending: true,
        ));
      case 'tool_end':
        _finishTool(ev.name, ev.text ?? _stringify(ev.input));
      case 'approval':
        _push(ClineStep(
          kind: ClineStepKind.approval,
          text: ev.name ?? '?',
          tool: ev.name,
          args: ev.input,
          approvalId: ev.approvalId,
          pending: true,
        ));
      case 'done':
        final failed = ev.status != null && ev.status != 'completed';
        if (failed) {
          _push(ClineStep(
            kind: ClineStepKind.notice,
            text: 'Прогон завершён со статусом ${ev.status}'
                '${ev.text == null ? '' : ': ${ev.text}'}',
          ));
        }
        if (ev.status != null) {
          state = state.copyWith(
            phase: ClineAgentPhase.ready,
            error: failed ? ev.text : null,
            clearError: !failed,
          );
        }
      case 'error':
        _push(ClineStep(kind: ClineStepKind.notice, text: ev.text ?? 'ошибка'));
        state = state.copyWith(
          phase: ClineAgentPhase.ready,
          error: ev.text,
        );
      case 'stopped':
        state = state.copyWith(
          phase: ClineAgentPhase.stopped,
          info: null,
          error: ev.text,
        );
      default:
        break;
    }
  }

  void _appendText(ClineStepKind kind, String? delta) {
    if (delta == null || delta.isEmpty) return;
    if (_steps.isNotEmpty && _steps.last.kind == kind) {
      final last = _steps.removeLast();
      _steps.add(last.copyWith(text: last.text + delta));
    } else {
      _push(ClineStep(kind: kind, text: delta));
    }
    state = state.copyWith(steps: List.unmodifiable(_steps));
  }

  void _finishTool(String? name, String? result) {
    for (var i = _steps.length - 1; i >= 0; i--) {
      final s = _steps[i];
      if (s.kind == ClineStepKind.tool && s.pending && (name == null || s.tool == name)) {
        _steps[i] = s.copyWith(result: result, pending: false);
        break;
      }
    }
    state = state.copyWith(steps: List.unmodifiable(_steps));
  }

  void _replace(ClineStep old, ClineStep next) {
    final i = _steps.indexOf(old);
    if (i >= 0) _steps[i] = next;
    state = state.copyWith(steps: List.unmodifiable(_steps));
  }

  void _push(ClineStep step) {
    _steps.add(step);
    state = state.copyWith(steps: List.unmodifiable(_steps));
  }

  static String _stringify(Object? v) {
    if (v == null) return '';
    final s = '$v';
    return s.length > 1200 ? '${s.substring(0, 1200)}…' : s;
  }
}

final clineAgentProvider =
    NotifierProvider<ClineAgentNotifier, ClineAgentState>(
        ClineAgentNotifier.new);
