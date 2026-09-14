import { normalizeToken } from '../solver/exclusions.js';

const STOP = new Set([
  'i',
  'im',
  "i'm",
  'ill',
  "i'll",
  'never',
  'eat',
  'eats',
  'eating',
  'or',
  'and',
  'the',
  'a',
  'an',
  'no',
  'not',
  'dont',
  "don't",
  'please',
  'something',
  'else',
  'food',
  'foods',
  'any',
  'also',
  'cant',
  "can't",
  'cannot',
  'have',
  'has',
  'with',
  'without',
  'like',
  'likes',
  'hate',
  'hates',
  'allergic',
  'allergy',
  'to',
  'of',
  'my',
  'me',
]);

export type ParsedRestriction = {
  label: string;
  token: string;
  source: 'ALLERGY' | 'INTOLERANCE' | 'PREFERENCE' | 'RELIGIOUS' | 'MEDICAL';
};

/**
 * Turn free-text "something else" exclusions into solver tokens so every
 * entered exclusion reaches `isFoodExcluded`. Splits on commas, semicolons,
 * newlines, "and"/"or", and also keeps longer leftover phrases.
 */
export function parseRestrictionFreeText(raw: string | null | undefined): ParsedRestriction[] {
  if (!raw) return [];
  const chunks = raw
    .split(/[,;\n/]|(\band\b)|(\bor\b)/i)
    .map((s) => (s ?? '').trim())
    .filter((s) => s && !/^(and|or)$/i.test(s));

  const out: ParsedRestriction[] = [];
  const seen = new Set<string>();

  const add = (label: string) => {
    const token = normalizeToken(label);
    if (!token || seen.has(token) || STOP.has(token.replace(/_/g, ''))) return;
    seen.add(token);
    out.push({ label: label.trim(), token, source: 'PREFERENCE' });
  };

  for (const chunk of chunks) {
    add(chunk);
    for (const word of chunk.split(/\s+/)) {
      const cleaned = word.replace(/[^a-zA-Z0-9 -]/g, '').trim();
      if (cleaned.length < 4) continue;
      if (STOP.has(cleaned.toLowerCase())) continue;
      add(cleaned);
    }
  }

  return out;
}

export function mergeRestrictions(
  structured: { label: string; source?: string }[],
  freeText?: string | null,
): { label: string; source?: string }[] {
  return [...structured, ...parseRestrictionFreeText(freeText).map((r) => ({ label: r.label, source: r.source }))];
}
