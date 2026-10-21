import { describe, expect, it } from 'vitest';
import { COST_SHEET, costSheetSummary, dollarsForTurn } from './costSheet.js';

describe('cost sheet', () => {
  it('has pinned 5.5 model ids and a positive per-turn cost', () => {
    expect(COST_SHEET.models.coach.id).toBe('claude-sonnet-5-5');
    expect(COST_SHEET.models.validator.id).toBe('claude-haiku-5-5');
    expect(COST_SHEET.quota.perDay).toBe(20);
    expect(dollarsForTurn({ cached: false })).toBeGreaterThan(0);
    expect(dollarsForTurn({ cached: true })).toBeLessThan(dollarsForTurn({ cached: false }));
  });

  it('fills the Phase 0 exit-criterion lines', () => {
    const sheet = costSheetSummary();
    expect(sheet.perActiveUserDayP50).toBeGreaterThan(0);
    expect(sheet.perActiveUserDayQuotaCap).toBeGreaterThan(sheet.perActiveUserDayP50);
    expect(sheet.pilot10x).toBe(sheet.pilotTotal * 10);
  });
});
