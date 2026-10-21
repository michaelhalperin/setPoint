/**
 * Model choice per plan §7 and specialist-coaches v4.
 * Pins are release events — changing a string here must run `npm run eval:experts`.
 * Verified against Anthropic docs 2026-10-21:
 *   https://platform.claude.com/docs/en/models/overview
 * Meal parse / manager voice keep their existing pins so those surfaces do not
 * silently migrate. The nutrition assistant uses the current 5.5 IDs.
 */
export const MEAL_PARSE_MODEL = 'claude-haiku-4-5';
export const MANAGER_VOICE_MODEL = 'claude-sonnet-5';
export const EXPERT_NUTRITION_MODEL = 'claude-sonnet-5-5';
export const EXPERT_VALIDATOR_MODEL = 'claude-haiku-5-5';
