import { Agent, createBuiltinTools } from "@cline/sdk";

const tools = createBuiltinTools({
  cwd: "D:\\Удалять запрещено\\mide",
  shell: "bash",
  enableBash: true,
  enableEditor: true,
});

const agent = new Agent({
  providerId: "openai-compatible",
  modelId: "gpt-oss-20b",
  baseUrl: "https://oai.endpoints.kepler.ai.cloud.ovh.net/v1",
  systemPrompt: "Ты кодинг-агент. Все пути — абсолютные. Отвечай кратко по-русски.",
  tools,
  maxIterations: 40,
  toolPolicies: { run_commands: { enabled: true, autoApprove: false } },
  requestToolApproval: async (r) => {
    console.log("APPROVAL", r.toolName, JSON.stringify(r.input).slice(0, 120));
    return { approved: true };
  },
});

const seen = new Set();
agent.subscribe((ev) => {
  if (!seen.has(ev.type)) { seen.add(ev.type); console.log("ev", ev.type); }
});
try {
  const r = await agent.run(
    'Создай файл D:\\Удалять запрещено\\mide\\.agent_probe_out.txt со содержимым "probe-ok 12345" инструментом editor, затем посчитай в нём символы командой shell и назови число.',
  );
  console.log("status", r.status, "err", r.error?.stack ?? r.error);
  console.log("text", String(r.outputText).slice(0, 300));
} catch (e) {
  console.log("THROWN", e.stack);
}
