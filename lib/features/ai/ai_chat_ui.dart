// Ada (M.AI) section UI.
// - Red shimmering "АДУСЯ" header
// - "Ада_" with breathing underscore
// - Horde / Pollinations provider badge (cross-fades on provider change)
// - Send/stop button (clean quick swap, no stickiness)
// - "Ада занята, попробуй позже!" error card
// - While thinking: a bare red blinking underscore (no bubble). When the
//   answer lands it cross-fades into the finished bubble.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_model.dart';
import '../ide/ide_entry.dart';
import 'ai_providers.dart';

class AiTab extends ConsumerStatefulWidget {
  const AiTab({super.key});

  @override
  ConsumerState<AiTab> createState() => _AiTabState();
}

class _AiTabState extends ConsumerState<AiTab> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  /// Topic presets that open in the "⋮" menu. Each one is a short,
  /// well-scoped prompt that gets injected into the composer on tap.
  static const _topics = <(String, IconData, String)>[
    ('Прогнозы', Icons.trending_up_rounded,
        'Сделай краткий прогноз: погода, курс валют, рынки — по существу, 2-3 строки.'),
    ('Дизайн', Icons.palette_rounded,
        'Предложи 3 идеи по дизайну (цвета, шрифт, компоновка) для мобильного приложения в стиле Material You.'),
    ('Кулинария', Icons.restaurant_rounded,
        'Придумай быстрый рецепт на 15 минут из простых продуктов. Калории и шаги.'),
    ('Код', Icons.code_rounded,
        'Напиши короткий, читаемый фрагмент кода (Dart/Flutter) с объяснением в 2 строки.'),
    ('Фитнес', Icons.self_improvement_rounded,
        'Дай 3-минутную тренировку без железа. Упражнения, подход, отдых.'),
    ('Финансы', Icons.savings_rounded,
        'Как быстро и реально сэкономить 500 руб в неделю? Практично, без воды.'),
  ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final s = ref.read(aiSessionProvider);
    final text = _input.text;
    if (s.busy || text.trim().isEmpty) return;
    ref.read(aiSessionProvider.notifier).send(text);
    _input.clear();
    _scrollToBottom();
  }

  /// Opens the smooth, small rounded topic sheet. Each topic tap fills the
  /// composer with its prompt so the user can send immediately.
  void _showTopics(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (_) => _TopicSheet(
        topics: _topics,
        onPick: (prompt) {
          Navigator.pop(context);
          _input.text = prompt;
          _input.selection =
              TextSelection.collapsed(offset: prompt.length);
          setState(() {});
        },
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(aiSessionProvider);
    final notifier = ref.read(aiSessionProvider.notifier);

    return Scaffold(
      backgroundColor: Colors.transparent,
      // System smooth keyboard resize (the compositor animates the inset,
      // so the field glides up and down with no jank and no overlap).
      body: SafeArea(
        bottom: true,

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 14),
            // Row 1: icon + АДУСЯ + M.AI ... "⋮" topic button (clear, alone).
            Row(
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: Image.asset('assets/icon/mide.png', fit: BoxFit.cover),
                ),
                const SizedBox(width: 12),
                const _ShimmerTitle(text: 'АДУСЯ'),
                const SizedBox(width: 8),
                const _Badge(text: 'M.AI'),
                const Spacer(),
                _TopicsButton(onTap: () => _showTopics(context)),
              ],
            ),
            const SizedBox(height: 14),
            // Row 2: "Ада_" centered with the disclaimer under it.
            Center(
              child: _AdaBrand(
                fontSize: 28,
                subtitle: 'AGI Can Make Mistakes.',
              ),
            ),
            const SizedBox(height: 12),
            // Row 3: provider controls — compact and tidy.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const _HordeKeyButton(),
                const SizedBox(width: 10),
                _ProviderBadge(label: s.providerLabel),
              ],
            ),
            const SizedBox(height: 14),
            // PC-only shortcut into the built-in code IDE (hidden on mobile/web).
            const IdeEntryPill(),
            const SizedBox(height: 12),

            Expanded(
              child: s.messages.isEmpty
                  ? const SizedBox.shrink()
                  : ListView(
                      controller: _scroll,
                      children: [
                        for (final m in s.messages) _AnimatedBubble(message: m),
                        if (s.error != null) _AnimatedErrorCard(text: s.error!),
                      ],
                    ),
            ),
            const SizedBox(height: 10),
            _Composer(
              busy: s.busy,
              controller: _input,
              hint: 'Ада жаждет...',
              onSend: _send,
              onStop: notifier.cancel,
            ),
            // Small breathing room above the pill bar so the field never
            // sits on top of the section content.
            const SizedBox(height: 26),
          ],
        ),
      ),
    );
  }
}

