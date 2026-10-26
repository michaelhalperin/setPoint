import { describe, expect, it } from 'vitest';

describe('the page script', () => {
  it('parses as JavaScript', async () => {
    const { OPS_PAGE_HTML } = await import('./opsPage.js');
    const script = OPS_PAGE_HTML.split('<script>')[1]!.split('</script>')[0]!;
    expect(() => new Function(script)).not.toThrow();
  });
});
