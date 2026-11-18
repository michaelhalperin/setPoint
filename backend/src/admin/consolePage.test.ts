import { describe, expect, it } from 'vitest';
import { CONSOLE_PAGE_HTML } from './consolePage.js';

describe('the console page script', () => {
  it('parses as JavaScript', () => {
    const script = CONSOLE_PAGE_HTML.split('<script>')[1]!.split('</script>')[0]!;
    expect(() => new Function(script)).not.toThrow();
  });

  it('never writes markup from data', () => {
    expect(CONSOLE_PAGE_HTML).not.toContain('innerHTML');
  });
});
