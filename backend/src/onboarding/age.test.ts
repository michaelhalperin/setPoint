import { describe, expect, it } from 'vitest';
import { MIN_AGE_YEARS, UnderageError, assertMinimumAge } from './age.js';

describe('assertMinimumAge', () => {
  it('allows 16 and over', () => {
    expect(() => assertMinimumAge(MIN_AGE_YEARS)).not.toThrow();
    expect(() => assertMinimumAge(40)).not.toThrow();
  });

  it('rejects under 16', () => {
    expect(() => assertMinimumAge(15)).toThrow(UnderageError);
    expect(() => assertMinimumAge(13)).toThrow(UnderageError);
  });

  it('skips when age is unknown', () => {
    expect(() => assertMinimumAge(null)).not.toThrow();
    expect(() => assertMinimumAge(undefined)).not.toThrow();
  });
});
