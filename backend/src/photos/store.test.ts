import { describe, expect, it, vi } from 'vitest';

vi.hoisted(() => {
  process.env.JWT_SECRET ||= 'test-jwt-secret';
  process.env.CRON_SECRET ||= 'test-cron-secret';
});

import { createS3PhotoStore, photoKeyFor, signingAnchor, userPhotoPrefix } from './store.js';

describe('photo keys', () => {
  it('namespaces every photo under its user', () => {
    expect(photoKeyFor('u1', 'image/jpeg', 'abc')).toBe('meals/u1/abc.jpg');
    expect(photoKeyFor('u1', 'image/png', 'abc')).toBe('meals/u1/abc.png');
    expect(photoKeyFor('u1', 'image/jpeg').startsWith(userPhotoPrefix('u1'))).toBe(true);
  });

  it('anchors signing to the start of the UTC hour', () => {
    expect(signingAnchor(new Date('2026-09-10T12:47:31.250Z')).toISOString()).toBe('2026-09-10T12:00:00.000Z');
  });
});

describe('signed URLs', () => {
  const store = createS3PhotoStore({
    bucket: 'meal-photos',
    endpoint: 'https://account.r2.cloudflarestorage.com',
    region: 'auto',
    accessKeyId: 'test-access-key',
    secretAccessKey: 'test-secret-key',
  });
  const key = 'meals/u1/abc.jpg';

  it('are identical within an hour so the app can cache the image', async () => {
    const early = await store.signedUrl(key, new Date('2026-09-10T12:05:00Z'));
    const late = await store.signedUrl(key, new Date('2026-09-10T12:55:00Z'));
    const nextHour = await store.signedUrl(key, new Date('2026-09-10T13:01:00Z'));

    expect(early).toBe(late);
    expect(nextHour).not.toBe(early);
  });

  it('point at the private object with a two-hour expiry', async () => {
    const url = new URL(await store.signedUrl(key, new Date('2026-09-10T12:05:00Z')));
    expect(url.pathname).toBe('/meal-photos/meals/u1/abc.jpg');
    expect(url.searchParams.get('X-Amz-Expires')).toBe('7200');
    expect(url.searchParams.get('X-Amz-Date')).toBe('20260910T120000Z');
  });
});
