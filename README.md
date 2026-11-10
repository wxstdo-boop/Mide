# Mide — FOSS VPN Client

VPN-клиент с открытым исходным кодом. Подключение к любому VPN-провайдеру через API.

## Возможности

- Ввод API-ключа в настройках приложения
- Реальные HTTP-запросы к API провайдера  
- Выбор сервера из списка
- Подключение/отключение одной кнопкой
- Material You дизайн
- Никаких подписок, рекламы и мёртвого кода

## Как использовать

1. Запусти приложение
2. Нажми ⚙️ (настройки)
3. Введи API-ключ и адрес провайдера
4. Выбери сервер
5. Нажми "Подключить"

## Формат API

REST с авторизацией Authorization: Bearer <ключ>:
- GET /servers
- POST /connect  
- POST /disconnect

## Запуск

```powershell
flutter pub get
flutter run
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
