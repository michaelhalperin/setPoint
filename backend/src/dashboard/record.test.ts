import { describe, expect, it } from 'vitest';
import { buildWeekRecord, type RecordInput } from './record.js';

const times = { breakfastMin: 480, lunchMin: 780, dinnerMin: 1140 };
// 2026-09-07 is a Monday.
const dates = ['2026-09-07', '2026-09-08', '2026-09-09', '2026-09-10', '2026-09-11', '2026-09-12', '2026-09-13'];

function input(over: Partial<RecordInput> = {}): RecordInput {
  return { dates, nowMin: 600, times, meals: [], checkIns: [], ...over };
}

describe('buildWeekRecord', () => {
  it('marks each meal on time, after a check-in, missed, or still open', () => {
    const record = buildWeekRecord(
      input({
        meals: [
          { date: '2026-09-07', minute: 485 },
          { date: '2026-09-07', minute: 850 }, // lunch, after its check-in
          { date: '2026-09-07', minute: 1150 },
          { date: '2026-09-13', minute: 490 },
        ],
        checkIns: [
          { date: '2026-09-07', minute: 826, status: 'LOGGED', tier: 1 },
          { date: '2026-09-08', minute: 1186, status: 'ESCALATED', tier: 2 },
        ],
      }),
    );

    expect(record.days[0]?.slots).toEqual(['on_time', 'after_check_in', 'on_time']);
    expect(record.days[1]?.slots).toEqual(['missed', 'missed', 'missed']);
    expect(record.days[6]?.slots).toEqual(['on_time', 'open', 'open']); // today at 10:00
    expect(record.afterCheckIn).toBe(1);
    expect(record.checkIns).toBe(2);
  });

  it('counts "I already ate" as eaten, not missed', () => {
    const record = buildWeekRecord(
      input({ checkIns: [{ date: '2026-09-09', minute: 830, status: 'EXPIRED', tier: 1 }] }),
    );
    expect(record.days[2]?.slots[1]).toBe('on_time');
  });

  it('spots a meal that runs late on workdays and suggests a new time', () => {
    const late = ['2026-09-07', '2026-09-08', '2026-09-10', '2026-09-11'].map((date, i) => ({ date, minute: 780 + [50, 70, 90, 60][i]! }));
    const record = buildWeekRecord(input({ meals: [...late, { date: '2026-09-09', minute: 785 }] }));
    expect(record.pattern).toEqual({ slot: 'lunch', lateDays: 4, ofDays: 5, currentMin: 780, suggestedMin: 840 });
  });

  it('does not count days before the plan started as missed', () => {
    const record = buildWeekRecord(input({ planStartDate: '2026-09-13', nowMin: 600 }));
    expect(record.days[0]?.slots).toEqual(['open', 'open', 'open']);
    expect(record.days[5]?.slots).toEqual(['open', 'open', 'open']);
    expect(record.days[6]?.slots).toEqual(['open', 'open', 'open']); // today, still morning
    expect(record.missed).toBe(0);
  });

  it('still marks a skipped meal missed once the plan has started', () => {
    const record = buildWeekRecord(input({ planStartDate: '2026-09-12', nowMin: 600 }));
    expect(record.days[5]?.slots).toEqual(['missed', 'missed', 'missed']); // yesterday on the plan
    expect(record.missed).toBe(3);
  });

  it('suggests nothing without a clear pattern', () => {
    const record = buildWeekRecord(
      input({ meals: [{ date: '2026-09-07', minute: 850 }, { date: '2026-09-08', minute: 790 }, { date: '2026-09-09', minute: 785 }] }),
    );
    expect(record.pattern).toBeNull();
  });
});
