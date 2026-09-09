export type SolverFood = {
  slug: string;
  name: string;
  servingDesc: string;
  kcal: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
  tags: string[];
  allergens: string[];
};

export type PrescriptionConstraints = {
  /** Calories to fill with this prescription (before the meal-size clamp). */
  targetKcal: number;
  /** Protein to aim for this meal, or null when the user has no protein target. */
  targetProteinG: number | null;
  /** Normalized restriction tokens — hard exclusions (allergens, lifestyle). */
  excludedTokens: string[];
  /** Weight no-cook / portable options more heavily (busy user, firm tier). */
  preferLowFriction?: boolean;
};

export type PrescriptionLineItem = {
  slug: string;
  name: string;
  servingDesc: string;
  quantity: number;
  kcal: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
};

export type PrescriptionResult = {
  items: PrescriptionLineItem[];
  totalKcal: number;
  totalProteinG: number;
  totalCarbsG: number;
  totalFatG: number;
  /** The clamped meal-size target the solver actually aimed at. */
  targetKcal: number;
  targetProteinG: number | null;
};
