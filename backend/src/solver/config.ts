/**
 * Prescription solver configuration (plan §2). A constraint solver over the
 * curated staple-food list — never an LLM freestyling suggestions that might
 * ignore a hard-excluded allergen (§7).
 */
export const SOLVER_CONFIG = {
  /** Most distinct foods in one prescription (plan examples are 1–2 items). */
  maxItems: 3,
  /** Most servings of a single food. */
  maxQtyPerItem: 3,

  /** A single prescription targets a meal-sized slice of the day's remaining gap. */
  minMealKcal: 300,
  maxMealKcal: 700,
  /** Protein asked for in one meal, at most. */
  maxProteinPerMeal: 60,

  // --- scoring weights (higher score = better candidate) ---
  /** Undershooting the calorie target is worse than overshooting ("eat enough"). */
  underKcalWeight: 2,
  overKcalWeight: 1,
  /** Reward for protein delivered, up to the target. */
  proteinWeight: 2.5,
  /** Even with no explicit protein target, nudge toward this much per meal so a
   *  prescription isn't just the densest snack that matches the calories. */
  impliedProteinFloorG: 20,
  /** Penalty per distinct food — prefer fewer, simpler items. */
  perItemPenalty: 25,
  /** Penalty for a food that needs cooking / prep. */
  cookPenalty: 40,

  /** Reject a candidate outside this band around the (clamped) target. */
  minKcalRatio: 0.6,
  maxKcalRatio: 1.8,
} as const;

export type SolverConfig = typeof SOLVER_CONFIG;
