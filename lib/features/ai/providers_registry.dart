// Provider registry: Pollinations + LLM7 + OVH + Horde (fallback).
// The UI shows one "Ada" engine; internally we rotate across providers
// and models until one answers. Anonymous fast providers come first;
// Horde (queue-based, needs a key) is tried last.
import 'chat_api.dart';

/// AI Horde — crowd-sourced LLM gateway. Free registration at
/// https://stablehorde.net/register (no credit card). The token is left
/// as a placeholder so the user can paste their free kudos token; until
/// then the rotation fast-skips it (401).
const LlmProvider horde = LlmProvider(
  label: 'Horde',
  baseUrl: 'https://oai.aihorde.net/v1',
  chatPath: 'chat/completions',
  authHeader: 'Bearer PASTE_YOUR_HORDE_API_KEY',
  // Only one model per Horde slot — queue-based providers are slow and
  // multiple models just multiply the wait. If the 3B model times out,
  // rotation falls straight to the fast anonymous provider.
  models: ['koboldcpp/Llama-3.2-3B'],
);

/// Pollinations — free, anonymous, OpenAI-compatible text endpoint.
/// Blocks non-browser user agents, so we send a browser UA.
const LlmProvider pollinations = LlmProvider(
  label: 'Pollinations',
  baseUrl: 'https://text.pollinations.ai',
  chatPath: 'openai',
  userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
  models: ['openai-fast', 'openai'],
);

/// LLM7.io — free OpenAI-compatible gateway (keyless for some models).
/// Model ids are checked against `GET /v1/models`; a stale id just burns a
/// rotation slot on a 404, so keep this list to live models.
const LlmProvider llm7 = LlmProvider(
  label: 'LLM7',
  baseUrl: 'https://api.llm7.io/v1',
  models: [
    'minimax-m2.7',
    'DeepSeek-V4-Flash-0731',
    'gemini-3-flash',
    'gemma4:31b',
  ],
);

/// OVHcloud AI Endpoints — free keyless (rate-limited per IP).
const LlmProvider ovh = LlmProvider(
  label: 'OVH',
  baseUrl: 'https://oai.endpoints.kepler.ai.cloud.ovh.net/v1',
  models: [
    'gpt-oss-120b',
    'Qwen3.6-27B',
    'Mistral-Small-3.2-24B-Instruct-2506',
    'Meta-Llama-3_3-70B-Instruct',
    'gpt-oss-20b',
  ],
);

/// Rotation order: Pollinations → LLM7 → OVH → Horde (last, fallback).
/// Anonymous keyless providers answer first; the slow queue-based Horde
/// is only reached when everything else is rate-limited or down.
const List<LlmProvider> providers = <LlmProvider>[
  pollinations,
  llm7,
  ovh,
  horde,
];

class RotationSlot {
  final int providerIndex;
  final int modelIndex;

  const RotationSlot(this.providerIndex, this.modelIndex);
}

/// All (provider, model) pairs in rotation order.
List<RotationSlot> get allSlots {
  final out = <RotationSlot>[];
  for (var p = 0; p < providers.length; p++) {
    for (var m = 0; m < providers[p].models.length; m++) {
      out.add(RotationSlot(p, m));
    }
  }
  return out;
}
