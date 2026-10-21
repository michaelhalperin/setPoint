/**
 * Phase 0 cost sheet. List prices from Anthropic docs 2026-10-21
 * (Sonnet 5.5 $3/$15 was older; current overview: $2 / $10 per MTok.
 * Haiku 5.5 from $0.10 / $0.50. Cache reads 0.05× on Sonnet 5.5).
 *
 * Fill measured tokens from staging; until then these are fixture estimates
 * used as the exit-criterion template.
 */
export const COST_SHEET = {
  models: {
    coach: { id: 'claude-sonnet-5-5', inputPerMTok: 2, outputPerMTok: 10, cacheReadMult: 0.05 },
    validator: { id: 'claude-haiku-5-5', inputPerMTok: 0.1, outputPerMTok: 0.5, cacheReadMult: 0.1 },
  },
  estimates: {
    coachInputUncached: 2200,
    coachInputCached: 1600,
    coachOutput: 220,
    validatorInput: 900,
    validatorOutput: 40,
    p50TurnsPerActiveDay: 4,
    quotaCapTurns: 20,
    pilotUsers: 15,
    pilotDays: 28,
  },
  quota: { perHour: 10, perDay: 20 },
  notes: [
    'No token streaming in Phase 1 — stage progress covers wait.',
    'Haiku validator runs every turn; include it in p95.',
    'Replace estimates with measured en/he fixture token counts before flag-on.',
  ],
} as const;

export function dollarsForTurn(opts: { cached: boolean }): number {
  const e = COST_SHEET.estimates;
  const c = COST_SHEET.models.coach;
  const v = COST_SHEET.models.validator;
  const coachIn = opts.cached ? e.coachInputCached * c.cacheReadMult : e.coachInputUncached;
  const coach = (coachIn / 1e6) * c.inputPerMTok + (e.coachOutput / 1e6) * c.outputPerMTok;
  const val = (e.validatorInput / 1e6) * v.inputPerMTok + (e.validatorOutput / 1e6) * v.outputPerMTok;
  return coach + val;
}

export function dollarsPerActiveUserDay(opts: { cached: boolean; turns?: number }): number {
  const turns = opts.turns ?? COST_SHEET.estimates.p50TurnsPerActiveDay;
  return dollarsForTurn(opts) * turns;
}

export function costSheetSummary() {
  const uncached = dollarsForTurn({ cached: false });
  const cached = dollarsForTurn({ cached: true });
  const p50Day = dollarsPerActiveUserDay({ cached: true });
  const quotaDay = dollarsPerActiveUserDay({ cached: true, turns: COST_SHEET.estimates.quotaCapTurns });
  const pilot = p50Day * COST_SHEET.estimates.pilotUsers * COST_SHEET.estimates.pilotDays;
  return {
    perTurnP50Uncached: uncached,
    perTurnP50Cached: cached,
    perActiveUserDayP50: p50Day,
    perActiveUserDayQuotaCap: quotaDay,
    pilotTotal: pilot,
    pilot10x: pilot * 10,
  };
}
