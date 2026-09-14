import { describe, expect, it } from 'vitest';
import { evaluateStopConditions } from './stopConditions.js';

describe('evaluateStopConditions', () => {
  it('keeps scoring on when delivery is healthy', () => {
    const result = evaluateStopConditions({
      wearableEnabled: false,
      schedulerStale: false,
      deliveryFailRate: 0.02,
      optOutRate: 0.05,
    });
    expect(result.disableScoring).toBe(false);
    expect(result.disableWearable).toBe(false);
  });

  it('disables scoring when the scheduler is stale or delivery fails', () => {
    expect(
      evaluateStopConditions({
        wearableEnabled: false,
        schedulerStale: true,
        deliveryFailRate: 0,
        optOutRate: 0,
      }).disableScoring,
    ).toBe(true);
    expect(
      evaluateStopConditions({
        wearableEnabled: false,
        schedulerStale: false,
        deliveryFailRate: 0.2,
        optOutRate: 0,
      }).disableScoring,
    ).toBe(true);
  });

  it('disables the wearable modifier when opt-outs climb', () => {
    const result = evaluateStopConditions({
      wearableEnabled: true,
      schedulerStale: false,
      deliveryFailRate: 0,
      optOutRate: 0.25,
    });
    expect(result.disableWearable).toBe(true);
    expect(result.reasons).toContain('wearable_opt_out');
  });
});
