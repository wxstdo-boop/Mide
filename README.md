# Mide — FOSS VPN Client

VPN-клиент с открытым исходным кодом на Flutter. Бесплатный туннель «из
коробки», плюс подключение к любому провайдеру по API-ключу.

## Возможности

Три раздела в нижней панели: **AGI** (AI), **NPV** (VPN) и **MEarn**.

### NPV — VPN

- **Бесплатный туннель без настройки.** Cloudflare WARP: приложение само
  регистрирует одноразового клиента на публичном enrollment-эндпоинте
  Cloudflare и превращает ответ в `wg-quick`-конфиг (тот же поток, что у
  `wgcf` / `warp-go`). Ключ и сервер вводить не нужно.
- **Обход DPI (Windows).** Список бесплатных VLESS-узлов подтягивается с
  GitHub-зеркал; Mide запускает `xray-core` как sidecar и переводит системный
  прокси (WinINET) на него. Трафик к `geosite:category-ru` идёт напрямую.
  Это не TUN-VPN: браузеры и приложения, уважающие WinINET, ходят через
  ядро — без прав администратора.
- **Свой провайдер по API-ключу.** Ключ и адрес вводятся в настройках,
  хранятся в зашифрованном хранилище (`flutter_secure_storage`).
- **Реальный туннель.** Кросс-платформенный WireGuard через
  `wireguard_flutter_pro`: Android VpnService, Windows Wintun, macOS/iOS
  Packet Tunnel, Linux `wg-quick`. На Web движок мягко отключается.
- Выбор сервера из списка, подключение/отключение одной кнопкой, информация
  о соединении (IP, протокол).

### AGI — Ada (M.AI)

- Чат-ассистент «Ada» на бесплатных OpenAI-совместимых провайдерах
  (Pollinations, LLM7, OVH) с ротацией по моделям и быстрым пропуском
  недоступных. Horde (нужен бесплатный ключ) идёт последним фолбэком.
- Анимированный интерфейс: шиммер-заголовок, «дышащий» индикатор набора,
  кросс-фейд между провайдерами.

### MEarn — крипто

- Информационные карточки о способах заработка (статичный контент).

### IDE (только ПК)

- Редактор с деревом файлов, вкладками, подсветкой синтаксиса и консолью
  запуска (`dart`, `python`, `node`, `pwsh`, `cmd`, `bash`).
- Встроенная AI-панель на базе sidecar-агента Cline SDK (Node.js) —
  читает проект, правит файлы, запускает команды.
- Раздел доступен только в десктопных сборках.

### Автообновление

- Настройки → **Проверить и обновить**: Mide смотрит последний GitHub
  Release, скачивает Android arm64 APK и открывает установщик системы.

## Запуск

```powershell
flutter pub get
flutter run
```

Требуется Flutter SDK (Dart 3.5+). Проверка кода и тесты:

```powershell
flutter analyze
flutter test
```

## Формат API провайдера

REST с авторизацией `Authorization: Bearer <ключ>`:

- `GET /servers` (пробуются также `/subscription`, `/locations`, …)
- `POST /connect`
- `POST /disconnect`

## Структура

```
lib/
  app/           # shell (HomePage, навигация) + вкладки и страницы
  core/          # тема (Material You) и состояние вкладок
  features/
    ai/          # Ada: провайдеры, клиент, UI
    ide/         # ПК-IDE: дерево, редактор, консоль, AI-панель, Cline-sidecar
    updater/     # GitHub-автообновление (io + web)
    vpn/         # WireGuard-движок, WARP/V2Nodes, Xray-core, API-клиент
```

## Android updates and releases

In Settings, **Проверить и обновить** checks the latest GitHub Release, downloads
its Android arm64 APK, and opens Android's installer. Android may ask once for
permission to install updates from Mide; installation always requires system
confirmation.

Pushing a new `version` from `pubspec.yaml` to `main` runs
`.github/workflows/release-ship.yml` and publishes `v<version>` automatically.
The workflow requires these repository Actions secrets: `ANDROID_KEYSTORE_BASE64`,
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD`.
Keep a secure backup of the keystore and its passwords; all future APKs must use
the same signing key for Android to accept them as updates.
The already-published v1.0.0 APK used a temporary debug signing key, so it
cannot be updated in place; install the first stable-signed build once before
using in-app updates.

MIT License
