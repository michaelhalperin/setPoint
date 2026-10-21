import { describe, expect, it } from 'vitest';
import { refuelMealFor, refuelStatus, todaySteps } from './status.js';

const at = (hhmm: string) => new Date(`2026-10-15T${hhmm}:00Z`);
const run = { start: at('17:00'), durationMin: 60 }; // ends 18:00, refuel by 18:45

describe('refuelStatus', () => {
  it('is null on a rest day and planned before the session ends', () => {
    expect(refuelStatus([], [], at('12:00'))).toBeNull();
    expect(refuelStatus([run], [], at('17:30'))).toBe('planned');
  });

  it('is due while the window is open, done with a real meal in it, missed after', () => {
    expect(refuelStatus([run], [], at('18:20'))).toBe('due');
    expect(refuelStatus([run], [{ loggedAt: at('18:30'), kcal: 320 }], at('18:31'))).toBe('done');
    expect(refuelStatus([run], [{ loggedAt: at('18:30'), kcal: 120 }], at('19:00'))).toBe('missed');
    expect(refuelStatus([run], [{ loggedAt: at('19:10'), kcal: 600 }], at('19:30'))).toBe('missed');
  });
});

describe('todaySteps', () => {
  it('marks the snack before, the session, the refuel and dinner as they happen', () => {
    const meals = [
      { loggedAt: at('15:30'), kcal: 250 },
      { loggedAt: at('18:20'), kcal: 320 },
      { loggedAt: at('19:40'), kcal: 850 },
    ];
    expect(todaySteps(run, at('19:30'), meals, at('20:00'))).toEqual({ before: true, workout: true, refuel: true, dinner: true });
    expect(todaySteps(run, at('19:30'), meals.slice(0, 1), at('16:00'))).toEqual({ before: true, workout: false, refuel: false, dinner: false });
  });

  it('does not count the refuel as dinner', () => {
    const steps = todaySteps(run, at('18:30'), [{ loggedAt: at('18:20'), kcal: 320 }], at('19:00'));
    expect(steps.refuel).toBe(true);
    expect(steps.dinner).toBe(false);
  });
});

describe('refuelMealFor', () => {
  it('finds the meal that counted, or null', () => {
    const session = { start: new Date('2026-10-20T14:00:00Z'), durationMin: 60 };
    const meals = [
      { loggedAt: new Date('2026-10-20T15:30:00Z'), kcal: 300 },
      { loggedAt: new Date('2026-10-20T15:10:00Z'), kcal: 420 },
    ];
    expect(refuelMealFor([session], meals)).toEqual({ at: '2026-10-20T15:10:00.000Z', kcal: 420 });
    expect(refuelMealFor([session], [{ loggedAt: new Date('2026-10-20T17:00:00Z'), kcal: 500 }])).toBeNull();
  });
});
