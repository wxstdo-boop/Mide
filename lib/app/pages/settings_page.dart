part of '../../main.dart';

/// Settings: theme carousel + entry point to the VPN connection setup.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header.
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Настройки',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          'Тема и обновления',
                          style: TextStyle(
                              fontSize: 13, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                children: const [
                  _SectionTitle(
                    icon: Icons.palette_rounded,
                    title: 'Тема',
                    subtitle: 'Листай карусель — тема меняется сразу',
                  ),
                  SizedBox(height: 14),
                  ThemeCarousel(),
                  SizedBox(height: 28),
                  _SectionTitle(
                    icon: Icons.system_update_alt_rounded,
                    title: 'Обновления',
                    subtitle: 'Проверка и установка нового билда из GitHub',
                  ),
                  SizedBox(height: 14),
                  _UpdateSection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Connection setup: subscription URL + optional API key.
class SetupVpnPage extends ConsumerStatefulWidget {
  const SetupVpnPage({super.key});

  @override
  ConsumerState<SetupVpnPage> createState() => _SetupVpnPageState();
}

class _SetupVpnPageState extends ConsumerState<SetupVpnPage> {
  final _urlCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  bool _showAdvanced = false;
  bool _obscureKey = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await ref.read(vpnSettingsProvider.future);
    if (!mounted) return;
    _urlCtrl.text = settings.baseUrl;
    _keyCtrl.text = settings.apiKey;
  }

  Future<void> _save() async {
    final settings = VpnSettings(
      apiKey: _keyCtrl.text.trim(),
      baseUrl: _urlCtrl.text.trim().isEmpty
          ? VpnSettingsStore.defaultBaseUrl
          : _urlCtrl.text.trim(),
    );
    setState(() => _saving = true);
    try {
      await ref.read(vpnSettingsStoreProvider).save(settings);
      ref.invalidate(vpnSettingsProvider);
      ref.invalidate(vpnServersProvider);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      // Silent: key remains in the field for re-entry.
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clear() async {
    await ref.read(vpnSettingsStoreProvider).clear();
    ref.invalidate(vpnSettingsProvider);
    ref.invalidate(vpnServersProvider);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header.
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Настройка VPN',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          'Подключение к провайдеру',
                          style: TextStyle(
                              fontSize: 13, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                children: [
                  // Subscription URL hero card.
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          scheme.primary.withValues(alpha: 0.16),
                          scheme.primary.withValues(alpha: 0.04),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: scheme.primary.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(Icons.rss_feed_rounded,
                              color: scheme.onPrimary),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'URL подписки',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: scheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Вставь ссылку на серверы провайдера — они появятся во вкладке NPV',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.35,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _urlCtrl,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'URL подписки',
                      hintText: 'https://provider.example.com',
                      prefixIcon: Icon(Icons.link_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Advanced: API key (optional).
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () =>
                          setState(() => _showAdvanced = !_showAdvanced),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Icon(
                              _showAdvanced
                                  ? Icons.expand_less_rounded
                                  : Icons.expand_more_rounded,
                              size: 20,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'API-ключ (если требуется)',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 280),
                    crossFadeState: _showAdvanced
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    firstChild: const SizedBox(width: double.infinity),
                    secondChild: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: TextField(
                        controller: _keyCtrl,
                        obscureText: _obscureKey,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: 'API-ключ',
                          prefixIcon: const Icon(Icons.vpn_key_rounded),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureKey
                                  ? Icons.visibility_rounded
                                  : Icons.visibility_off_rounded,
                              size: 20,
                            ),
                            onPressed: () =>
                                setState(() => _obscureKey = !_obscureKey),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_download_rounded),
                      label: const Text('Получить серверы'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton.icon(
                      onPressed: _saving ? null : _clear,
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('Удалить ключ'),
                      style:
                          TextButton.styleFrom(foregroundColor: scheme.error),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 18, color: scheme.onSecondaryContainer),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
              Text(
                subtitle,
                style:
                    TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Horizontal carousel of theme cards — swiping applies the theme instantly.
class ThemeCarousel extends ConsumerStatefulWidget {
  const ThemeCarousel({super.key});

  @override
  ConsumerState<ThemeCarousel> createState() => _ThemeCarouselState();
}

class _ThemeCarouselState extends ConsumerState<ThemeCarousel> {
  late final PageController _controller;
  late int _page;

  @override
  void initState() {
    super.initState();
    // Start the carousel on the page of the currently selected theme.
    // (Without initialPage the view opens on page 0, so the checkmark and
    // the centered card could disagree — the reported "checkmark on dark,
    // display on light" bug.)
    final initial =
        MideThemeChoice.values.indexOf(ref.read(themeChoiceProvider));
    _page = initial;
    _controller = PageController(viewportFraction: 0.86, initialPage: initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _select(int page) {
    setState(() => _page = page);
    ref.read(themeChoiceProvider.notifier).select(MideThemeChoice.values[page]);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final choice = ref.watch(themeChoiceProvider);
    final choiceIndex = MideThemeChoice.values.indexOf(choice);
    if (choiceIndex != _page) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) return;
        _controller.animateToPage(choiceIndex,
            duration: const Duration(milliseconds: 480),
            curve: Curves.easeInOutCubic);
        setState(() => _page = choiceIndex);
      });
    }
    return Column(
      children: [
        SizedBox(
          height: 176,
          child: PageView.builder(
            controller: _controller,
            itemCount: MideThemeChoice.values.length,
            onPageChanged: _select,
            itemBuilder: (context, index) {
              final item = MideThemeChoice.values[index];
              return _ThemeCard(
                choice: item,
                selected: choiceIndex == index,
                onTap: () {
                  _controller.animateToPage(
                    index,
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeInOutCubic,
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(MideThemeChoice.values.length, (i) {
            final active = i == _page;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 480),
              curve: Curves.easeInOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 22 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: active
                    ? scheme.primary
                    : scheme.outlineVariant.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(999),
              ),
            );
          }),
        ),
      ],
    );
  }
}

/// A single theme card with a live mini-preview of its palette.
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.choice,
    required this.selected,
    required this.onTap,
  });

  final MideThemeChoice choice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: bloodySeed,
      brightness: choice.isDark ? Brightness.dark : Brightness.light,
    );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 480),
      curve: Curves.easeInOutCubic,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: selected
              ? scheme.primary
              : scheme.outlineVariant.withValues(alpha: 0.5),
          width: selected ? 2.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: selected
                ? scheme.primary.withValues(alpha: 0.25)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: selected ? 18 : 8,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [scheme.primary, scheme.tertiary],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        Icons.colorize_rounded,
                        size: 20,
                        color: scheme.onPrimary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            choice.label,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurface,
                            ),
                          ),
                          Text(
                            choice.subtitle,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutBack,
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: selected ? scheme.primary : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color:
                              selected ? scheme.primary : scheme.outlineVariant,
                        ),
                      ),
                      child: selected
                          ? Icon(Icons.check_rounded,
                              size: 16, color: scheme.onPrimary)
                          : null,
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: scheme.primary, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 64,
                        height: 22,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Settings: the "Обновления" section ────────────────────────────────────────

/// One-tap update: checks the latest GitHub release, downloads the Android
/// arm64 APK when needed, and opens Android's installer for confirmation.
class _UpdateSection extends StatefulWidget {
  const _UpdateSection();

  @override
  State<_UpdateSection> createState() => _UpdateSectionState();
}

class _UpdateSectionState extends State<_UpdateSection> {
  bool _checking = false;
  bool _installing = false;
  UpdateCheckResult? _result;

  bool get _busy => _checking || _installing;

  Future<void> _check() async {
    if (_busy) return;
    setState(() => _checking = true);
    try {
      final res = await githubUpdater.checkLatest();
      if (!mounted) return;
      setState(() {
        _result = res;
        if (res.hasUpdate) {
          _checking = false;
          _installing = true;
        }
      });
      if (res.hasUpdate) {
        final done = await githubUpdater.downloadAndInstall(res);
        if (mounted) setState(() => _result = done);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _result = UpdateCheckResult.failure('$e'));
      }
    } finally {
      if (mounted) {
        setState(() {
          _checking = false;
          _installing = false;
        });
      }
    }
  }

  Future<void> _openReleasePage() async {
    // openReleasePage falls back to the releases page when the link is null.
    await githubUpdater
        .openReleasePage(_result ?? UpdateCheckResult.noReleases());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final res = _result;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Primary action.
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : _check,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.system_update_alt_rounded),
            label: Text(
              _installing
                  ? 'Скачиваем и открываем установщик…'
                  : _checking
                      ? 'Ищем новый релиз…'
                      : res == null
                          ? 'Проверить и обновить'
                          : 'Проверить снова',
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildResult(scheme, res),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            onPressed: _busy ? null : _openReleasePage,
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text('Открыть GitHub Releases'),
            style: TextButton.styleFrom(
              textStyle: const TextStyle(fontSize: 12.5),
              foregroundColor: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResult(ColorScheme scheme, UpdateCheckResult? res) {
    if (res == null) {
      return const _ResultCard(
        icon: Icons.cloud_queue_rounded,
        title: 'Обновления из GitHub',
        lines: [
          'Одно нажатие проверит GitHub, скачает новый APK и откроет установщик',
        ],
      );
    }
    final asset = res.asset;
    final date = res.publishedAt?.split('T').first;

    switch (res.kind) {
      case UpdateKind.error:
        return _ResultCard(
          icon: Icons.error_outline_rounded,
          tone: scheme.error,
          title: 'Не удалось проверить',
          lines: [res.error ?? 'Неизвестная ошибка'],
        );
      case UpdateKind.none:
        return const _ResultCard(
          icon: Icons.info_outline_rounded,
          title: 'Нет доступных релизов',
          lines: [
            'GitHub пока не вернул опубликованный релиз Mide',
          ],
        );
      case UpdateKind.noMatch:
        return _ResultCard(
          icon: Icons.search_off_rounded,
          title: 'Версия ${res.latestVersion} найдена',
          lines: [
            currentPlatformTag == 'android'
                ? 'В релизе нет совместимого APK для Android arm64'
                : 'Автоустановка сейчас доступна только в Android arm64-сборке',
          ],
        );
      case UpdateKind.upToDate:
        return _ResultCard(
          icon: Icons.check_circle_rounded,
          tone: scheme.primary,
          title: 'Установлена последняя версия',
          lines: [res.latestVersion ?? ''],
        );
      case UpdateKind.update:
        return _ResultCard(
          icon: Icons.cloud_download_rounded,
          tone: scheme.primary,
          title: _installing
              ? 'Скачиваем версию ${res.latestVersion}'
              : 'Доступна версия ${res.latestVersion}',
          lines: [
            if (asset != null) '${asset.name} · ${asset.sizeMb}',
            if (date != null) 'Выпущена: $date',
            if (res.notes != null && res.notes!.isNotEmpty) res.notes!,
            if (_installing)
              'После загрузки Android запросит подтверждение установки.',
          ],
        );
      case UpdateKind.installerOpened:
        return _ResultCard(
          icon: Icons.system_update_alt_rounded,
          tone: scheme.primary,
          title: 'Обновление передано Android: ${res.latestVersion}',
          lines: [
            'Файл: ${asset?.name ?? '—'}',
            'Подтверди установку в системном окне. Если Android попросит разрешение, разреши установку для Mide.',
          ],
        );
    }
  }
}

/// A rounded result card under the update button: icon + title + detail
/// lines, with an optional accent.
class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.icon,
    required this.title,
    required this.lines,
    this.tone,
  });

  final IconData icon;
  final String title;
  final List<String> lines;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = tone ?? scheme.onSurfaceVariant;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: tone != null
              ? tone!.withValues(alpha: 0.35)
              : scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          if (lines.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...lines.map(
              (l) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  l,
                  style:
                      TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
