// AI section UI.
// - Red shimmering "MIDE" header
// - "MIDE" wordmark with the AI disclaimer
// - Horde / Pollinations provider badge (cross-fades on provider change)
// - Send/stop button (clean quick swap, no stickiness)
// - "Ассистент занят, попробуй позже!" error card
// - While thinking: a bare red blinking underscore (no bubble). When the
//   answer lands it cross-fades into the finished bubble.
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_model.dart';
import '../ide/ide_entry.dart';
import 'ai_providers.dart';

// Sub-widgets of the AI screen. They are `part`s rather than separate
// libraries because they are private to this tab and share its imports;
// keeping them here-in-file was what made this file 1458 lines.
part 'ai_chat_composer.dart';
part 'ai_chat_header.dart';
part 'ai_chat_messages.dart';
part 'ai_chat_topics.dart';

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
    (
      'Прогнозы',
      Icons.trending_up_rounded,
      'Сделай краткий прогноз: погода, курс валют, рынки — по существу, 2-3 строки.',
    ),
    (
      'Дизайн',
      Icons.palette_rounded,
      'Предложи 3 идеи по дизайну (цвета, шрифт, компоновка) для мобильного приложения в стиле Material You.',
    ),
    (
      'Кулинария',
      Icons.restaurant_rounded,
      'Придумай быстрый рецепт на 15 минут из простых продуктов. Калории и шаги.',
    ),
    (
      'Код',
      Icons.code_rounded,
      'Напиши короткий, читаемый фрагмент кода (Dart/Flutter) с объяснением в 2 строки.',
    ),
    (
      'Фитнес',
      Icons.self_improvement_rounded,
      'Дай 3-минутную тренировку без железа. Упражнения, подход, отдых.',
    ),
    (
      'Финансы',
      Icons.savings_rounded,
      'Как быстро и реально сэкономить 500 руб в неделю? Практично, без воды.',
    ),
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

  /// Re-sends the most recent user message after a failure.
  void _retry() {
    final s = ref.read(aiSessionProvider);
    if (s.busy) return;
    final lastUser = s.messages.lastWhere(
      (m) => m.role == AiRole.user,
      orElse: () => const AiMessage(AiRole.user, ''),
    );
    if (lastUser.text.trim().isEmpty) return;
    ref.read(aiSessionProvider.notifier).send(lastUser.text);
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
          _input.selection = TextSelection.collapsed(offset: prompt.length);
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
            // Row 1: icon + persona name + AI badge ... topic buttons.
            Row(
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: Image.asset('assets/icon/mide.png', fit: BoxFit.cover),
                ),
                const SizedBox(width: 12),
                const Flexible(
                  child: _ShimmerTitle(
                    text: 'Ada Cry (Ада Край)',
                    fontSize: 21,
                  ),
                ),
                const SizedBox(width: 8),
                const _Badge(text: 'AI'),
                const Spacer(),
                _HeaderIconButton(
                  icon: Icons.cleaning_services_rounded,
                  tooltip: 'Очистить чат',
                  onTap: s.messages.isEmpty && s.error == null
                      ? null
                      : () => notifier.clear(),
                ),
                const SizedBox(width: 4),
                _TopicsButton(onTap: () => _showTopics(context)),
              ],
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                'AI Can Make Mistakes.',
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: Theme.of(context).colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.5),
                ),
              ),
            ),
            const SizedBox(height: 12),
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
                        if (s.error != null)
                          _AnimatedErrorCard(text: s.error!, onRetry: _retry),
                      ],
                    ),
            ),
            const SizedBox(height: 10),
            _Composer(
              busy: s.busy,
              controller: _input,
              hint: 'Спроси что угодно…',
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
