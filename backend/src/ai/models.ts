/**
 * Model choice per plan §7:
 *  - meal parsing runs constantly → a cheap/fast model
 *  - manager's-voice copy runs rarely → a stronger model is fine
 */
export const MEAL_PARSE_MODEL = 'claude-haiku-4-5';
export const MANAGER_VOICE_MODEL = 'claude-sonnet-5';
