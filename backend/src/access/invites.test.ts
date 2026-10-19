import { describe, expect, it } from 'vitest';
import { generateInviteCode, higherRole, inviteProblem, normalizeInviteCode } from './invites.js';

const now = new Date('2026-10-19T12:00:00Z');
const open = { disabledAt: null, expiresAt: null, maxUses: null, uses: 0 };

describe('invite codes', () => {
  it('generates codes without look-alike characters', () => {
    for (let i = 0; i < 200; i += 1) {
      const code = generateInviteCode();
      expect(code).toMatch(/^[A-Z2-9]{8}$/);
      expect(code).not.toMatch(/[01OIL]/);
    }
  });

  it('ignores case, spaces and dashes', () => {
    expect(normalizeInviteCode(' dvir 2026 ')).toBe('DVIR2026');
    expect(normalizeInviteCode('ab-cd-ef')).toBe('ABCDEF');
  });

  it('says why a code is unusable', () => {
    expect(inviteProblem(null, now)).toBe('unknown');
    expect(inviteProblem({ ...open, disabledAt: now }, now)).toBe('disabled');
    expect(inviteProblem({ ...open, expiresAt: new Date('2026-10-19T11:59:59Z') }, now)).toBe('expired');
    expect(inviteProblem({ ...open, maxUses: 3, uses: 3 }, now)).toBe('used_up');
    expect(inviteProblem({ ...open, maxUses: 3, uses: 2, expiresAt: new Date('2026-11-01T00:00:00Z') }, now)).toBeNull();
    expect(inviteProblem(open, now)).toBeNull();
  });

  it('raises a role but never lowers it', () => {
    expect(higherRole('USER', 'TRAINER')).toBe('TRAINER');
    expect(higherRole('ADMIN', 'USER')).toBe('ADMIN');
    expect(higherRole('TRAINER', 'TRAINER')).toBe('TRAINER');
  });
});
