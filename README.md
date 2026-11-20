# Mide — FOSS VPN Client

VPN-клиент с открытым исходным кодом на Flutter. Бесплатный туннель «из
коробки», плюс подключение к любому провайдеру по API-ключу.

## Возможности

Три раздела в нижней панели: **CRY** (AI), **NPV** (VPN) и **Earn**
(крипто). **3D** (компаньонка) и **Clip** (видеоредактор) открываются
кнопками в шапке раздела NPV, рядом с настройками.

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

### CRY — Ada Cry (Ада Край)

- Чат-ассистент на бесплатных OpenAI-совместимых провайдерах
  (Pollinations, AI Horde) с ротацией по моделям и быстрым пропуском
  недоступных. Оба отвечают анонимно, без регистрации и ключа. Выбор
  провайдера — в настройках, в шапке раздела его нет.
- Анимированный интерфейс: шиммер-заголовок с красным блеском, «дышащий»
  индикатор набора.
- Кнопка очистки чата и повтор последнего вопроса после ошибки.
- Сессии на персонах (`personaSessionProvider`): у каждой персоны своя
  история, поэтому 3D-компаньонка не смешивается с ассистентом.

### MEarn — крипто

- Информационные карточки о способах заработка (статичный контент).

### 3D — компаньонка «Мира» (страница из NPV)

- Процедурная 3D-модель девушки: сфера, собранная из затенённых сфер с
  ручной перспективной проекцией, — рендерится везде (включая Web) без
  нативных зависимостей и без glTF-ассетов.
- Настроение (нежность, радость, загадка, драйв, печаль) меняет ауру и позу.
- Свой чат на базе общей персональной сессии.

### Clip — Clip Studio (страница из NPV)

- Лёгкий аналог CapCut: выбор видео/фото/музыки, обрезка, скорость,
  громкость и цветовые фильтры для каждого клипа.
- Горизонтальный таймлайн с перетаскиванием, дублированием и удалением.
- Экспорт в один MP4 через FFmpeg: клипы нормализуются, затем склеиваются
  потоково (`-c copy`), с прогрессом и отменой. Только нативные платформы;
  на Web редактор открывается, но экспорт отключён.

### IDE (только ПК)

- Редактор с деревом файлов, вкладками, подсветкой синтаксиса и консолью
  запуска (`dart`, `python`, `node`, `pwsh`, `cmd`, `bash`).
- Встроенная AI-панель на базе sidecar-агента Cline SDK (Node.js) —
  читает проект, правит файлы, запускает команды. Подробности и API —
  в [`agent/README.md`](agent/README.md); sidecar собирается и проверяется
  отдельной CI-джобой `agent-sidecar`.
- Раздел доступен только в десктопных сборках.

### Бесплатные AI-провайдеры

Работают без регистрации, проверено вживую:

| Провайдер | Модели | Примечание |
|---|---|---|
| Pollinations | `openai-fast`, `openai` | нужен браузерный User-Agent |
| AI Horde | Qwen3 / Llama-3.2 / Qwen3.8 | анонимный ключ `0000000000`, низкий приоритет |
| Kilo Gateway (ПК-IDE) | `kilo-auto/free`, `minimax-m2.1:free` | без Authorization-заголовка |

Убраны как переставшие быть анонимными: **LLM7.io** (401 на всех моделях) и
**OVHcloud Kepler** (TLS-хендшейк не проходит). Ключ AI Horde из
[stablehorde.net](https://stablehorde.net/register) необязателен — он только
поднимает приоритет в очереди.

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
    ai/          # AI-чат: провайдеры, клиент, UI, персональные сессии
    clip/        # Clip Studio: модели, FFmpeg-экспорт, превью, провайдеры
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
