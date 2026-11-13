part of '../../main.dart';

// ---------------------------------------------------------------------------
// 3D tab — a procedural, rotatable AI companion ("Мира").
//
// There is no glTF asset: the figure is built from a small set of shaded
// spheres projected with a hand-rolled perspective camera, so it renders
// everywhere (including Web) with zero native dependencies. The mood the user
// picks tints the aura and drives the pose; chat goes through the shared
// persona session, so the companion has her own persisted conversation.
// ---------------------------------------------------------------------------

/// Persona + storage key for the companion's chat (kept apart from Ada's).
const PersonaArg kCompanionPersona = PersonaArg(
  systemPrompt:
      'Ты — Мира, дружелюбная 3D-компаньонка внутри приложения Mide. '
      'Отвечай тепло, живо и коротко (1–3 предложения), в языке пользователя. '
      'Можешь кокетничать, но без пошлости.',
  chatKey: 'mide_ai_chat_companion_v1',
);

/// Mood presets: label + the accent that tints the aura and the hair sheen.
class _Mood {
  const _Mood(this.label, this.icon, this.accent);
  final String label;
  final IconData icon;
  final Color accent;
}

const List<_Mood> _moods = <_Mood>[
  _Mood('Нежность', Icons.favorite_rounded, Color(0xFFFF7EB6)),
  _Mood('Радость', Icons.wb_sunny_rounded, Color(0xFFFFC24B)),
  _Mood('Загадка', Icons.nightlight_round, Color(0xFF9B7BFF)),
  _Mood('Драйв', Icons.bolt_rounded, Color(0xFF39E0C8)),
  _Mood('Печаль', Icons.water_drop_rounded, Color(0xFF6FA8FF)),
];

class CompanionTab extends ConsumerStatefulWidget {
  const CompanionTab({super.key});

  @override
  ConsumerState<CompanionTab> createState() => _CompanionTabState();
}

class _CompanionTabState extends ConsumerState<CompanionTab> {
  final _input = TextEditingController();
  int _mood = 0;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    final session = ref.read(personaSessionProvider(kCompanionPersona));
    if (session.busy) return;
    ref
        .read(personaSessionProvider(kCompanionPersona).notifier)
        .send(text);
    _input.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final session = ref.watch(personaSessionProvider(kCompanionPersona));
    final notifier =
        ref.read(personaSessionProvider(kCompanionPersona).notifier);
    final mood = _moods[_mood];

