import { describe, expect, it } from 'vitest';
import { closeCheckIn, closeDueMin, dailyCapReached, GAP_CONFIG, lightShortfall, topUpGap } from './gap.js';
import { expectedThroughSlot } from './mealSchedule.js';

const times = { breakfastMin: 480, lunchMin: 780, dinnerMin: 1140 }; // 8:00 · 13:00 · 19:00

describe('expectedThroughSlot', () => {
  it('splits the day into equal meal shares', () => {
    expect(expectedThroughSlot('breakfast', 3000, false)).toBe(1000);
    expect(expectedThroughSlot('lunch', 3000, false)).toBe(2000);
    expect(expectedThroughSlot('dinner', 3000, false)).toBe(3000);
  });

  it('uses five shares when snacks are on', () => {
    expect(expectedThroughSlot('lunch', 3000, true)).toBe(1800);
    expect(expectedThroughSlot('snack_pm', 3000, true)).toBe(2400);
  });
});

describe('lightShortfall', () => {
  it('is zero once the day reaches the cover share', () => {
    expect(lightShortfall({ slot: 'lunch', consumedKcal: 1500, targetKcal: 3000, extra: false })).toBe(0);
  });

  it('is the full gap to the expected intake when light', () => {
    expect(lightShortfall({ slot: 'lunch', consumedKcal: 900, targetKcal: 3000, extra: false })).toBe(1100);
  });
});

describe('closeCheckIn', () => {
  const base = {
    nowMin: 1240,
    times,
    quietStartMin: 1380,
    consumedKcal: 2400,
    targetKcal: 3000,
    closedToday: false,
    minSinceLastCheckIn: null,
  };

  it('comes 90 minutes after dinner with the gap capped to one plate', () => {
    expect(closeCheckIn(base)).toEqual({ dueMin: 1230, gapKcal: 600, plateKcal: 600, overdue: true });
    expect(closeCheckIn({ ...base, consumedKcal: 1500 })!.plateKcal).toBe(GAP_CONFIG.closeMaxKcal);
  });

  it('is pulled earlier so it never lands inside quiet hours', () => {
    expect(closeDueMin({ ...times, dinnerMin: 1290 }, 1380)).toBe(1350);
  });

  it('ignores quiet hours that start after midnight', () => {
    expect(closeDueMin(times, 60)).toBe(1230);
  });

  it('stays quiet when the day is nearly covered, or already closed', () => {
    expect(closeCheckIn({ ...base, consumedKcal: 2800 })).toBeNull();
    expect(closeCheckIn({ ...base, closedToday: true })).toBeNull();
  });

  it('waits when another check-in just went out', () => {
    expect(closeCheckIn({ ...base, minSinceLastCheckIn: 20 })!.overdue).toBe(false);
    expect(closeCheckIn({ ...base, minSinceLastCheckIn: 60 })!.overdue).toBe(true);
  });

  it('is not due before its time', () => {
    expect(closeCheckIn({ ...base, nowMin: 1200 })!.overdue).toBe(false);
  });
});

describe('topUpGap', () => {
  const base = { currentSlot: 'lunch' as const, loggedInSlot: true, consumedKcal: 1200, targetKcal: 3000, extra: false };

  it('offers a capped top-up after a light meal', () => {
    expect(topUpGap(base)).toEqual({ slot: 'lunch', behindKcal: 800, topUpKcal: GAP_CONFIG.topUpMaxKcal });
    expect(topUpGap({ ...base, consumedKcal: 1700 })).toEqual({ slot: 'lunch', behindKcal: 300, topUpKcal: 300 });
  });

  it('says nothing before a meal is logged in the slot, or when on pace', () => {
    expect(topUpGap({ ...base, loggedInSlot: false })).toBeNull();
    expect(topUpGap({ ...base, consumedKcal: 1900 })).toBeNull();
    expect(topUpGap({ ...base, consumedKcal: 3100 })).toBeNull();
  });
});

describe('dailyCapReached', () => {
  it('counts check-ins but not tier-3 conversations', () => {
    expect(dailyCapReached([{ tier: 1 }, { tier: 2 }, { tier: 1 }])).toBe(false);
    expect(dailyCapReached([{ tier: 1 }, { tier: 2 }, { tier: 1 }, { tier: 3 }])).toBe(false);
    expect(dailyCapReached([{ tier: 1 }, { tier: 2 }, { tier: 1 }, { tier: 1 }])).toBe(true);
  });
});
