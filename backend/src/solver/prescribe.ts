import { clamp } from '../engine/types.js';
import { SOLVER_CONFIG, type SolverConfig } from './config.js';
import { filterAllowedFoods } from './exclusions.js';
import type { PrescriptionConstraints, PrescriptionResult, SolverFood } from './types.js';

type Portion = {
  food: SolverFood;
  qty: number;
  kcal: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
};

const round1 = (n: number): number => Math.round(n * 10) / 10;

function portionsFor(foods: SolverFood[], maxQty: number): Portion[] {
  const out: Portion[] = [];
  for (const food of foods) {
    for (let qty = 1; qty <= maxQty; qty += 1) {
      out.push({
        food,
        qty,
        kcal: food.kcal * qty,
        proteinG: food.proteinG * qty,
        carbsG: food.carbsG * qty,
        fatG: food.fatG * qty,
      });
    }
  }
  return out;
}

function comboKey(combo: Portion[]): string {
  return combo
    .map((p) => `${p.food.slug}:${p.qty}`)
    .sort()
    .join('|');
}

function scoreCombo(
  combo: Portion[],
  totalKcal: number,
  target: number,
  constraints: PrescriptionConstraints,
  config: SolverConfig,
): number {
  const kcalError = totalKcal - target;
  const kcalPenalty =
    kcalError >= 0 ? kcalError * config.overKcalWeight : -kcalError * config.underKcalWeight;

  const proteinTarget =
    constraints.targetProteinG && constraints.targetProteinG > 0
      ? constraints.targetProteinG
      : config.impliedProteinFloorG;
  const totalProtein = combo.reduce((acc, p) => acc + p.proteinG, 0);
  const proteinBonus = Math.min(totalProtein, proteinTarget) * config.proteinWeight;

  const itemPenalty = combo.length * config.perItemPenalty;

  const frictionWeight = constraints.preferLowFriction ? 1.5 : 1;
  const cookPenalty = combo.reduce((acc, p) => {
    const lowFriction = p.food.tags.includes('no_cook') || p.food.tags.includes('portable');
    return acc + (lowFriction ? 0 : config.cookPenalty * frictionWeight);
  }, 0);

  return proteinBonus - kcalPenalty - itemPenalty - cookPenalty;
}

function toResult(
  combo: Portion[],
  target: number,
  targetProteinG: number | null,
): PrescriptionResult {
  const items = [...combo]
    .sort((a, b) => a.food.slug.localeCompare(b.food.slug))
    .map((p) => ({
      slug: p.food.slug,
      name: p.food.name,
      servingDesc: p.food.servingDesc,
      quantity: p.qty,
      kcal: Math.round(p.kcal),
      proteinG: round1(p.proteinG),
      carbsG: round1(p.carbsG),
      fatG: round1(p.fatG),
    }));

  return {
    items,
    totalKcal: items.reduce((acc, i) => acc + i.kcal, 0),
    totalProteinG: round1(items.reduce((acc, i) => acc + i.proteinG, 0)),
    totalCarbsG: round1(items.reduce((acc, i) => acc + i.carbsG, 0)),
    totalFatG: round1(items.reduce((acc, i) => acc + i.fatG, 0)),
    targetKcal: target,
    targetProteinG,
  };
}

/**
 * Picks 1–`maxItems` staple foods (with integer servings) whose calories land
 * near the meal-sized target, favouring protein when there's a target and
 * fewer / no-cook items always. Deterministic: equal scores break on a stable
 * key. Returns null when nothing acceptable exists (e.g. everything excluded).
 */
export function prescribe(
  foods: SolverFood[],
  constraints: PrescriptionConstraints,
  config: SolverConfig = SOLVER_CONFIG,
): PrescriptionResult | null {
  const allowed = filterAllowedFoods(foods, constraints.excludedTokens);
  if (allowed.length === 0) return null;

  const target = clamp(constraints.targetKcal, config.minMealKcal, config.maxMealKcal);
  const minKcal = target * config.minKcalRatio;
  const maxKcal = target * config.maxKcalRatio;

  const portions = portionsFor(allowed, config.maxQtyPerItem);
  const n = portions.length;

  const state: { best: { combo: Portion[]; score: number; key: string } | null } = { best: null };

  const consider = (combo: Portion[]): void => {
    const totalKcal = combo.reduce((acc, p) => acc + p.kcal, 0);
    if (totalKcal < minKcal || totalKcal > maxKcal) return;

    const score = scoreCombo(combo, totalKcal, target, constraints, config);
    const key = comboKey(combo);
    const best = state.best;
    if (!best || score > best.score || (score === best.score && key < best.key)) {
      state.best = { combo, score, key };
    }
  };

  for (let i = 0; i < n; i += 1) {
    const pi = portions[i]!;
    consider([pi]);
    if (config.maxItems < 2) continue;

    for (let j = i + 1; j < n; j += 1) {
      const pj = portions[j]!;
      if (pj.food.slug === pi.food.slug) continue;
      consider([pi, pj]);
      if (config.maxItems < 3) continue;

      for (let k = j + 1; k < n; k += 1) {
        const pk = portions[k]!;
        if (pk.food.slug === pi.food.slug || pk.food.slug === pj.food.slug) continue;
        consider([pi, pj, pk]);
      }
    }
  }

  if (!state.best) return null;
  return toResult(state.best.combo, target, constraints.targetProteinG);
}

/** A short "eat this" line, e.g. "2× 2 large eggs + Whole wheat bread". */
export function prescriptionSummary(result: PrescriptionResult): string {
  return result.items
    .map((i) => (i.quantity > 1 ? `${i.quantity}× ${i.name}` : i.name))
    .join(' + ');
}
