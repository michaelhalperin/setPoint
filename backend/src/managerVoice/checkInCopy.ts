import type { ManagerVoiceContext } from './types.js';
import { slotNameHe } from '../i18n/index.js';

/**
 * The words on a check-in notification. Written from facts the engine has (which meal slipped, how
 * long since the person last ate, what to eat), never by a model: a generated line once told
 * someone who was behind that they were on pace. Quiet and short, a manager and not a punisher.
 */
export function checkInCopy(ctx: ManagerVoiceContext): string {
  const hours = ctx.hoursSinceMeal !== null && ctx.hoursSinceMeal >= 2 ? Math.round(ctx.hoursSinceMeal) : null;
  if (ctx.lang === 'he') {
    const since = hours ? ` עברו ${hours} שעות מהארוחה האחרונה.` : '';
    const directive = ctx.prescriptionSummary ? ` נסה ${ctx.prescriptionSummary}.` : '';
    if (ctx.tier <= 1) {
      return ctx.slot ? `${slotNameHe(ctx.slot)} התפספסה.${since}${directive}` : `הגיע הזמן לאכול.${since}${directive}`;
    }
    return `תאכל עכשיו.${since}${directive}`;
  }
  const since = hours ? ` ${hours} hours since you last ate.` : '';
  const directive = ctx.prescriptionSummary ? ` Try ${ctx.prescriptionSummary}.` : '';
  if (ctx.tier <= 1) {
    return ctx.slot ? `${cap(ctx.slot)} slipped.${since}${directive}` : `Time to eat.${since}${directive}`;
  }
  return `Eat now.${since}${directive}`;
}

function cap(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1).replace(/_/g, ' ');
}
