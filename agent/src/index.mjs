// ============================================================================
// Mide AGI sidecar — кодинг-агент на Cline SDK (@cline/sdk)
// ----------------------------------------------------------------------------
// HTTP-сервер (без внешних зависимостей, только node:http):
//   GET  /health   — статус: провайдер, модель, рабочая папка, тулы
//   POST /chat     — { "message": "..." } → SSE-поток событий агента
//   POST /approve  — { "id": "...", "ok": true } — ответ на approval-запрос
//   POST /stop     — прервать текущий прогон
//   POST /reset    — сбросить историю разговора
//
// Провайдеры: ollama (бесплатно, локально), google (Gemini), openrouter,
//             любой openai-compatible (OVH, LLM7, Pollinations…).
// Конфиг — через переменные окружения (см. .env.example).
// ============================================================================

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { Agent, createBuiltinTools } from "@cline/sdk";

// --- мини-загрузчик .env (без зависимостей) ---------------------------------
try {
  const envFile = fs.readFileSync(new URL("../.env", import.meta.url), "utf8");
  for (const line of envFile.split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$/);
    if (m && !(m[1] in process.env)) {
      process.env[m[1]] = m[2].replace(/^["']|["']$/g, "");
    }
  }
} catch {
  /* .env не обязателен — используем переменные окружения */
}

// --- конфигурация ------------------------------------------------------------
const PORT = Number(process.env.AGENT_PORT || 8765);
const PROVIDER = (process.env.PROVIDER || "ollama").toLowerCase();
const MODEL = process.env.MODEL || "";
const API_KEY = process.env.API_KEY || "";
const BASE_URL = process.env.BASE_URL || "";
const AUTO_APPROVE = process.env.AUTO_APPROVE === "1";
const APPROVAL_TIMEOUT_MS = Number(process.env.APPROVAL_TIMEOUT_MS || 300000);
// Рабочая папка агента: по умолчанию корень проекта (родитель папки agent/)
const WORKSPACE = path.resolve(
  process.env.WORKSPACE || path.resolve(import.meta.dirname, "..", ".."),
);

const DEFAULT_MODELS = {
  ollama: "qwen2.5-coder:7b",
  google: "gemini-2.5-flash",
  openai: "gpt-4o-mini",
  openrouter: "deepseek/deepseek-chat",
};

const providerId = PROVIDER;
const modelId = MODEL || DEFAULT_MODELS[PROVIDER] || DEFAULT_MODELS.openai;
const apiKey = API_KEY || (providerId === "ollama" ? "ollama" : undefined);
const baseUrl = BASE_URL || (providerId === "ollama" ? "http://127.0.0.1:11434" : undefined);

// --- тулы: встроенный набор Cline (чтение, поиск, shell, редактор, веб) ------
const tools = createBuiltinTools({
  cwd: WORKSPACE,
  shell: process.platform === "win32" ? "bash" : "/bin/sh",
  enableReadFiles: true,
  enableSearch: true,
  enableBash: true,
  enableEditor: true,
  enableWebFetch: true,
  bashTimeoutMs: 180000,
});

// --- подтверждения (human-in-the-loop) ---------------------------------------
// Опасные тулы не имеют TTY-вопроса: агент просит разрешение через UI (SSE +
// POST /approve). Без клиента решение приходит по таймауту — отказ.
const pending = new Map();
let emit = () => {};
let approvalSeq = 0;

function requestApproval(req) {
  const id = `ap${++approvalSeq}`;
  return new Promise((resolve) => {
    const timer = setTimeout(() => {
      pending.delete(id);
      resolve({ approved: false, reason: "Нет ответа от интерфейса" });
    }, APPROVAL_TIMEOUT_MS);
    pending.set(id, (decision) => {
      clearTimeout(timer);
      pending.delete(id);
      resolve(decision);
    });
    emit({
      type: "approval",
      id,
      name: req.toolName,
      input: req.input ?? null,
    });
  });
}

const systemPrompt = [
  `Ты — Mide AGI, кодинг-агент приложения Mide.`,
  `Рабочая папка проекта: ${WORKSPACE}. Все пути в тулах — абсолютные внутри неё.`,
  `Ты умеешь: читать файлы (read_files), искать по коду (search_codebase),`,
  `править и создавать файлы (editor), выполнять команды (run_commands), читать веб.`,
  `Сначала читай, потом правь: editor требует точного совпадения old_text.`,
  `Команды shell и правки файлов могут потребовать подтверждения пользователя.`,
  `Отвечай кратко и по делу, на русском языке. Не выдумывай содержимое файлов.`,
].join("\n");

const agent = new Agent({
  providerId,
  modelId,
  apiKey,
  ...(baseUrl ? { baseUrl } : {}),
  systemPrompt,
  tools,
  maxIterations: 40,
  toolPolicies: AUTO_APPROVE
    ? undefined
    : { run_commands: { enabled: true, autoApprove: false } },
  requestToolApproval: requestApproval,
});

let running = false;

// --- HTTP-сервер --------------------------------------------------------------
function cors(res) {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
}

async function readJsonBody(req) {
  let body = "";
  for await (const chunk of req) body += chunk;
  try {
    return JSON.parse(body || "{}");
  } catch {
    return {};
  }
}

const server = http.createServer(async (req, res) => {
  cors(res);
  if (req.method === "OPTIONS") {
    res.writeHead(204);
    res.end();
    return;
  }

  const url = new URL(req.url, `http://${req.headers.host || "localhost"}`);
  const json = (code, obj) => {
    res.writeHead(code, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify(obj));
  };

  // --- health ---
  if (url.pathname === "/health" && req.method === "GET") {
    json(200, {
      ok: true,
      name: "Mide AGI",
      provider: providerId,
      model: modelId,
      baseUrl: baseUrl ?? null,
      workspace: WORKSPACE,
      autoApprove: AUTO_APPROVE,
      tools: tools.map((t) => t.name),
      busy: running,
    });
    return;
  }

  // --- reset ---
  if (url.pathname === "/reset" && req.method === "POST") {
    agent.restore([]);
    json(200, { ok: true });
    return;
  }

  // --- stop ---
  if (url.pathname === "/stop" && req.method === "POST") {
    if (running) agent.abort("остановлено пользователем");
    json(200, { ok: true, wasRunning: running });
    return;
  }

  // --- approve ---
  if (url.pathname === "/approve" && req.method === "POST") {
    const body = await readJsonBody(req);
    const settle = pending.get(String(body.id ?? ""));
    if (!settle) {
      json(404, { error: "Запрос подтверждения не найден (истёк или его не было)" });
      return;
    }
    settle({
      approved: body.ok === true,
      reason: body.ok === true ? undefined : String(body.reason ?? "Пользователь отклонил"),
    });
    json(200, { ok: true });
    return;
  }

  // --- chat (SSE) ---
  if (url.pathname === "/chat" && req.method === "POST") {
    const body = await readJsonBody(req);
    const message = body.message;
    if (typeof message !== "string" || !message.trim()) {
      json(400, { error: 'Ожидается { "message": "..." }' });
      return;
    }
    if (running) {
      json(409, { error: "Агент занят — дождитесь завершения текущего запроса" });
      return;
    }
    running = true;

    res.writeHead(200, {
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
    });
    const send = (ev) => res.write(`data: ${JSON.stringify(ev)}\n\n`);
    emit = send;

    const unsubscribe = agent.subscribe((ev) => {
      try {
        switch (ev.type) {
          case "assistant-text-delta":
            send({ type: "text", text: ev.text });
            break;
          case "assistant-reasoning-delta":
            send({ type: "reasoning", text: ev.text });
            break;
          case "tool-started":
            send({
              type: "tool_start",
              name: ev.toolCall?.toolName ?? "?",
              input: ev.toolCall?.input ?? null,
            });
            break;
          case "tool-finished":
            send({
              type: "tool_end",
              name: ev.toolCall?.toolName ?? "?",
              output: toolOutput(ev.message),
            });
            break;
          default:
            break;
        }
      } catch {
        /* клиент отвалился — игнорируем */
      }
    });

    req.on("close", () => {
      if (!res.writableEnded) {
        unsubscribe();
        emit = () => {};
        agent.abort("клиент отключился");
      }
    });

    try {
      const result = await agent.run(message.trim());
      send({
        type: "done",
        status: result.status,
        outputText: result.outputText,
        error: result.error ? String(result.error) : undefined,
      });
    } catch (e) {
      send({ type: "error", message: String(e?.message ?? e) });
    } finally {
      unsubscribe();
      emit = () => {};
      for (const settle of pending.values()) {
        settle({ approved: false, reason: "Соединение закрыто" });
      }
      running = false;
      if (!res.writableEnded) res.end();
    }
    return;
  }

  res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
  res.end("Not found");
});

/// Итог тула из сообщения tool-result (Cline кладёт его в content parts).
function toolOutput(message) {
  const parts = message?.content;
  if (!Array.isArray(parts)) return null;
  const part = parts.find((p) => p?.type === "tool-result");
  const out = part?.output;
  const text = typeof out === "string" ? out : (() => {
    try {
      return JSON.stringify(out);
    } catch {
      return String(out);
    }
  })();
  return text && text.length > 4000 ? text.slice(0, 4000) + "\n…[обрезано]" : text;
}

server.listen(PORT, () => {
  console.log("═══════════════════════════════════════════════════");
  console.log("  Mide AGI sidecar (Cline SDK)");
  console.log(`  Провайдер : ${providerId}`);
  console.log(`  Модель    : ${modelId}`);
  console.log(`  Рабочая   : ${WORKSPACE}`);
  console.log(`  Тулы      : ${tools.map((t) => t.name).join(", ")}`);
  console.log(`  Сервер    : http://127.0.0.1:${PORT}`);
  console.log(`  Подтверждение команд: ${AUTO_APPROVE ? "ВЫКЛ (всё разрешено)" : "через UI (POST /approve)"}`);
  console.log("═══════════════════════════════════════════════════");
});
