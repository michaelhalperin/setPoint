import { describe, expect, it } from 'vitest';
import { detectDistress } from './distress.js';

describe('detectDistress', () => {
  it('trips on eat-less with a calorie object', () => {
    expect(detectDistress('how do I eat less calories')?.code).toBe('restriction');
    expect(detectDistress('לאכול פחות קלוריות')?.code).toBe('restriction');
  });

  it('does not trip on eat less salt', () => {
    expect(detectDistress('eat less salt')).toBeNull();
    expect(detectDistress('לאכול פחות מלח')).toBeNull();
  });

  it('trips on ED and self-harm phrasing', () => {
    expect(detectDistress('I think I have an eating disorder')?.code).toBe('ed');
    expect(detectDistress('הפרעת אכילה')?.code).toBe('ed');
    expect(detectDistress('I want to kill myself')?.code).toBe('self_harm');
  });

  it('trips on misspellings and mixed Hebrew/English restriction', () => {
    expect(detectDistress('eat less cals')?.code).toBe('restriction');
    expect(detectDistress('how do I לאכול פחות calories')?.code).toBe('restriction');
    expect(detectDistress('I need to get skinny for the season')?.code).toBe('restriction');
  });

  it('lets ordinary food questions through', () => {
    expect(detectDistress('What’s left today?')).toBeNull();
    expect(detectDistress('I only have 10 minutes')).toBeNull();
    expect(detectDistress('משהו לשתות')).toBeNull();
  });
});
