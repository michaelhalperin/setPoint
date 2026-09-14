import { describe, expect, it } from 'vitest';
import { STOP_CONFIG, evaluateStopConditions, type StopSignals } from './stopConditions.js';

const NOW = new Date('2026-09-14T12:00:00Z');
const minutesAgo = (m: number) => new Date(NOW.getTime() - m * 60_000);
const r = (numerator: number, denominator: number) => ({ numerator, denominator });

const healthy = (over: Partial<StopSignals> = {}): StopSignals => ({
  schedulerLastRunAt: minutesAgo(10),
  schedulerLastOk: true,
  delivery: r(1, 100),
  negativeFeedback: { wearable: r(5, 50), control: r(5, 50) },
  paused: { wearable: r(1, 20), control: r(1, 20) },
  ...over,
});

describe('evaluateStopConditions', () => {
  it('raises nothing when everything is healthy', () => {
    const e = evaluateStopConditions(healthy(), NOW);
    expect(e.haltWearable).toBe(false);
    expect(e.alerts).toEqual([]);
    expect(e.rates.deliveryFailRate).toBe(0.01);
  });

  it('tolerates a late GitHub run but flags a scheduler that has stopped', () => {
    expect(evaluateStopConditions(healthy({ schedulerLastRunAt: minutesAgo(30) }), NOW).alerts).toEqual([]);
    expect(
      evaluateStopConditions(healthy({ schedulerLastRunAt: minutesAgo(STOP_CONFIG.schedulerStaleMin + 1) }), NOW).alerts,
    ).toContain('scheduler_stale');
    expect(evaluateStopConditions(healthy({ schedulerLastRunAt: null }), NOW).alerts).toContain('scheduler_stale');
    expect(evaluateStopConditions(healthy({ schedulerLastOk: false }), NOW).alerts).toContain('scheduler_failing');
  });

  it('alerts on failing delivery, measured from delivery status', () => {
    const e = evaluateStopConditions(healthy({ delivery: r(20, 100) }), NOW);
    expect(e.alerts).toContain('delivery_failing');
    expect(e.haltWearable).toBe(false);
  });

  it('halts the wearable modifier when its cohort dismisses more than control', () => {
    const e = evaluateStopConditions(
      healthy({ negativeFeedback: { wearable: r(15, 50), control: r(5, 50) } }),
      NOW,
    );
    expect(e.haltWearable).toBe(true);
    expect(e.reasons).toContain('wearable_negative_feedback');
  });

  it('halts the wearable modifier when its cohort pauses more than control', () => {
    const e = evaluateStopConditions(healthy({ paused: { wearable: r(5, 20), control: r(1, 20) } }), NOW);
    expect(e.haltWearable).toBe(true);
    expect(e.reasons).toContain('wearable_pauses');
  });

  it('decides nothing from too little data', () => {
    const e = evaluateStopConditions(
      healthy({
        delivery: r(3, 5),
        negativeFeedback: { wearable: r(5, 6), control: r(0, 6) },
        paused: { wearable: r(3, 4), control: r(0, 4) },
      }),
      NOW,
    );
    expect(e.haltWearable).toBe(false);
    expect(e.alerts).toEqual([]);
    expect(e.rates.deliveryFailRate).toBeNull();
  });
});
