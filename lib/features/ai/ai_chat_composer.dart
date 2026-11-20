part of 'ai_chat_ui.dart';

// ── Composer ───────────────────────────────────────────────────────────────

class _Composer extends StatefulWidget {
  final bool busy;
  final TextEditingController controller;
  final String hint;
  final VoidCallback onSend;
  final VoidCallback onStop;

  const _Composer({
    required this.busy,
    required this.controller,
    required this.hint,
    required this.onSend,
    required this.onStop,
  });

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer>
    with SingleTickerProviderStateMixin {
  final _focusNode = FocusNode();

  /// Smoothly settles the freshly-typed text into view instead of popping.
  late final AnimationController _fadeCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1.0,
  );
  int _lastLen = 0;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() => setState(() {}));
    widget.controller.addListener(_onTextChanged);
  }

  /// Each keystroke (type or delete) gently fades the input text back in,
  /// so letters appear and disappear smoothly rather than snapping.
  void _onTextChanged() {
    final len = widget.controller.text.length;
    if (len == _lastLen) return;
    _lastLen = len;
    _fadeCtrl
      ..value = 0.4
      ..animateTo(
        1.0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
  }

  /// Send, then keep the caret in the field so the keyboard stays open.
  /// On Android the "send" IME action auto-hides the keyboard, so we
  /// re-request focus one frame later to reliably win that race.
  void _sendThenFocus() {
    widget.onSend();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final focused = _focusNode.hasFocus;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: focused
              ? scheme.primary.withValues(alpha: 0.8)
              : scheme.outlineVariant.withValues(alpha: 0.5),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: focused
                ? scheme.primary.withValues(alpha: 0.20)
                : Colors.black.withValues(alpha: 0.06),
            blurRadius: focused ? 14 : 4,
            spreadRadius: focused ? 2 : 0,
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            // The TextField is built once and stays stable; only the
            // Opacity layer re-runs each animation frame. Each keystroke
            // gently fades the input text back in (0.4 -> 1.0, 220 ms)
            // so letters appear and disappear smoothly instead of snapping.
            child: AnimatedBuilder(
              animation: _fadeCtrl,
              builder: (context, child) =>
                  Opacity(opacity: _fadeCtrl.value, child: child),
              child: TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                // The field stays enabled even while the assistant is busy so the
                // keyboard and focus are kept alive after sending.
                autofocus: false,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendThenFocus(),
                // 16px avoids the mobile-browser auto-zoom ("magnifier")
                // that used to jump the letters when the field focused.
                style: TextStyle(
                  fontSize: 16,
                  color: scheme.onSurface,
                  height: 1.3,
                ),
                // Smooth rounded breathing caret (no hard square blink).
                cursorColor: scheme.primary,
                cursorWidth: 1.6,
                cursorRadius: const Radius.circular(0.8),
                cursorOpacityAnimates: true,
                showCursor: true,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  hintStyle: TextStyle(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                  filled: false,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          _SendStopButton(
            busy: widget.busy,
            onSend: _sendThenFocus,
            onStop: widget.onStop,
            scheme: scheme,
          ),
        ],
      ),
    );
  }
}

// ── Send/Stop button — premium, bigger, with smooth looping gloss ────────

class _SendStopButton extends StatefulWidget {
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final ColorScheme scheme;

  const _SendStopButton({
    required this.busy,
    required this.onSend,
    required this.onStop,
    required this.scheme,
  });

  @override
  State<_SendStopButton> createState() => _SendStopButtonState();
}

class _SendStopButtonState extends State<_SendStopButton>
    with SingleTickerProviderStateMixin {
  /// Continuous gloss sweep. A sine oscillation over one cycle makes the
  /// start and end of each loop identical (seamless, no visible seam).
  late final AnimationController _glossCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat();

  @override
  void dispose() {
    _glossCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = widget.scheme;
    final color = widget.busy ? scheme.error : scheme.primary;
    final light = Color.lerp(color, Colors.white, 0.18)!;

    // Only the moving gloss layer re-runs each frame; the static circle and
    // the send/stop icon cross-fade stay stable.
    return SizedBox(
      width: 52,
      height: 52,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: widget.busy ? widget.onStop : widget.onSend,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Gradient + glow background (animates only on busy change).
              AnimatedContainer(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeInOut,
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [light, color],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.38),
                      blurRadius: 14,
                      spreadRadius: 1,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
              ),
              // Sweeping gloss (seamless sine loop).
              AnimatedBuilder(
                animation: _glossCtrl,
                builder: (context, _) {
                  final v = _glossCtrl.value;
                  final sweep = math.sin(v * math.pi); // 0 → 1 → 0
                  final x = -34.0 + sweep * 68.0;
                  return Transform.translate(
                    offset: Offset(x, 0),
                    child: ClipOval(
                      child: ShaderMask(
                        blendMode: BlendMode.srcIn,
                        shaderCallback: (b) => const LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.transparent,
                            Colors.white,
                            Colors.transparent,
                          ],
                          stops: [0.0, 0.5, 1.0],
                        ).createShader(b),
                        child: const SizedBox(width: 52, height: 52),
                      ),
                    ),
                  );
                },
              ),
              // Icon cross-fade (reacts only to busy).
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeInOut,
                switchOutCurve: Curves.easeInOut,
                child: widget.busy
                    ? Icon(
                        Icons.stop_rounded,
                        key: const ValueKey('stop'),
                        size: 26,
                        color: scheme.onError,
                      )
                    : Icon(
                        Icons.send_rounded,
                        key: const ValueKey('send'),
                        size: 26,
                        color: scheme.onPrimary,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
