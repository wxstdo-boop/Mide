part of 'ai_chat_ui.dart';

// ── Animated chat bubble ───────────────────────────────────────────────────
// Own messages fade + scale in smoothly. The assistant's reply: while waiting a bare
// red blinking underscore shows; when the answer lands it cross-fades into
// the finished bubble.

class _AnimatedBubble extends StatefulWidget {
  final AiMessage message;

  const _AnimatedBubble({required this.message});

  @override
  State<_AnimatedBubble> createState() => _AnimatedBubbleState();
}

class _AnimatedBubbleState extends State<_AnimatedBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutCubic,
  );
  late final Animation<double> _scale = Tween<double>(
    begin: 0.94,
    end: 1.0,
  ).animate(_fade);

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final m = widget.message;
    final isUser = m.role == AiRole.user;
    final waiting = m.streaming && m.text.isEmpty;
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: Alignment.center,
          child: Align(
            alignment: Alignment.center,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 360),
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: waiting
                  ? const _ThinkingCaret(key: ValueKey('think'))
                  : _BubbleBody(
                      key: const ValueKey('body'),
                      isUser: isUser,
                      text: m.text,
                      scheme: scheme,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The finished message bubble (user or assistant).
class _BubbleBody extends StatelessWidget {
  final bool isUser;
  final String text;
  final ColorScheme scheme;

  const _BubbleBody({
    super.key,
    required this.isUser,
    required this.text,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 28, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      constraints: const BoxConstraints(maxWidth: 420),
      decoration: BoxDecoration(
        color: isUser
            ? scheme.primary.withValues(alpha: 0.92)
            : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: isUser
            ? null
            : Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13.5,
          height: 1.4,
          color: isUser ? scheme.onPrimary : scheme.onSurface,
        ),
      ),
    );
  }
}

/// The assistant's "thinking" indicator — a bare red blinking underscore (no bubble),
/// shown while the answer is in flight.
class _ThinkingCaret extends StatefulWidget {
  const _ThinkingCaret({super.key});

  @override
  State<_ThinkingCaret> createState() => _ThinkingCaretState();
}

class _ThinkingCaretState extends State<_ThinkingCaret>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Smooth sine-wave blink, 0.1 → 1.0 → 0.1.
    final o = 0.1 + 0.9 * Curves.easeInOut.transform(_c.value);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 3),
      child: Opacity(
        opacity: o,
        child: Text(
          '_',
          style: TextStyle(
            color: scheme.error,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

// ── Error card ─────────────────────────────────────────────────────────────

class _AnimatedErrorCard extends StatefulWidget {
  final String text;
  final VoidCallback? onRetry;

  const _AnimatedErrorCard({required this.text, this.onRetry});

  @override
  State<_AnimatedErrorCard> createState() => _AnimatedErrorCardState();
}

class _AnimatedErrorCardState extends State<_AnimatedErrorCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  )..forward();
  late final Animation<double> _fade = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutCubic,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.94, end: 1.0).animate(_fade),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: scheme.errorContainer.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: scheme.error.withValues(alpha: 0.45)),
            boxShadow: [
              BoxShadow(
                color: scheme.error.withValues(alpha: 0.18),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: 20,
                color: scheme.onErrorContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ассистент занят',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: scheme.onErrorContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Попробуй позже!',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onErrorContainer.withValues(alpha: 0.85),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.onRetry != null)
                IconButton(
                  onPressed: widget.onRetry,
                  tooltip: 'Повторить',
                  icon: Icon(
                    Icons.refresh_rounded,
                    size: 20,
                    color: scheme.onErrorContainer,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
