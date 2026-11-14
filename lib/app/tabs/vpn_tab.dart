part of '../../main.dart';

/// AGI tab — remote AI assistant. Placeholder for now, will be fleshed out later.

/// NPV tab — the VPN client.
class VpnTab extends ConsumerWidget {
  const VpnTab({super.key});

  Future<void> _openMail(BuildContext context) async {
    const email = 'hello@mide.app';
    final uri = Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: {'subject': 'Mide VPN'},
    );
    try {
      await launchUrl(uri);
    } catch (_) {}
  }

  void _showSettings(BuildContext context) {
    _pushPage(context, const SettingsPage());
  }

  /// Push a full-screen page with the signature slide + fade + scale transition
  /// (reversed automatically on pop).
  static void _pushPage(BuildContext context, Widget page) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 480),
        reverseTransitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, __, ___) => page,
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.09),
                end: Offset.zero,
              ).animate(curved),
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            // The tunnel list is a static preset now; re-read the engine stage
            // so the card reflects the native VPN state on pull-to-refresh.
            await ref.read(vpnConnectionStateProvider.notifier).stageRefresh();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AppHeader(
                  image: 'assets/icon/mide.png',
                  title: 'Mide',
                  version: '0.75b',
                  actions: [
                    IconButton.filledTonal(
                      onPressed: () => _openMail(context),
                      icon: const Icon(Icons.mail_rounded),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: () => _showSettings(context),
                      icon: const Icon(Icons.settings_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const _VpnToggleCard(),
                const SizedBox(height: 20),
                const ServerListSection(),
                if (ref.watch(vpnConnectionStateProvider).isConnected) ...[
                  const SizedBox(height: 16),
                  const ConnectionInfoCard(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ServerListSection extends ConsumerWidget {
  const ServerListSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final servers = ref.watch(vpnServersProvider);
    final selectedId = ref.watch(selectedServerIdProvider);
    final vpnState = ref.watch(vpnConnectionStateProvider);

    return Column(
      key: const ValueKey('servers-data'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Серверы',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            if (servers.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${servers.length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        if (servers.isEmpty)
          const _EmptyServers()
        else
          ...servers.map(
            (s) => _ServerTile(
              server: s,
              isSelected: s.id == selectedId,
              isCurrent: vpnState.isConnected && vpnState.serverId == s.id,
              isBusy: vpnState.isConnecting && vpnState.serverId == s.id,
              onTap: () =>
                  ref.read(selectedServerIdProvider.notifier).state = s.id,
              onToggle: () =>
                  ref.read(vpnConnectionStateProvider.notifier).toggle(s.id),
            ),
          ),
      ],
    );
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.server,
    required this.isSelected,
    required this.isCurrent,
    required this.isBusy,
    required this.onTap,
    required this.onToggle,
  });

  final VpnServer server;
  final bool isSelected;
  final bool isCurrent;
  final bool isBusy;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mide = context.mideTheme;

    final parts = <String>[
      if (server.country != null && server.country!.isNotEmpty) server.country!,
      if (server.ping > 0) '${server.ping} мс',
    ];
    final subtitle = parts.join(' • ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isSelected
            ? scheme.primaryContainer
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? scheme.primary
                    : scheme.outlineVariant.withValues(alpha: 0.5),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? scheme.primary.withValues(alpha: 0.12)
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    switch (server.id) {
                      'warp' => Icons.bolt_rounded,
                      'v2nodes' => Icons.hub_rounded,
                      // `Icons.shield_locked_rounded` does not exist in Flutter — it broke the
                      // whole app at compile time. `vpn_lock` is the closest
                      // real icon.
                      'reality' => Icons.vpn_lock_rounded,
                      _ => Icons.dns_rounded,
                    },
                    size: 22,
                    color: isSelected
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        server.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (isCurrent) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: mide.successContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'В сети',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: mide.onSuccessContainer,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                // Per-server connect / disconnect toggle.
                IconButton.filledTonal(
                  isSelected: isCurrent,
                  onPressed: isBusy ? null : onToggle,
                  style: IconButton.styleFrom(
                    backgroundColor: isCurrent
                        ? scheme.errorContainer
                        : scheme.primary.withValues(alpha: 0.12),
                    foregroundColor: isCurrent
                        ? scheme.onErrorContainer
                        : scheme.primary,
                    disabledBackgroundColor: scheme.surfaceContainerHighest,
                  ),
                  icon: isBusy
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.primary,
                          ),
                        )
                      : Icon(
                          isCurrent
                              ? Icons.power_settings_new_rounded
                              : Icons.play_arrow_rounded,
                          size: 20,
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

class _EmptyServers extends StatelessWidget {
  const _EmptyServers();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.dns_rounded,
                size: 32,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Серверы не найдены',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Проверьте API-ключ и адрес провайдера в настройках',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class ConnectionInfoCard extends ConsumerWidget {
  const ConnectionInfoCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final vpnState = ref.watch(vpnConnectionStateProvider);
    final latency = ref.watch(vpnMetricsProvider).valueOrNull?.latencyMs;

    Widget cell(String label, String value) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
        ],
      );
    }

    Widget divider() => Container(
      width: 1,
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: scheme.outlineVariant.withValues(alpha: 0.6),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Row(
          children: [
            Expanded(child: cell('IP-адрес', vpnState.ipAddress ?? '—')),
            divider(),
            Expanded(child: cell('Протокол', vpnState.protocol)),
            divider(),
            Expanded(
              child: cell('Задержка', latency != null ? '$latency мс' : '—'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── VPN toggle: a single clean ON/OFF control that drives a real tunnel ──
// On Windows the two V2Nodes entries run the bundled Xray core (free VLESS
// lists, screened for life before spawning); elsewhere WARP enrolls a
// WireGuard config. No import, no subscription, no API key either way.

class _VpnToggleCard extends ConsumerWidget {
  const _VpnToggleCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final state = ref.watch(vpnConnectionStateProvider);
    final conf = ref.watch(wgConfigProvider);

    final isConnected = state.isConnected;
    final isBusy = state.isConnecting;
    final denied = state.phase == VpnPhase.denied;
    final failed = state.phase == VpnPhase.failed;

    Future<void> handleToggle() async {
      final notifier = ref.read(vpnConnectionStateProvider.notifier);
      if (isConnected) {
        notifier.disconnect();
        return;
      }
      if (isBusy) return;
      notifier.toggle(ref.read(selectedServerIdProvider) ?? 'v2nodes');
    }

    // First-ever connect also provisions the tunnel (keygen + enrollment, or
    // screening free nodes), which is worth calling out so the pause doesn't
    // look like a hang.
    final xrayPath = state.serverId == 'v2nodes' || state.serverId == 'reality';
    final provisioning =
        isBusy &&
        state.phase == VpnPhase.connecting &&
        (xrayPath || conf.isEmpty);

    final (String title, String status) = isConnected
        ? ('VPN включён', 'Туннель работает · обход активен')
        : denied
        ? (
            'Разрешение отклонено',
            state.error ?? 'Система не дала VPN-разрешение',
          )
        : failed
        ? ('Ошибка подключения', state.error ?? 'Туннель не запустился')
        : provisioning
        ? (xrayPath
              ? (state.serverId == 'reality'
                    ? (
                        'Ищем живые Reality-узлы…',
                        'Перебираем VLESS Reality · список обновляется каждые 15 мин',
                      )
                    : (
                        'Ищем живые узлы…',
                        'Перебираем бесплатные V2Nodes-узлы…',
                      ))
              : (
                  'Готовим туннель…',
                  'Бесплатная регистрация WireGuard-конфига…',
                ))
        : isBusy
        ? (
            state.phase == VpnPhase.disconnecting
                ? 'Выключаем…'
                : 'Подключаем…',
            'Открываем туннель…',
          )
        : ('VPN выключен', 'Готов к включению');

    final btnLabel = isConnected
        ? 'Выключить VPN'
        : isBusy
        ? (state.phase == VpnPhase.disconnecting ? 'Выключаем…' : 'Подключаем…')
        : 'Включить VPN';

    final accent = isConnected ? scheme.primary : scheme.error;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isConnected
              ? [scheme.primaryContainer, scheme.surfaceContainerHigh]
              : [scheme.surfaceContainerHigh, scheme.surfaceContainerHighest],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isConnected
              ? scheme.primary.withValues(alpha: 0.5)
              : scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: isConnected
                      ? scheme.primary.withValues(alpha: 0.16)
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: isBusy
                    ? Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: accent,
                        ),
                      )
                    : Icon(
                        isConnected
                            ? Icons.shield_rounded
                            : Icons.vpn_key_rounded,
                        color: isConnected
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                        size: 24,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color:
                            (denied || failed
                                    ? scheme.error
                                    : scheme.onSurfaceVariant)
                                .withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isBusy ? null : handleToggle,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: double.infinity,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isConnected
                        ? [scheme.error, scheme.error.withValues(alpha: 0.85)]
                        : [
                            scheme.primary,
                            scheme.primary.withValues(alpha: 0.85),
                          ],
                  ),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isBusy
                          ? Icons.autorenew_rounded
                          : (isConnected
                                ? Icons.stop_rounded
                                : Icons.bolt_rounded),
                      color: isConnected ? scheme.onError : scheme.onPrimary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      btnLabel,
                      style: TextStyle(
                        color: isConnected ? scheme.onError : scheme.onPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
