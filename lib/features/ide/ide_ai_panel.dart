// PC-only IDE — right AI coding panel (Kilo / LLM7 / OVHcloud).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_model.dart';
import 'ide_ai.dart';
import 'ide_providers.dart';

/// Right sidebar: quick coding actions + chat with the active file attached.
class IdeAiPanel extends ConsumerStatefulWidget {
  const IdeAiPanel({super.key});

  @override
  ConsumerState<IdeAiPanel> createState() => _IdeAiPanelState();
}

class _IdeAiPanelState extends ConsumerState<IdeAiPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  static const _actions = <(String, IconData, String)>[
    ('Объясни', Icons.help_outline_rounded,
        'Кратко объясни, что делает этот код, построчно.'),
    ('Баги', Icons.bug_report_outlined,
        'Найди ошибки в этом файле и дай исправления по пунктам.'),
    ('Тесты', Icons.science_outlined,
        'Напиши тесты для этого файла — полный файл одним код-блоком.'),
    ('Рефактор', Icons.auto_fix_high_rounded,
        'Отрефактори файл: упрости, убери дубли, сохрани поведение.'),
    ('Докстринг', Icons.article_outlined,
        'Добавь докстринги к публичным элементам. Полный файл.'),
  ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send([String? preset]) {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty) return;
    if (preset == null) _input.clear();
    ref.read(ideAiProvider.notifier).ask(text);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ai = ref.watch(ideAiProvider);

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(
          left: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
            child: Row(
              children: [
                Icon(Icons.auto_awesome_rounded, size: 16, color: scheme.primary),
                const SizedBox(width: 7),
                Text(
                  'Кодинг-ИИ',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
                const Spacer(),
                _AiProviderBadge(label: ai.providerLabel),
                IconButton(
                  tooltip: 'Kilo API-ключ (бесплатный)',
                  onPressed: _showKiloKeyDialog,
                  icon: Icon(Icons.vpn_key_rounded,
                      size: 16, color: scheme.onSurfaceVariant),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final (label, icon, prompt) in _actions)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ActionChip(
                      avatar: Icon(icon, size: 14, color: scheme.primary),
                      label: Text(label,
                          style: const TextStyle(
                              fontSize: 11.5, fontWeight: FontWeight.w700)),
                      onPressed: ai.busy ? null : () => _send(prompt),
                      visualDensity: VisualDensity.compact,
                      side: BorderSide(
                          color: scheme.primary.withValues(alpha: 0.35)),
                      backgroundColor:
                          scheme.primaryContainer.withValues(alpha: 0.55),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Divider(height: 1),
          Expanded(
            child: ai.messages.isEmpty && ai.error == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Text(
                        'Файл уходит в Kilo / LLM7 / OVH автоматически.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: scheme.onSurfaceVariant),
                      ),
                    ),
                  )
                : ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    children: [
                      for (final m in ai.messages)
                        _AiBubble(
                          message: m,
                          onApply: m.role == AiRole.assistant
                              ? () => _applyCode(m.text)
                              : null,
                        ),
                      if (ai.busy) _TypingRow(label: ai.providerLabel),
                      if (ai.error != null)
                        _ErrorCard(text: ai.error!, onKiloKey: _showKiloKeyDialog),
                    ],
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'Спроси про открытый файл…',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 46,
                  height: 46,
                  child: FilledButton(
                    onPressed: ai.busy
                        ? () => ref.read(ideAiProvider.notifier).cancel()
                        : _send,
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      backgroundColor: ai.busy
                          ? scheme.errorContainer
                          : scheme.primary,
                    ),
                    child: Icon(
                      ai.busy ? Icons.stop_rounded : Icons.arrow_upward_rounded,
                      size: 20,
                      color: ai.busy ? scheme.onErrorContainer : scheme.onPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),

        ],
      ),
    );
  }

  /// Free Kilo key dialog — the key is optional (LLM7/OVH work keyless).
  void _showKiloKeyDialog() {
    final ref0 = ref;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        final ctrl = TextEditingController(
          text: ref0.read(kiloKeyProvider),
        );
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kilo API-ключ',
                    style: Theme.of(ctx)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                  'Бесплатно на app.kilo.ai (без карты). Без ключа ротация '
                  'просто пропускает Kilo и отвечает LLM7 / OVH.',
                  style: TextStyle(
                      fontSize: 12.5, height: 1.45, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: ctrl,
                  obscureText: true,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Kilo API key',
                    hintText: 'kilo_… или JWT',
                    prefixIcon: Icon(Icons.vpn_key_rounded),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          ref0.read(kiloKeyProvider.notifier).set(ctrl.text);
                          Navigator.pop(ctx);
                        },
                        child: const Text('Сохранить'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          ref0.read(kiloKeyProvider.notifier).clear();
                          Navigator.pop(ctx);
                        },
                        child:
                            Text('Удалить', style: TextStyle(color: scheme.error)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Replaces the active buffer with the first ``` code block of [text].
  void _applyCode(String text) {
    final code = _extractFirstCodeBlock(text);
    final tab = ref.read(ideTabsProvider).activeTab;
    if (code == null || code.trim().isEmpty) {
      _snack('В ответе нет код-блока');
      return;
    }
    if (tab == null) {
      _snack('Сначала открой файл');
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Заменить файл?'),
        content: Text(
          'Буфер «${tab.name}» будет полностью заменён кодом из ответа. '
          'Сохранить — Ctrl+S.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              ref
                  .read(ideTabsProvider.notifier)
                  .setContent(tab.path, code);
              Navigator.pop(ctx);
              _snack('Код вставлен — Ctrl+S для записи');
            },
            child: const Text('Заменить'),
          ),
        ],
      ),
    );
  }

  /// First ```-fenced block without the language line, or null.
  String? _extractFirstCodeBlock(String text) {
    final start = text.indexOf('```');
    if (start < 0) return null;
    final bodyStart = start + 3;
    final end = text.indexOf('```', bodyStart);
    if (end < 0) return null;
    var body = text.substring(bodyStart, end);
    final nl = body.indexOf('\n');
    if (nl >= 0 && nl < 40) body = body.substring(nl + 1);
    return body.trimRight();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }
}

/// Cross-fading pill showing the provider that answered last.
class _AiProviderBadge extends StatelessWidget {
  const _AiProviderBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primaryContainer,
            scheme.secondaryContainer.withValues(alpha: 0.7),
          ],
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(scale: anim, child: child),
        ),
        child: Row(
          key: ValueKey(label),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt_rounded, size: 13, color: scheme.primary),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Thinking" row shown while a provider request is in flight.
class _TypingRow extends StatelessWidget {
  const _TypingRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            '$label генерирует код…',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Red-tinted failure card; Kilo errors offer the key dialog inline.
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.text, required this.onKiloKey});

  final String text;
  final VoidCallback onKiloKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isKilo = text.contains('Kilo') || text.contains('403');
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.error.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline_rounded, size: 16, color: scheme.error),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: scheme.onErrorContainer),
                ),
              ),
            ],
          ),
          if (isKilo) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onKiloKey,
              icon: const Icon(Icons.vpn_key_rounded, size: 15),
              label: const Text('Вставить бесплатный ключ Kilo'),
              style: TextButton.styleFrom(
                foregroundColor: scheme.error,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One chat bubble; assistant messages render ``` blocks as styled code
/// panels and expose copy / apply actions.
class _AiBubble extends StatelessWidget {
  const _AiBubble({required this.message, this.onApply});

  final AiMessage message;
  final VoidCallback? onApply;

  /// Splits [text] into (isCode, chunk) pairs on ``` fences.
  static List<(bool, String)> _segments(String text) {
    final out = <(bool, String)>[];
    final parts = text.split('```');
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (part.isEmpty) continue;
      if (i.isOdd) {
        final nl = part.indexOf('\n');
        out.add((true, nl >= 0 && nl < 40 ? part.substring(nl + 1) : part));
      } else {
        out.add((false, part));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.role == AiRole.user;
    final hasCode = message.text.contains('```');

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: const BoxConstraints(maxWidth: 460),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        decoration: BoxDecoration(
          color: isUser
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest.withValues(alpha: 0.85),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 6),
            bottomRight: Radius.circular(isUser ? 6 : 18),
          ),
          border: Border.all(
            color: isUser
                ? scheme.primary.withValues(alpha: 0.35)
                : scheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (isCode, chunk) in _segments(message.text))
              if (isCode)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.8)),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(
                      chunk,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: scheme.onSurface,
                        fontFamilyFallback: const [
                          'Consolas',
                          'DejaVu Sans Mono',
                          'monospace',
                        ],
                      ),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    chunk.trim(),
                    style: TextStyle(
                        fontSize: 13, height: 1.5, color: scheme.onSurface),
                  ),
                ),
            if (!isUser)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Копировать',
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: message.text)),
                    icon: Icon(Icons.copy_rounded,
                        size: 15, color: scheme.onSurfaceVariant),
                    visualDensity: VisualDensity.compact,
                  ),
                  if (onApply != null && hasCode)
                    TextButton.icon(
                      onPressed: onApply,
                      icon: const Icon(Icons.download_rounded, size: 15),
                      label: const Text('В файл'),
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.primary,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}



