export const EXPERT_KIND = 'NUTRITION' as const;
export type ExpertLang = 'en' | 'he';

export const TODAY_CHIP_MIN_KCAL = 300;

export const TRANSCRIPT_MODEL_TURNS = 12;
export const PROPOSAL_TTL_MS = 2 * 60 * 60 * 1000;
export const LOCK_TTL_MS = 48 * 60 * 60 * 1000;
export const TRIPS_LOCK_24H = 2;
export const TRIPS_LOCK_7D = 3;

export type TranscriptTurn = { role: 'user' | 'assistant'; content: string; at: string };

export type ExpertChip = { id: string; title: string; message: string };

export type PlateArgs = {
  kind: 'suggest_plate';
  localDate: string;
  timezone: string;
  targetKcal: number;
  requireNoCook: boolean;
  requireDrinkable: boolean;
  summary: string;
  items: {
    slug: string;
    name: string;
    servingDesc: string;
    quantity: number;
    kcal: number;
    proteinG: number;
    carbsG: number;
    fatG: number;
  }[];
  totals: { kcal: number; proteinG: number; carbsG: number; fatG: number };
};

export type ProposalCard = {
  id: string;
  kind: 'suggest_plate';
  title: string;
  summary: string;
  localDate: string;
  timezone: string;
  expiresAt: string;
  items: PlateArgs['items'];
  totals: PlateArgs['totals'];
};
