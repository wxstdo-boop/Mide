# Mide AGI — sidecar-агент (Cline SDK)

Кодинг-агент для Mide на **@cline/sdk**: те же тулы, что у расширения Cline —
читает и ищет по проекту, правит файлы, запускает команды, читает веб.
Модель любая, включая бесплатные (OVH / LLM7 / Ollama локально).

```
Mide (IDE, плашка «Агент») ──HTTP/SSE──▶  этот sidecar (Node.js)
                                           └── Cline SDK Agent
                                               ├── read_files / search_codebase
                                               ├── editor (правка файлов)
                                               ├── run_commands (спрашивает UI)
                                               └── fetch_web_content
```

## Установка

```bash
cd agent
npm install          # ставит @cline/sdk из npm
cp .env.example .env # и заполни под свою модель (Mide передаёт env сам)
```

## Запуск

```bash
npm start            # или: node src/index.mjs
```

Сервер поднимется на `http://127.0.0.1:8765` (порт — `AGENT_PORT`). Проверка:

```bash
curl http://127.0.0.1:8765/health
```

Mide запускает sidecar сам (плашка «Полноценный агент» в IDE), передавая
`WORKSPACE`, `PROVIDER`, `BASE_URL`, `MODEL` переменными окружения — `.env`
для этого не нужен.

## Бесплатные модели

- **Локально, бесплатно:** [Ollama](https://ollama.com) + `ollama pull qwen2.5-coder:7b`,
  затем `PROVIDER=ollama`, `MODEL=qwen2.5-coder:7b` — интернет не нужен.
- **Без ключа:** `PROVIDER=openai-compatible` +
  `BASE_URL=https://oai.endpoints.kepler.ai.cloud.ovh.net/v1`, `MODEL=gpt-oss-20b`
  (этот вариант Mide использует по умолчанию).
- `PROVIDER=google` / `openrouter` + ключ — есть бесплатные тиры.

## API

| Метод | Путь      | Описание                                                        |
|-------|-----------|-----------------------------------------------------------------|
| GET   | `/health` | статус: провайдер, модель, рабочая папка, тулы, `busy`          |
| POST  | `/chat`   | `{ "message": "..." }` → SSE-поток событий                      |
| POST  | `/approve`| `{ "id": "ap1", "ok": true, "reason": "…" }` — ответ на approval |
| POST  | `/stop`   | прервать текущий прогон                                         |
| POST  | `/reset`  | сбросить историю разговора                                      |

События `/chat` (SSE, `data: {...}\n\n`):
- `{type:"text", text}` — текст ответа (стриминг)
- `{type:"reasoning", text}` — рассуждения модели
- `{type:"tool_start", name, input}` — агент вызывает тул
- `{type:"approval", id, name, input}` — тул ждёт разрешения UI (на `POST /approve`)
- `{type:"tool_end", name, output}` — тул завершился с результатом
- `{type:"done", status, outputText, error}` — финал прогона
- `{type:"error", message}` — ошибка

Пример:

```bash
curl -N -X POST http://127.0.0.1:8765/chat \
  -H "Content-Type: application/json" \
  -d '{"message":"Найди, где собирается VPN-конфиг, и объясни"}'
```

## Безопасность

- `run_commands` по умолчанию **не** выполняется сам: sidecar шлёт событие
  `approval` и ждёт `POST /approve`. Без ответа из UI решение принимается
  через `APPROVAL_TIMEOUT_MS` (по умолчанию 300 с) — отказ.
- `AUTO_APPROVE=1` — всё выполняется без спроса (только для доверенной машины).
- Все пути тулов ограничены `WORKSPACE` — той самой папкой проекта, которую
  открыл Mide.
