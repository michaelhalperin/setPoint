import { describe, expect, it } from 'vitest';
import {
  buildAppetiteHistory,
  foodTag,
  historyWindow,
  mondayOnOrBefore,
} from './history.js';

describe('appetite history', () => {
  it('aligns 28 days to four Mon–Sun weeks containing today', () => {
    // Tuesday 2026-09-15 → this Monday 09-14 → start 08-24
    expect(mondayOnOrBefore('2026-09-15')).toBe('2026-09-14');
    const days = historyWindow('2026-09-15');
    expect(days).toHaveLength(28);
    expect(days[0]).toBe('2026-08-24');
    expect(days[27]).toBe('2026-09-20');
  });

  it('tags drinkable, no-prep, and dense foods', () => {
    expect(foodTag({ slug: 'whole-milk', tags: ['no_cook'] })).toBe('Drinkable');
    expect(foodTag({ slug: 'rotisserie-chicken', tags: ['no_cook'] })).toBe('No prep');
    expect(foodTag({ slug: 'white-rice', tags: [] })).toBe('Dense');
  });

  it('counts low days, eaten %, patterns, and top low-day foods', () => {
    const levels: Record<string, 'HUNGRY' | 'NORMAL' | 'LOW'> = {
      '2026-08-25': 'LOW',
      '2026-08-26': 'LOW',
      '2026-08-27': 'LOW',
      '2026-08-28': 'LOW',
      '2026-08-29': 'LOW',
      '2026-09-01': 'HUNGRY',
      '2026-09-02': 'HUNGRY',
      '2026-09-03': 'HUNGRY',
      '2026-09-04': 'NORMAL',
      '2026-09-05': 'NORMAL',
    };
    // Late dinners on days before most LOW days
    const lastMealMinByDate: Record<string, number> = {
      '2026-08-24': 1300,
      '2026-08-25': 1300,
      '2026-08-26': 1300,
      '2026-08-27': 1300,
      '2026-08-28': 800,
    };
    const consumedByDate: Record<string, number> = {
      '2026-08-25': 2700,
      '2026-08-26': 2800,
      '2026-08-27': 2750,
      '2026-08-28': 2600,
      '2026-08-29': 2650,
      '2026-09-01': 3100,
      '2026-09-02': 3000,
      '2026-09-03': 3050,
      '2026-09-04': 3000,
      '2026-09-05': 2950,
      '2026-08-20': 2000,
      '2026-08-21': 2100,
      '2026-08-22': 2200,
    };
    const history = buildAppetiteHistory({
      todayISO: '2026-09-15',
      targetKcal: 3100,
      levels,
      consumedByDate,
      lastMealMinByDate,
      workoutDates: ['2026-08-31', '2026-09-01', '2026-09-02'],
      lowDayPrescriptions: [
        {
          date: '2026-08-25',
          accepted: true,
          items: [{ name: 'Protein smoothie', slug: 'whey-protein-shake', tags: [] }],
        },
        {
          date: '2026-08-26',
          accepted: true,
          items: [{ name: 'Protein smoothie', slug: 'whey-protein-shake', tags: [] }],
        },
        {
          date: '2026-08-27',
          accepted: false,
          items: [{ name: 'Protein smoothie', slug: 'whey-protein-shake', tags: [] }],
        },
        {
          date: '2026-08-28',
          accepted: true,
          items: [{ name: 'White rice', slug: 'white-rice', tags: [] }],
        },
      ],
    });

    expect(history.days).toHaveLength(28);
    expect(history.days.filter((d) => d.level === 'LOW')).toHaveLength(5);
    expect(history.percentEatenLow).toBeGreaterThan(80);
    expect(history.percentEatenNormal).toBeGreaterThan(90);
    expect(history.percentEatenLowBefore).not.toBeNull();
    expect(history.percentEatenLowBefore!).toBeLessThan(history.percentEatenLow);

    expect(history.patterns.map((p) => p.id)).toContain('late_dinner');
    expect(history.patterns.map((p) => p.id)).toContain('after_training');
    const late = history.patterns.find((p) => p.id === 'late_dinner');
    expect(late?.action?.dinnerMin).toBe(1200);

    expect(history.lowDayFoods[0]?.name).toBe('White rice');
    expect(history.lowDayFoods[0]?.tag).toBe('Dense');
    expect(history.lowDayFoods.find((f) => f.name === 'Protein smoothie')).toMatchObject({
      tag: 'Drinkable',
      eaten: 2,
      offered: 3,
    });
  });

  it('hides patterns without enough days and omits lowDayFoods when empty', () => {
    const history = buildAppetiteHistory({
      todayISO: '2026-09-15',
      targetKcal: 3000,
      levels: { '2026-09-14': 'LOW', '2026-09-13': 'HUNGRY' },
      consumedByDate: { '2026-09-14': 2000 },
      lastMealMinByDate: {},
      workoutDates: [],
      lowDayPrescriptions: [],
    });
    expect(history.patterns).toEqual([]);
    expect(history.lowDayFoods).toEqual([]);
    expect(history.percentEatenLowBefore).toBeNull();
  });
});