    // The last assistant line is her "voice"; fall back to a greeting.
    final lastAssistant = session.messages.lastWhere(
      (m) => m.role == AiRole.assistant && m.text.trim().isNotEmpty,
      orElse: () => const AiMessage(AiRole.assistant, ''),
    );
    final speech = session.error != null
        ? 'Мира задумалась… повтори чуть позже!'
        : (lastAssistant.text.isNotEmpty
            ? lastAssistant.text
            : 'Привет! Я Мира — выбери настроение и напиши мне.');

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: _AppHeader(
                image: 'assets/icon/mide.png',
                title: 'Мира',
                version: '3D',
                actions: [
                  IconButton.filledTonal(
                    tooltip: 'Очистить чат',
                    onPressed: () => notifier.clear(),
                    icon: const Icon(Icons.cleaning_services_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _CompanionStage(
                mood: mood,
                accent: mood.accent,
                scheme: scheme,
              ),
            ),
            // Mood picker.
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _moods.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final m = _moods[i];
                  final selected = i == _mood;
                  return _MoodChip(
                    mood: m,
                    selected: selected,
                    onTap: () => setState(() => _mood = i),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            // Speech bubble.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _SpeechBubble(
                text: speech,
                accent: mood.accent,
                thinking: session.busy,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: _CompanionComposer(
                controller: _input,
                busy: session.busy,
                accent: mood.accent,
                onSend: _send,
                onStop: notifier.cancel,
              ),
            ),
            const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }
}

// ── Stage: the animated 3D viewport ────────────────────────────────────────

class _CompanionStage extends StatefulWidget {
  const _CompanionStage({
    required this.mood,
    required this.accent,
    required this.scheme,
  });

  final _Mood mood;
  final Color accent;
  final ColorScheme scheme;

  @override
  State<_CompanionStage> createState() => _CompanionStageState();
}

class _CompanionStageState extends State<_CompanionStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 20),
  )..repeat();

  /// User-imposed spin, added on top of the slow idle rotation.
  double _dragYaw = 0;
  double _yawAtDragStart = 0;

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) => _yawAtDragStart = _dragYaw,
      onHorizontalDragUpdate: (d) {
        setState(() => _dragYaw = _yawAtDragStart + d.primaryDelta! * 0.02);
      },
      child: AnimatedBuilder(
        animation: _clock,
        builder: (context, _) {
          final t = _clock.value;
          final yaw = _dragYaw + t * 2 * math.pi;
          return CustomPaint(
            painter: _CompanionPainter(
              yaw: yaw,
              time: t,
              accent: widget.accent,
              scheme: widget.scheme,
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

// ── 3D math ────────────────────────────────────────────────────────────────

class _V3 {
  const _V3(this.x, this.y, this.z);
  final double x;
  final double y;
  final double z;
}

/// One shaded sphere of the figure, in local (pre-rotation) space.
class _Blob {
  const _Blob(this.p, this.r, this.role);
  final _V3 p;
  final double r;
  final _PartRole role;
}

enum _PartRole { skin, hair, cloth, eye }

/// The figure as a cloud of spheres: head, hair, torso, limbs, eyes.
const List<_Blob> _figure = <_Blob>[
  _Blob(_V3(0, -0.62, 0.02), 0.30, _PartRole.skin), // head
  _Blob(_V3(0, -0.66, 0.16), 0.33, _PartRole.hair), // hair mass
  _Blob(_V3(0, -0.42, 0.30), 0.19, _PartRole.hair), // bun
  _Blob(_V3(-0.26, -0.56, 0.10), 0.15, _PartRole.hair), // side hair L
  _Blob(_V3(0.26, -0.56, 0.10), 0.15, _PartRole.hair), // side hair R
  _Blob(_V3(-0.10, -0.60, -0.24), 0.045, _PartRole.eye),
  _Blob(_V3(0.10, -0.60, -0.24), 0.045, _PartRole.eye),
  _Blob(_V3(0, -0.18, 0), 0.26, _PartRole.cloth), // chest
  _Blob(_V3(0, 0.10, 0), 0.24, _PartRole.cloth), // waist
  _Blob(_V3(0, 0.34, 0), 0.25, _PartRole.cloth), // hips
  _Blob(_V3(-0.30, -0.26, 0), 0.13, _PartRole.cloth), // shoulder L
  _Blob(_V3(0.30, -0.26, 0), 0.13, _PartRole.cloth), // shoulder R
  _Blob(_V3(-0.40, -0.06, 0), 0.11, _PartRole.cloth), // arm L upper
  _Blob(_V3(-0.46, 0.14, 0), 0.095, _PartRole.skin), // arm L lower
  _Blob(_V3(0.40, -0.06, 0), 0.11, _PartRole.cloth), // arm R upper
  _Blob(_V3(0.46, 0.14, 0), 0.095, _PartRole.skin), // arm R lower
  _Blob(_V3(-0.14, 0.60, 0), 0.13, _PartRole.cloth), // thigh L
  _Blob(_V3(-0.16, 0.86, 0), 0.11, _PartRole.skin), // shin L
  _Blob(_V3(0.14, 0.60, 0), 0.13, _PartRole.cloth), // thigh R
  _Blob(_V3(0.16, 0.86, 0), 0.11, _PartRole.skin), // shin R
];

class _CompanionPainter extends CustomPainter {
  _CompanionPainter({
    required this.yaw,
    required this.time,
    required this.accent,
    required this.scheme,
  });

  final double yaw;
  final double time;
  final Color accent;
  final ColorScheme scheme;

  /// Camera distance for the perspective divide.
  static const double _cam = 3.2;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.46;
    final scale = math.min(size.width, size.height) * 0.95;

    // Blink: a short closure twice per idle cycle.
    final blinkPhase = (time * 6) % 1.0;
    final blink = blinkPhase > 0.94 ? 0.0 : 1.0;

    // Breathing: a gentle vertical bob.
    final bob = math.sin(time * 2 * math.pi * 2) * 0.012;

    // Aura behind the figure.
    final auraPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          accent.withValues(alpha: 0.34),
          accent.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(
        center: Offset(cx, cy),
        radius: scale * 0.62,
      ));
    canvas.drawCircle(Offset(cx, cy), scale * 0.62, auraPaint);

    final cosY = math.cos(yaw);
    final sinY = math.sin(yaw);

    // Project every blob, then paint back-to-front (painter's algorithm).
    final projected = <_Proj>[];
    for (final b in _figure) {
      final p = b.p;
      final rx = p.x * cosY - p.z * sinY;
      final rz = p.x * sinY + p.z * cosY;
      final ry = p.y + bob;
      final depth = rz;
      final persp = _cam / (_cam + depth);
      projected.add(_Proj(
        sx: cx + rx * scale * persp,
        sy: cy + ry * scale * persp,
        r: b.r * scale * persp,
        depth: depth,
        role: b.role,
      ));
    }
    projected.sort((a, b) => b.depth.compareTo(a.depth));

    // Ground shadow.
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, cy + scale * 0.52),
        width: scale * 0.55,
        height: scale * 0.10,
      ),
      shadow,
    );

    for (final q in projected) {
      final color = _roleColor(q.role, q.depth);
      final radius = (q.role == _PartRole.eye && blink == 0) ? 0.4 : 1.0;
      final rr = q.r * radius;
      // Shaded sphere: lighter toward the light (top-left-front).
      final paint = Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.5),
          radius: 0.95,
          colors: [
            Color.lerp(color, Colors.white, 0.35)!,
            color,
            Color.lerp(color, Colors.black, 0.28)!,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: Offset(q.sx, q.sy), radius: rr));
      canvas.drawCircle(Offset(q.sx, q.sy), rr, paint);
    }
  }

  Color _roleColor(_PartRole role, double depth) {
    // Depth fog: farther blobs fade slightly toward the background.
    final fog = (0.85 + depth * 0.18).clamp(0.6, 1.0);
    final base = switch (role) {
      _PartRole.skin => const Color(0xFFF2C6A8),
      _PartRole.hair => Color.lerp(accent, const Color(0xFF3A2A4A), 0.35)!,
      _PartRole.cloth => Color.lerp(accent, scheme.surface, 0.55)!,
      _PartRole.eye => const Color(0xFF2B2233),
    };
    return Color.lerp(base, scheme.surface, 1 - fog)!;
  }

  @override
  bool shouldRepaint(_CompanionPainter old) =>
      old.yaw != yaw ||
      old.time != time ||
      old.accent != accent ||
      old.scheme != scheme;
}

