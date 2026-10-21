import { describe, expect, it } from 'vitest';
import { PILOT, scorePilot, type PilotCounts } from './pilot.js';

const floor: PilotCounts = {
  flagOnUsers: 15,
  holdoutUsers: 15,
  checkInsFlagOn: 50,
  checkInsHoldout: 50,
  opens: 10,
  sends: 40,
  confirms: 4,
  trips: 1,
  layer1LlmTurns: 0,
};

describe('scorePilot', () => {
  it('stays too_early until the sample floor', () => {
    const score = scorePilot({ ...floor, flagOnUsers: 5, holdoutUsers: 5 });
    expect(score.sampleFloorMet).toBe(false);
    expect(score.verdict).toBe('too_early');
  });

  it('reports ITT and opener rates separately', () => {
    const score = scorePilot(floor);
    expect(score.ittConfirmRate).toBeCloseTo(4 / 15);
    expect(score.openerRate).toBeCloseTo(10 / 15);
    expect(score.confirmAmongOpeners).toBeCloseTo(0.4);
    expect(score.verdict).toBe('expand');
  });

  it('keeps Phase 1 when confirm-among-openers is under 15%', () => {
    const score = scorePilot({ ...floor, opens: 20, confirms: 2 });
    expect(score.confirmAmongOpeners).toBeLessThan(PILOT.expand.keepBelowOpenerConfirm);
    expect(score.verdict).toBe('keep');
  });

  it('hard-kills on Layer-1 LLM turns or a >15% trip rate', () => {
    expect(scorePilot({ ...floor, layer1LlmTurns: 1 }).verdict).toBe('killed');
    expect(scorePilot({ ...floor, sends: 20, trips: 4 }).hardKill).toContain('trip_rate_kill');
  });

  it('pauses to inspect above a 5% trip rate after the floor', () => {
    const score = scorePilot({ ...floor, sends: 20, trips: 2, confirms: 8, opens: 10 });
    expect(score.pauseTripRate).toBe(true);
    expect(score.verdict).toBe('inspect');
  });
});