// ── Shimmer title ──────────────────────────────────────────────────────────

class _ShimmerTitle extends StatefulWidget {
  final String text;
  const _ShimmerTitle({required this.text});

  @override
  State<_ShimmerTitle> createState() => _ShimmerTitleState();
}

class _ShimmerTitleState extends State<_ShimmerTitle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final red = Theme.of(context).colorScheme.error;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final center = -0.25 + 1.5 * t;
        const w = 0.2;
        final s1 = (center - w).clamp(0.0, 1.0);
        final s2 = (center - w * 0.45).clamp(0.0, 1.0);
        final s3 = center.clamp(0.0, 1.0);
        final s4 = (center + w * 0.45).clamp(0.0, 1.0);
        final s5 = (center + w).clamp(0.0, 1.0);
        final gloss =
            Color.alphaBlend(Colors.white.withValues(alpha: 0.85), red);
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (b) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [red, red, gloss, red, red],
            stops: [s1, s2, s3, s4, s5],
          ).createShader(b),
          child: Text(
            widget.text,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
        );
      },
    );
  }
}

// ── M.AI badge ─────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final String text;
  const _Badge({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

// ── Provider badge (Horde / Pollinations) — cross-fades on change ─────────

class _ProviderBadge extends StatelessWidget {
  final String label;
  const _ProviderBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        // Layered, premium look: a soft gradient fill + a crisp outline +
        // a subtle inner top highlight that reads as glassy/expensive.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.9),
            scheme.surfaceContainerHighest,
          ],
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.4),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.22),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.9, end: 1.0).animate(anim),
            child: child,
          ),
        ),
        child: Row(
          key: ValueKey('provider_$label'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(Icons.smart_toy_rounded,
                  size: 14, color: scheme.onPrimary),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── "Ада_" brand with breathing underscore ───────────────────────────────

/// Small "Horde API" button next to the provider badge.
/// Opens a bottom sheet where the user pastes their free stablehorde.net
/// API key; the key is persisted in secure storage and injected into the
/// rotation on the next request.
class _HordeKeyButton extends ConsumerWidget {
  const _HordeKeyButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final keySet = ref.watch(hordeKeyProvider).trim().isNotEmpty;
    return GestureDetector(
      onTap: () => _showKeySheet(context, ref),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: keySet
                ? [
                    scheme.primaryContainer,
                    scheme.primary.withValues(alpha: 0.55),
                  ]
                : [
                    scheme.surfaceContainerHighest,
                    scheme.surfaceContainerHigh,
                  ],
          ),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: keySet
                ? scheme.primary.withValues(alpha: 0.6)
                : scheme.outlineVariant.withValues(alpha: 0.6),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: keySet
                  ? scheme.primary.withValues(alpha: 0.28)
                  : Colors.black.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: keySet
                    ? scheme.onPrimaryContainer
                    : scheme.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(
                Icons.key_rounded,
                size: 14,
                color: keySet
                    ? scheme.onPrimaryContainer
                    : scheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Horde',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
                color: keySet
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showKeySheet(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final current = ref.read(hordeKeyProvider);
    final ctrl = TextEditingController(text: current);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              Text(
                'Horde API-ключ (бесплатно)',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface),
              ),
              const SizedBox(height: 6),
              Text(
                'Зарегистрируйся на stablehorde.net (без карты) и вставь ключ —\n'
                    'Horde станет основным провайдером Ады.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: TextField(
                  controller: ctrl,
                  obscureText: true,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'API-ключ',
                    hintText: 'например: a1b2c3…',
                    prefixIcon: Icon(Icons.vpn_key_rounded),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          ref
                              .read(hordeKeyProvider.notifier)
                              .set(ctrl.text.trim());
                          Navigator.pop(ctx);
                        },
                        child: const Text('Сохранить'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          ref.read(hordeKeyProvider.notifier).clear();
                          Navigator.pop(ctx);
                        },
                        child: Text('Удалить',
                            style: TextStyle(color: scheme.error)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

class _AdaBrand extends StatefulWidget {
  const _AdaBrand({super.key, this.fontSize = 20, this.subtitle});

  /// Larger brand for the top-center placement.
  final double fontSize;

  /// Optional disclaimer line shown under the brand when centered.
  final String? subtitle;

  @override
  State<_AdaBrand> createState() => _AdaBrandState();
}

class _AdaBrandState extends State<_AdaBrand>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brand = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'Ада',
          style: TextStyle(
            color: scheme.onSurface,
            fontSize: widget.fontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            final o = 0.15 + 0.85 * Curves.easeInOut.transform(_c.value);
            return Opacity(
              opacity: o,
              child: Text(
                '_',
                style: TextStyle(
                  color: scheme.primary,
                  fontSize: widget.fontSize * 1.1,
                  height: 0.8,
                  fontWeight: FontWeight.w800,
                ),
              ),
            );
          },
        ),
      ],
    );

    if (widget.subtitle == null) return brand;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        brand,
        const SizedBox(height: 6),
        Text(
          widget.subtitle!,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            letterSpacing: 0.3,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}

// ── Animated chat bubble ───────────────────────────────────────────────────
// Own messages fade + scale in smoothly. Ada's reply: while waiting a bare
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
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
  late final Animation<double> _fade =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  late final Animation<double> _scale =
      Tween<double>(begin: 0.94, end: 1.0).animate(_fade);

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

  const _BubbleBody(
      {super.key,
      required this.isUser,
      required this.text,
      required this.scheme});

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
            : Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.4)),
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

