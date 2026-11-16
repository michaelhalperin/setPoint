import { describe, expect, it } from 'vitest';
import { normalizeTraining } from './parseTraining.js';

describe('normalizeTraining', () => {
  it('maps weekday names to calendar weekdays and clamps the length', () => {
    const r = normalizeTraining({
      sessions: [{ title: 'Legs', kind: 'STRENGTH', durationMin: 999, weekdays: ['Mon', 'thu', 'mon'], startTime: '18:30' }],
      note: ' guessed the time ',
    });
    expect(r.sessions).toEqual([{ title: 'Legs', kind: 'STRENGTH', durationMin: 360, weekdays: [2, 5], startMinute: 18 * 60 + 30 }]);
    expect(r.note).toBe('guessed the time');
  });

  it('drops sessions with no readable day and falls back on a bad time', () => {
    const r = normalizeTraining({
      sessions: [
        { title: 'Run', kind: 'CARDIO', durationMin: 40, weekdays: ['sat'], startTime: 'morning' },
        { title: 'Nothing', kind: 'CARDIO', durationMin: 40, weekdays: ['someday'], startTime: '07:00' },
      ],
    });
    expect(r.sessions).toHaveLength(1);
    expect(r.sessions[0]).toMatchObject({ weekdays: [7], startMinute: 18 * 60 });
    expect(r.note).toBeNull();
  });
});
