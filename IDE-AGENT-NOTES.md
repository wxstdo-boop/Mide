# Идея: IDE-агент на ПК (на будущее)

> Записано по просьбе пользователя: «пригодится для ide агента на пк — это потом, но запомни».

## Кандидат №1 — Google Antigravity SDK
- Репо: https://github.com/google-antigravity/antigravity-sdk-python
- Ставка: `pip install google-antigravity` (важно: ставится из PyPI, вместе с compiled runtime binary — просто склонировать репо недостаточно)
- Что даёт (Python):
  - `Agent` — агент «из коробки» (управляет жизненным циклом, тулами, хуками, политиками)
  - `Conversation` — stateful-сессия с историей шагов
  - Кастомные тулы (Python-функции), MCP-серверы
  - Политики безопасности: `deny()`, `allow()`, `ask_user()` — по умолчанию read-only, запись включается через `CapabilitiesConfig()`
  - Триггеры (фоновые задачи по расписанию), мультимодальный ввод, стриминг мыслей и tool-call'ов
- Для IDE-агента это почти готовый фундамент: файловые/командные тулы + `ask_user` + sandbox.

## Альтернативы
- **Google ADK** (https://github.com/google/adk-python) — официальный флагман Google, зрелее и шире:
  graph-workflow'ы, multi-agent, human-in-the-loop (tool confirmation), eval, ADK Web UI, model-agnostic.
- **OpenAI Agents SDK** — популярный, чистый, handoffs; заточен под OpenAI (другие модели через LiteLLM).
- **LangGraph** — максимальная гибкость (графы), огромная экосистема, крутая кривая обучения.
- **Pydantic AI** — типобезопасный, аккуратный DX, model-agnostic.
- **Готовые решения** (если не строить с нуля): Continue.dev (open-source ассистент для VS Code/JetBrains, расширяемый), Aider (CLI-агент), OpenHands (платформа).
- **MCP** — стандарт «склейки» агента с инструментами (все перечисленные SDK его поддерживают).

## Вывод
- Если хочется Google-стек и «агентный цикл под капотом» — Antigravity SDK подходит почти идеально (у него уже есть файловые/командные примитивы + политики).
- Если важнее зрелость, доки и комьюнити — **Google ADK**.
- Если не привязываться к Google — Pydantic AI / LangGraph / OpenAI Agents SDK.

## РЕШЕНИЕ (обновлено)
Цель: НЕ писать агентный цикл с нуля — нужен готовый цикл (модель-вызовы, тулы, стриминг, история).
Все кандидаты (Antigravity, ADK, OpenAI Agents, Pydantic AI) дают цикл из коробки → выбор по модели и зрелости:

- **Google ADK** (`pip install google-adk`) — выбор, если Gemini/Google-стек: зрелый, model-agnostic, HITL, eval, веб-UI, без compiled-бинарников.
- **Pydantic AI** — выбор, если не привязан к Google: минимум кода, чистый DX, model-agnostic.
- **Antigravity SDK** — только если хочется максимально «нулевой код» и не смущает свежий compiled runtime + только Gemini.
- LangGraph — НЕ брать для старта (оркестрация пишется самому).

Финальный выбор: **Google ADK** (если Google) / **Pydantic AI** (если не Google).

## ДЛЯ MIDE (вкладка AGI) — SDK под Dart/Flutter
ВАЖНО про депрекации (проверено 19.08.2026):
- `google_generative_ai` — ЗАДЕПРЕКЕЙЧЕН (Google не развивает, заменили на firebase_vertexai → тот тоже discontinued → теперь `firebase_ai`).
- `firebase_ai` (официальный) — минусы: нужен полный Firebase-проект + App Check; платформы Android/iOS/web/macOS, Windows-десктопа НЕТ.

**Выбор для Mide: LangChain.dart** (`langchain` 0.8.1 + `langchain_google`/`langchain_openai`/`langchain_ollama`):
- Единственный готовый агентный SDK на чистом Dart; цикл (агенты, тулы, память, RAG) из коробки.
- Работает на ВСЕХ платформах Mide, включая Windows-десктоп.
- Модель-агностик — Gemini/OpenAI/Ollama меняются одной строкой.

Тяжёлый агент на ПК (файлы/команды) — Python-сидка (ADK/Antigravity) + Mide как UI поверх MCP/WebSocket.

## ★ Cline SDK — ЛУЧШИЙ готовый кодинг-агент (проверено 19.08.2026)
- `npm install @cline/sdk` — Node.js SDK, тот же движок, что у расширения Cline (VS Code/JetBrains/CLI). Apache 2.0.
- Из коробки: чтение проекта, правка файлов с диффами+чекпоинтами, терминал, веб, human-in-the-loop подтверждения.
- Кастомные тулы (createTool), MCP, мульти-агенты, cron-агенты, коннекторы (Telegram/Slack/Discord).
- Модель-агностик: Claude, OpenAI, Gemini, OpenRouter, Bedrock, Groq, Ollama, любой OpenAI-совместимый.
- Минус: Node.js — НЕ встроить в Flutter напрямую. Роль: sidecar-агент на ПК, Mide (UI) ↔ WebSocket/MCP ↔ Cline SDK.
- Вывод: для «вставил и пашет» кодинг-агента Cline SDK сильнее ADK/Antigravity (тулы+диффы+approval уже встроены).

## ЕСЛИ НЕ КОДИТЬ ВООБЩЕ (готовые решения «вставил и работает»)
SDK не нужен — берётся готовый плагин/ассистент:
- **Continue.dev** — open-source, VS Code/JetBrains, любая модель (вкл. Gemini и локальную Ollama). Главный кандидат.
- **Cline / Roo Code** — агентные расширения VS Code: сами читают проект, правят, запускают команды, свой API-ключ.
- **Gemini Code Assist** — плагин от Google, бесплатный тир.
- **Cursor / Windsurf** — целые AI-IDE (коммерческие).
- **Claude Code / Aider** — CLI-агенты (терминал).
Вывод: «вставил и работает» = Continue.dev или Cline. SDK — только когда строим своего агента (например, в Mide).
