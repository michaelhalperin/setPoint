import type {
  DaySummaryContext,
  HomeNoteContext,
  ManagerVoice,
  ManagerVoiceContext,
} from './types.js';
import { slotNameHe } from '../i18n/index.js';

/**
 * Deterministic copy. Tone per plan §6: a manager, not a punisher — assertive,
 * specific, never shaming. Tier 3 is a conversation, handled elsewhere.
 */
export const fallbackManagerVoice: ManagerVoice = {
  async checkInMessage(ctx: ManagerVoiceContext): Promise<string> {
    if (ctx.lang === 'he') {
      const directive = ctx.prescriptionSummary ? ` נסה ${ctx.prescriptionSummary}.` : '';
      if (ctx.tier <= 1) {
        return ctx.slot ? `${slotNameHe(ctx.slot)} התפספסה.${directive}` : `הגיע הזמן לאכול.${directive}`;
      }
      return `תאכל עכשיו.${directive}`;
    }
    const directive = ctx.prescriptionSummary ? ` Try ${ctx.prescriptionSummary}.` : '';
    if (ctx.tier <= 1) {
      return ctx.slot ? `${cap(ctx.slot)} slipped.${directive}` : `Time to eat.${directive}`;
    }
    return `Eat now.${directive}`;
  },

  async homeNote(ctx: HomeNoteContext): Promise<string> {
    if (ctx.lang === 'he') return homeNoteHe(ctx);
    // The screen shows the numbers; the note is about timing and what's next.
    const meal = cap(ctx.nextMeal);

    // Quiet mode (§3): describe the day, never prompt or push.
    if (!ctx.enforcementEnabled) {
      return ctx.mealsToday === 0 ? `Nothing logged yet today.` : `Here's today so far.`;
    }

    if (ctx.hasActiveCheckIn) {
      return `There's a check-in waiting just below.`;
    }

    if (ctx.state === 'over') {
      return `A bit past target today. Nothing to fix — steer back tomorrow.`;
    }

    if (ctx.mealsToday === 0) {
      if (ctx.nextMeal === 'breakfast') return `A real breakfast now keeps lunch and dinner ordinary.`;
      if (ctx.nextMeal === 'lunch') return `Nothing logged yet — lunch needs to be a full one.`;
      return `Nothing logged yet — dinner has to carry the day.`;
    }

    if (ctx.state === 'on_track') {
      return `On track. ${meal} rounds it out.`;
    }

    switch (ctx.paceStatus) {
      case 'behind':
        return `${meal} is running late — worth making it a full one.`;
      case 'ahead':
        return `Ahead of your usual pace. ${meal} next.`;
      default:
        return `Good rhythm so far. ${meal} next.`;
    }
  },

  async daySummary(ctx: DaySummaryContext): Promise<string> {
    if (ctx.lang === 'he') {
      switch (ctx.kind) {
        case 'MISSED':
          return 'לא תועד כלום.';
        case 'UNDER':
          return `${Math.round(ctx.kcalTarget - ctx.kcalConsumed)} קלוריות מתחת ליעד.`;
        case 'OVER':
          return 'מעל היעד.';
        default:
          return 'על היעד.';
      }
    }
    switch (ctx.kind) {
      case 'MISSED':
        return `Nothing logged.`;
      case 'UNDER':
        return `${Math.round(ctx.kcalTarget - ctx.kcalConsumed)} kcal under target.`;
      case 'OVER':
        return `Over target.`;
      default:
        return `On target.`;
    }
  },
};

export function mealWindow(
  mins: number,
  times: { lunchMin: number; dinnerMin: number },
): HomeNoteContext['nextMeal'] {
  if (mins < times.lunchMin) return 'breakfast';
  if (mins < times.dinnerMin) return 'lunch';
  return 'dinner';
}

function cap(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}

function homeNoteHe(ctx: HomeNoteContext): string {
  const meal = slotNameHe(ctx.nextMeal);
  if (!ctx.enforcementEnabled) {
    return ctx.mealsToday === 0 ? 'עדיין לא תועד כלום היום.' : 'הנה היום עד עכשיו.';
  }
  if (ctx.hasActiveCheckIn) return 'יש תזכורת שמחכה ממש למטה.';
  if (ctx.state === 'over') return 'קצת מעל היעד היום. אין מה לתקן — חוזרים לקצב מחר.';
  if (ctx.mealsToday === 0) {
    if (ctx.nextMeal === 'breakfast') return 'ארוחת בוקר אמיתית עכשיו שומרת על שאר היום רגיל.';
    if (ctx.nextMeal === 'lunch') return 'עדיין לא תועד כלום — ארוחת הצהריים צריכה להיות מלאה.';
    return 'עדיין לא תועד כלום — ארוחת הערב צריכה לשאת את היום.';
  }
  if (ctx.state === 'on_track') return `בקצב. ${meal} משלימה את זה.`;
  switch (ctx.paceStatus) {
    case 'behind':
      return `${meal} מתאחרת — כדאי שתהיה מלאה.`;
    case 'ahead':
      return `לפני הקצב הרגיל שלך. ${meal} הבאה.`;
    default:
      return `קצב טוב עד עכשיו. ${meal} הבאה.`;
  }
}
