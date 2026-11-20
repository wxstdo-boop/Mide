// Provider registry: Pollinations + AI Horde.
//
// Both answer *without* a user-supplied key, which is the whole point of this
// app: the AI tab must work on a fresh install with no signup.
//
// Verified anonymously (2026-11):
//   * Pollinations  POST text.pollinations.ai/openai         -> 200
//   * AI Horde      POST oai.aihorde.net/v1/chat/completions -> 200
//                   with the documented anonymous key "0000000000".
//
// Removed after probing because they stopped being anonymous:
//   * LLM7.io  -> 401 "Missing API key" on every model.
//   * OVHcloud -> TLS handshake dies before HTTP; endpoint is gone.
import 'chat_api.dart';

/// AI Horde — crowd-sourced inference. The anonymous key `0000000000` works
/// out of the box at the lowest priority; a real key from
/// https://stablehorde.net/register (free, no card) only raises priority.
///
/// Models are restricted to ids that answered a live request: Horde returns
/// 503 `no_eligible_worker` for models nobody currently serves, and each such
/// id would burn a rotation slot on every message.
const LlmProvider horde = LlmProvider(
  label: 'Horde',
  baseUrl: 'https://oai.aihorde.net/v1',
  authHeader: 'Bearer 0000000000',
  models: [
    'koboldcpp/Llama-3.2-1B-Instruct',
    'koboldcpp/Qwen3-0.6B',
    'koboldcpp/Qwen3-14B',
    'Qwen/Qwen3.8-Flash-Next',
  ],
);

/// Pollinations — free, anonymous, OpenAI-compatible text endpoint.
/// Blocks non-browser user agents, so we send a browser UA.
const LlmProvider pollinations = LlmProvider(
  label: 'Pollinations',
  baseUrl: 'https://text.pollinations.ai',
  chatPath: 'openai',
  userAgent:
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0 Safari/537.36',
  models: ['openai-fast', 'openai'],
);

/// Rotation order: Pollinations first (fast, no queue), then Horde as the
/// fallback that keeps working when Pollinations rate-limits the IP.
const List<LlmProvider> providers = <LlmProvider>[pollinations, horde];

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
