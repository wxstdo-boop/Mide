part of '../../main.dart';

// ---------------------------------------------------------------------------
// MEarn Tab — passive crypto / money farming
// ---------------------------------------------------------------------------

class MEarnTab extends StatelessWidget {
  const MEarnTab({super.key});

  static const _cards = <_EarnCardData>[
    _EarnCardData(
      icon: Icons.quiz_rounded,
      title: 'Анкетка',
      subtitle:
          'Проходи опросы — получаешь рубли на карту. Простой заработок без вложений',
      url: 'https://anketka.ru',
      gradient: [Color(0xFFE91E63), Color(0xFF9C27B0)],
    ),
    _EarnCardData(
      icon: Icons.currency_bitcoin_rounded,
      title: 'Kryptex',
      subtitle:
          'Майнишь крипту на своём ПК. Вывод на карту или BTC. Работает в РФ',
      url: 'https://kryptex.org',
      gradient: [Color(0xFFFF9800), Color(0xFFFF5722)],
    ),
    _EarnCardData(
      icon: Icons.hexagon_rounded,
      title: 'Honeygain',
      subtitle:
          'Сдавай интернет — получаешь BTC. Работает в РФ, минимум 50 руб',
      url: 'https://honeygain.com',
      gradient: [Color(0xFFF59E0B), Color(0xFFD97706)],
    ),
    _EarnCardData(
      icon: Icons.hive_rounded,
      title: 'DataHive AI',
      subtitle:
          'Децентрализованная биржа данных. Сдавай трафик — зарабатывай токены',
      url: 'https://datahive.ai',
      gradient: [Color(0xFF10B981), Color(0xFF3B82F6)],
    ),
    _EarnCardData(
      icon: Icons.water_drop_rounded,
      title: 'Pond AI',
      subtitle: 'Фарм токены за разметку данных для ИИ. Пассивный доход',
      url: 'https://pondai.io',
      gradient: [Color(0xFF0EA5E9), Color(0xFF6366F1)],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
          children: [
            _AppHeader(
              image: 'assets/icon/mide.png',
              title: 'MEarn',
              version: '0.75b',
              actions: [
                IconButton.filledTonal(
                  onPressed: () {},
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Quick stats row.
            Row(
              children: [
                _StatChip(
                  icon: Icons.trending_up_rounded,
                  label: '5 сервисов',
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                _StatChip(
                  icon: Icons.circle,
                  label: 'Пассивный доход',
                  color: scheme.tertiary,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Фарм и заработок',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Открой сервис, подключи — и капает пассивно',
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            ..._cards.map((c) => _EarnCard(data: c)),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _EarnCardData {
  const _EarnCardData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.url,
    required this.gradient,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String url;
  final List<Color> gradient;
}

class _EarnCard extends StatelessWidget {
  const _EarnCard({required this.data});

  final _EarnCardData data;

  Future<void> _open(BuildContext context) async {
    final uri = Uri.parse(data.url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () => _open(context),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                // Gradient icon container.
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: data.gradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    data.icon,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                // Text.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        data.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.open_in_new_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
