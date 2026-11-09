import { Agent, createBuiltinTools } from "@cline/sdk";

const tools = createBuiltinTools({
  cwd: process.cwd(),
  shell: "bash",
  enableBash: true,
  enableEditor: true,
});

const agent = new Agent({
  providerId: "openai-compatible",
  modelId: "gpt-oss-20b",
  baseUrl: "https://oai.endpoints.kepler.ai.cloud.ovh.net/v1",
  systemPrompt:
    "Ты кодинг-агент. Ответь кратко. Используй инструменты для дела, не для демонстрации.",
  tools,
  maxIterations: 4,
  toolPolicies: { run_commands: { enabled: true, autoApprove: false } },
  requestToolApproval: async (req) => {
    console.log("APPROVAL:", JSON.stringify(req, null, 1));
    return { approved: true };
  },
});

const seen = new Map();
agent.subscribe((ev) => {
  if (!seen.has(ev.type)) {
    seen.set(
      ev.type,
      JSON.stringify(
        Object.fromEntries(
          Object.entries(ev).map(([k, v]) => [
            k,
            Array.isArray(v) ? `[${v.length}]` : typeof v === "object" && v ? Object.keys(v).join("|") : typeof v,
          ]),
        ),
      ).slice(0, 300),
    );
  }
});
const t0 = Date.now();
const r = await agent.run(
  "Создай файл .census.txt в текущей папке со словом hello, затем посчитай символы в нём через shell и скажи результат.",
);
console.log("wall", Date.now() - t0, "status", r.status, "err", String(r.error ?? ""));
for (const [k, v] of seen) console.log("EVENT", k, "=>", v);
console.log("TOOLNAMES", tools.map((t) => t.name).join(","));
