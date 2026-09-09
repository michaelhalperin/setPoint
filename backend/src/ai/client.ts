import Anthropic from '@anthropic-ai/sdk';
import { env } from '../env.js';

let cached: Anthropic | null | undefined;

/**
 * The shared Anthropic client, or null when `ANTHROPIC_API_KEY` is unset — every
 * AI feature has a deterministic fallback, so a missing key degrades rather than
 * breaks (plan §7).
 */
export function getAnthropic(): Anthropic | null {
  if (cached !== undefined) return cached;
  cached = env.ANTHROPIC_API_KEY ? new Anthropic({ apiKey: env.ANTHROPIC_API_KEY }) : null;
  if (!cached) {
    console.warn('[ai] ANTHROPIC_API_KEY not set — AI features use deterministic fallbacks');
  }
  return cached;
}
