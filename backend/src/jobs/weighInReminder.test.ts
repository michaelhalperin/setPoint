import { describe, expect, it } from 'vitest';
import { inReminderWindow, weighInCopy } from './weighInReminder.js';

describe('weigh-in reminder', () => {
  it('sends only between 10:00 and 12:00 local time', () => {
    expect(inReminderWindow(new Date('2026-11-16T08:30:00Z'), 'UTC')).toBe(false);
    expect(inReminderWindow(new Date('2026-11-16T10:30:00Z'), 'UTC')).toBe(true);
    expect(inReminderWindow(new Date('2026-11-16T12:00:00Z'), 'UTC')).toBe(false);
    // 08:30 UTC is 10:30 in Jerusalem (UTC+2 in November).
    expect(inReminderWindow(new Date('2026-11-16T08:30:00Z'), 'Asia/Jerusalem')).toBe(true);
  });

  it('has its own wording in both languages', () => {
    expect(weighInCopy('en').title).toBe('Weigh-in time');
    expect(weighInCopy('he').title).toBe('הגיע הזמן להישקל');
  });
});

import { buildCheckInAlertPayload } from '../push/apns.js';

describe('weigh-in alert payload', () => {
  it('opens the weigh-in and carries no check-in', () => {
    const payload = buildCheckInAlertPayload({ userId: 'u', checkInId: '', tier: 1, title: 'T', body: 'B', weighIn: true });
    expect(payload.deepLink).toBe('setpoint://weigh-in');
    expect(payload).not.toHaveProperty('checkInId');
    expect((payload.aps as { category?: string }).category).toBeUndefined();
  });
});