class _Proj {
  _Proj({
    required this.sx,
    required this.sy,
    required this.r,
    required this.depth,
    required this.role,
  });
  final double sx;
  final double sy;
  final double r;
  final double depth;
  final _PartRole role;
}

// ── Mood chip ──────────────────────────────────────────────────────────────

class _MoodChip extends StatelessWidget {
  const _MoodChip({
    required this.mood,
    required this.selected,
    required this.onTap,
  });

  final _Mood mood;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? mood.accent.withValues(alpha: 0.22)
                : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? mood.accent
                  : scheme.outlineVariant.withValues(alpha: 0.6),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(mood.icon,
                  size: 16,
                  color: selected ? mood.accent : scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                mood.label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? mood.accent : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Speech bubble ──────────────────────────────────────────────────────────

class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble({
    required this.text,
    required this.accent,
    required this.thinking,
  });

  final String text;
  final Color accent;
  final bool thinking;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.16),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.chat_bubble_rounded, size: 18, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: thinking
                ? _MiraTyping(accent: accent)
                : Text(
                    text,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.35,
                      color: scheme.onSurface,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _MiraTyping extends StatefulWidget {
  const _MiraTyping({required this.accent});
  final Color accent;

  @override
  State<_MiraTyping> createState() => _MiraTypingState();
}

class _MiraTypingState extends State<_MiraTyping>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Row(
          children: [
            Text(
              'Мира печатает',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 6),
            for (var i = 0; i < 3; i++) ...[
              Opacity(
                opacity: (0.3 + 0.7 * (((_c.value * 3) - i) % 1.0)).clamp(0, 1),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: widget.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 3),
            ],
          ],
        );
      },
    );
  }
}

// ── Composer ───────────────────────────────────────────────────────────────

class _CompanionComposer extends StatelessWidget {
  const _CompanionComposer({
    required this.controller,
    required this.busy,
    required this.accent,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final bool busy;
  final Color accent;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
            style: TextStyle(fontSize: 14, color: scheme.onSurface),
            decoration: InputDecoration(
              hintText: 'Напиши Мире…',
              isDense: true,
              filled: true,
              fillColor: scheme.surfaceContainerHigh,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: busy ? onStop : onSend,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                busy ? Icons.stop_rounded : Icons.send_rounded,
                size: 20,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
