/** Minimum age aligned with the privacy policy and terms (16+). */
export const MIN_AGE_YEARS = 16;

export class UnderageError extends Error {
  constructor() {
    super(`SetPoint is for people ${MIN_AGE_YEARS} or older.`);
  }
}

export function assertMinimumAge(ageYears: number | null | undefined): void {
  if (ageYears == null) return;
  if (ageYears < MIN_AGE_YEARS) throw new UnderageError();
}
