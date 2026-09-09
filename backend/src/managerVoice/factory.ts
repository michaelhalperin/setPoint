import { getAnthropic } from '../ai/client.js';
import { createAiManagerVoice } from './ai.js';
import { fallbackManagerVoice } from './fallback.js';
import type { ManagerVoice } from './types.js';

/** Claude-backed manager's voice when a key is configured, otherwise the deterministic stand-in. */
export function createManagerVoice(): ManagerVoice {
  const client = getAnthropic();
  return client ? createAiManagerVoice(client, fallbackManagerVoice) : fallbackManagerVoice;
}
