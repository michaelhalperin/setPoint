import type { FeatureFlag, PrismaClient, UserRole } from '@prisma/client';
import { env } from '../env.js';

/**
 * Feature flags. Every flag is declared here with its default, so a flag with no
 * row in the database behaves as it always has; a row overrides it — on for
 * everyone, or only for some cohorts, roles or users. The app gets the result
 * for its user from GET /api/flags.
 */
export const FLAGS = {
  order_nearby: { default: true, description: 'Order nearby: dishes near you with Wolt links.' },
  app_language: { default: false, description: 'In-app language picker (English / Hebrew) on Settings.' },
  nutrition_chat: {
    default: false,
    description: 'Nutrition assistant (ember). Off until a cohort whitelist.',
  },
} as const satisfies Record<string, { default: boolean; description: string }>;

export type FlagKey = keyof typeof FLAGS;

export const isFlagKey = (key: string): key is FlagKey => Object.prototype.hasOwnProperty.call(FLAGS, key);

export type FlagUser = { id: string; role: UserRole; cohort: string | null };
type FlagRow = Pick<FeatureFlag, 'key' | 'enabled' | 'cohorts' | 'roles' | 'userIds'>;

/** Whether one flag is on for this user. */
export function flagOn(key: FlagKey, user: FlagUser, row: FlagRow | undefined): boolean {
  if (!row) return FLAGS[key].default;
  if (row.enabled) return true;
  return (
    row.userIds.includes(user.id) ||
    row.roles.includes(user.role) ||
    (user.cohort !== null && row.cohorts.includes(user.cohort))
  );
}

/** Every declared flag, resolved for this user. */
export function resolveFlags(user: FlagUser, rows: FlagRow[]): Record<FlagKey, boolean> {
  const byKey = new Map(rows.map((r) => [r.key, r]));
  return Object.fromEntries(
    (Object.keys(FLAGS) as FlagKey[]).map((key) => [key, flagOn(key, user, byKey.get(key))]),
  ) as Record<FlagKey, boolean>;
}

export async function flagsForUser(prisma: PrismaClient, userId: string): Promise<Record<FlagKey, boolean>> {
  const [user, rows] = await Promise.all([
    prisma.user.findUnique({ where: { id: userId }, select: { id: true, role: true, cohort: true } }),
    prisma.featureFlag.findMany(),
  ]);
  const flags = resolveFlags(user ?? { id: userId, role: 'USER', cohort: null }, rows);
  // Env is the second kill switch. Tiles hide on the next /api/flags without a redeploy
  // of the flag row — but env off still wins even if the row is enabled.
  if (env.EXPERT_NUTRITION_ENABLED !== 'true') flags.nutrition_chat = false;
  return flags;
}

export async function isFlagOnForUser(prisma: PrismaClient, userId: string, key: FlagKey): Promise<boolean> {
  return (await flagsForUser(prisma, userId))[key];
}
