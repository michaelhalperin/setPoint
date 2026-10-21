/**
 * Layer 2a — rules before the model. High precision. "Eat less salt" must not trip.
 * Either this or distress_flag on the model reply is a trip.
 */
export type DistressHit = { code: string } | null;

const WEIGHT_OBJECT =
  /\b(kcal|calorie|calories|קלורי|משקל|weight|fat|שומן|body|גוף|deficit|גירעון|cut|cutting|diet|דיאטה)\b/i;

const EAT_LESS = /\b(eat\s+less|eat\s+fewer|lose\s+weight|cut\s+(?:cals|calories|kcal)|deficit|be\s+smaller|get\s+skinny)\b/i;
const EAT_LESS_HE = /(לאכול\s+פחות|לרדת\s+במשקל|לרדת\s+משקל|לחתוך\s+קלור|גירעון)/;

const SALT_EXCEPTION = /\b(salt|sodium)\b|מלח|נתרן/i;

const ED = /\b(purg|vomit|laxative|binge|anorex|bulim|ed\b|eating\s+disorder|make\s+myself\s+sick|scoff)\b/i;
const ED_HE = /(להקיא|משלשל|בולמוס|אנורקס|בולימ|הפרעת\s+אכילה|הפרעות\s+אכילה)/;

const SELF_HARM = /\b(kill\s+myself|suicide|self[- ]harm|want\s+to\s+die)\b/i;
const SELF_HARM_HE = /(להתאבד|לפגוע\s+בעצמי|לא\s+רוצה\s+לחיות)/;

export function detectDistress(message: string): DistressHit {
  const text = message.trim();
  if (!text) return null;

  if (SELF_HARM.test(text) || SELF_HARM_HE.test(text)) return { code: 'self_harm' };
  if (ED.test(text) || ED_HE.test(text)) return { code: 'ed' };

  const less = EAT_LESS.test(text) || EAT_LESS_HE.test(text);
  if (less && SALT_EXCEPTION.test(text) && !WEIGHT_OBJECT.test(text.replace(SALT_EXCEPTION, ''))) {
    return null;
  }
  if (less && WEIGHT_OBJECT.test(text)) return { code: 'restriction' };
  if (EAT_LESS.test(text) && !SALT_EXCEPTION.test(text)) return { code: 'restriction' };
  if (EAT_LESS_HE.test(text) && !SALT_EXCEPTION.test(text)) return { code: 'restriction' };

  return null;
}
