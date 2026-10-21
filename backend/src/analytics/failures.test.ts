import { describe, expect, it } from 'vitest';
import { ZodError, z } from 'zod';
import { AiQuotaExceededError } from '../ai/quota.js';
import { EmptyMealError, MealParsingUnavailableError } from '../meals/logMeal.js';
import { failReason, mealSourceFromBody, routeCode } from './failures.js';

describe('routeCode', () => {
  it('turns a Fastify route into a short analytics code', () => {
    expect(routeCode('/api/meals')).toBe('api.meals');
    expect(routeCode('/api/checkins/:id/defer')).toBe('api.checkins.id.defer');
    expect(routeCode(undefined)).toBe('unmatched');
  });
});

describe('mealSourceFromBody', () => {
  it('reads the log kind from which field was sent', () => {
    expect(mealSourceFromBody({ image: { data: 'x' } })).toBe('PHOTO');
    expect(mealSourceFromBody({ savedMealId: 's1' })).toBe('SAVED');
    expect(mealSourceFromBody({ barcode: '123' })).toBe('BARCODE');
    expect(mealSourceFromBody({ catalogId: 'c1' })).toBe('CATALOG');
    expect(mealSourceFromBody({ prescriptionId: 'p1' })).toBe('PRESCRIPTION');
    expect(mealSourceFromBody({ macros: { kcal: 400 } })).toBe('MANUAL');
    expect(mealSourceFromBody({ text: 'oats' })).toBe('TEXT');
    expect(mealSourceFromBody(null)).toBe('UNKNOWN');
  });
});

describe('failReason', () => {
  it('maps known errors and HTTP status to short codes', () => {
    expect(failReason(new EmptyMealError('empty'))).toBe('empty');
    expect(failReason(new MealParsingUnavailableError('off'))).toBe('parse');
    expect(failReason(new AiQuotaExceededError('meal_parse', 30))).toBe('quota');
    expect(failReason(new ZodError(z.object({ a: z.string() }).safeParse({}).error!.issues))).toBe('invalid');
    expect(failReason(new Error('x'), 500)).toBe('server');
    expect(failReason(new Error('x'), 400)).toBe('bad_request');
    expect(failReason(new Error('x'), 404)).toBe('not_found');
  });
});
