/** Deterministic post-workout snack — shake + banana. */
export function refuelPrescription() {
  const items = [
    { name: 'Protein shake', quantity: 1, kcal: 250, proteinG: 30, carbsG: 12, fatG: 5 },
    { name: 'Banana', quantity: 1, kcal: 90, proteinG: 1, carbsG: 23, fatG: 0 },
  ];
  return {
    targetKcal: 340,
    targetProteinG: 31,
    totalKcal: 340,
    totalProteinG: 31,
    totalCarbsG: 35,
    totalFatG: 5,
    items,
  };
}