/// Ada's "thinking" indicator — a bare red blinking underscore (no bubble),
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

  const _AnimatedErrorCard({required this.text});

  @override
  State<_AnimatedErrorCard> createState() => _AnimatedErrorCardState();
}

class _AnimatedErrorCardState extends State<_AnimatedErrorCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 350))
        ..forward();
  late final Animation<double> _fade =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

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
              Icon(Icons.cloud_off_rounded,
                  size: 20, color: scheme.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ада занята',
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
                        color:
                            scheme.onErrorContainer.withValues(alpha: 0.85),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
                // The field stays enabled even while Ada is busy so the
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
                        shaderCallback: (b) => LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: const [
                            Colors.transparent,
                            Colors.white,
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.5, 1.0],
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
                    ? Icon(Icons.stop_rounded,
                        key: const ValueKey('stop'),
                        size: 26,
                        color: scheme.onError)
                    : Icon(Icons.send_rounded,
                        key: const ValueKey('send'),
                        size: 26,
                        color: scheme.onPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// в”Ђв”Ђ Topics menu в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ

/// Small rounded "в‹®" button that sits under the provider badge. Tapping opens
/// a smooth, premium bottom sheet of topic presets.
class _TopicsButton extends StatelessWidget {
  final VoidCallback onTap;
  const _TopicsButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.primaryContainer.withValues(alpha: 0.9),
                scheme.surfaceContainerHighest,
              ],
            ),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.22),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(Icons.more_horiz_rounded, size: 20, color: scheme.primary),
        ),
      ),
    );
  }
}

/// The smooth rounded bottom sheet listing topic presets. Each row fades and
/// slides in with a stagger delay. Tapping injects the prompt into the
/// composer so the user can send immediately.
class _TopicSheet extends StatelessWidget {
  final List<(String, IconData, String)> topics;
  final void Function(String prompt) onPick;
  const _TopicSheet({required this.topics, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final h = MediaQuery.of(context).size.height;
    return Padding(
      padding: EdgeInsets.only(bottom: h * 0.12),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.surfaceContainerHigh, scheme.surfaceContainerHighest],
          ),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: scheme.primary.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Grabber.
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Title.
            Text(
              'Р’С‹Р±СЂР°С‚СЊ С‚РµРјСѓ РґР»СЏ РђРґС‹',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            // Topic rows with staggered entrance.
            for (var i = 0; i < topics.length; i++)
              _StaggeredFade(
                delay: i * 50,
                child: _TopicRow(
                  title: topics[i].$1,
                  icon: topics[i].$2,
                  scheme: scheme,
                  onTap: () => onPick(topics[i].$3),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Fades + slides a child in after a stagger delay (cascade effect).
class _StaggeredFade extends StatefulWidget {
  final int delay;
  final Widget child;
  const _StaggeredFade({required this.delay, required this.child});

  @override
  State<_StaggeredFade> createState() => _StaggeredFadeState();
}

class _StaggeredFadeState extends State<_StaggeredFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
    value: 0.0,
  );

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Opacity(
        opacity: _c.value,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - _c.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// One row inside the topic sheet.
class _TopicRow extends StatelessWidget {
  final String title;
  final IconData icon;
  final ColorScheme scheme;
  final VoidCallback onTap;
  const _TopicRow({
    required this.title,
    required this.icon,
    required this.scheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: scheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

