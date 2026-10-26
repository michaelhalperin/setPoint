import { FOOD_NAMES_HE } from './foodNames.js';

/** The two languages the app speaks. Anything else is English. */
export type Lang = 'en' | 'he';

export function langOf(value: string | null | undefined): Lang {
  return value === 'he' ? 'he' : 'en';
}

export function foodNameIn(name: string, lang: Lang): string {
  return lang === 'he' ? (FOOD_NAMES_HE[name] ?? name) : name;
}

/** 24-hour clock for minutes after midnight — "13:45". */
export function clock24(min: number): string {
  const wrapped = ((min % 1440) + 1440) % 1440;
  return `${String(Math.floor(wrapped / 60)).padStart(2, '0')}:${String(wrapped % 60).padStart(2, '0')}`;
}

/** What the model is told so it writes in the user's language. */
export function languageInstruction(lang: Lang): string {
  return lang === 'he'
    ? 'Write in natural, modern Hebrew, addressing the user in the masculine singular. Keep numbers as digits.'
    : '';
}

const SLOT_HE: Record<string, string> = {
  breakfast: 'ארוחת הבוקר',
  lunch: 'ארוחת הצהריים',
  dinner: 'ארוחת הערב',
  snack_am: 'הנשנוש',
  snack_pm: 'הנשנוש',
  snack: 'הנשנוש',
};

/** "ארוחת הצהריים" — the meal a check-in is about, in Hebrew. */
export function slotNameHe(slot: string): string {
  return SLOT_HE[slot] ?? (slot.startsWith('snack') ? 'הנשנוש' : 'הארוחה');
}

/** Feminine for meals, masculine for the snack — "was light". */
export function wasLightHe(slot: string): string {
  return slotNameHe(slot) === 'הנשנוש' ? 'היה קל' : 'הייתה קלה';
}
