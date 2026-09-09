import { CONFIDENCE_WEIGHTS, ENGINE_CONFIG, type EngineConfig } from './config.js';
import { clamp, type Mode } from './types.js';

export type BiosignalInput = {
  /** HRV z-score vs personal baseline. Negative = suppressed (under-fuelling signal). */
  hrvZ: number;
  /** RHR z-score vs personal baseline. Positive = elevated (under-fuelling signal). Null if unknown. */
  rhrZ: number | null;
};

export type ConfidenceInput = {
  mode: Mode;
  /** Hours since the user's last logged meal (>= 0). */
  hoursSinceMeal: number;
  /** The user's personal expected inter-meal gap, in hours (> 0). */
  expectedGapHours: number;
  /** Hours since the user last logged anything (>= 0). */
  hoursSinceLastLog: number;
  /** Fresh biosignal reading, or null in Basic mode / when no usable reading exists. */
  biosignal: BiosignalInput | null;
  config?: EngineConfig;
};

export type ConfidenceComponents = {
  /** 0..1, or null when biosignals did not contribute. */
  biosignalDeviation: number | null;
  /** hoursSinceMeal / expectedGap, clamped to the configured ceiling. */
  mealGapRatio: number;
  /** 0..1 measure of how long since anything was logged. */
  loggingSilence: number;
};

export type ConfidenceResult = {
  score: number;
  mode: Mode;
  /** Whether biosignal weights were actually used (Smart + fresh reading). */
  usedBiosignal: boolean;
  components: ConfidenceComponents;
  threshold: number;
  fires: boolean;
};

/**
 * Maps signed HRV/RHR z-scores to a 0..1 "under-fuelling" signal. Only HRV
 * suppression and RHR elevation count; the opposite directions are treated as
 * no signal (0), never as negative evidence.
 */
export function normalizeBiosignal(
  hrvZ: number,
  rhrZ: number | null,
  fullScale: number = ENGINE_CONFIG.biosignalZFullScale,
): number {
  const hrvSignal = Math.max(0, -hrvZ);
  if (rhrZ === null) return clamp(hrvSignal / fullScale, 0, 1);
  const rhrSignal = Math.max(0, rhrZ);
  return clamp((hrvSignal + rhrSignal) / 2 / fullScale, 0, 1);
}

/**
 * The deterministic confidence score (plan §2). Pure. Smart mode without a
 * usable biosignal reading transparently falls back to the Basic weights.
 */
export function computeConfidence(input: ConfidenceInput): ConfidenceResult {
  const config = input.config ?? ENGINE_CONFIG;

  const mealGapRatio =
    input.expectedGapHours > 0
      ? clamp(input.hoursSinceMeal / input.expectedGapHours, 0, config.mealGapRatioCeiling)
      : 0;

  const loggingSilence = clamp(input.hoursSinceLastLog / config.silenceHorizonHours, 0, 1);

  const usedBiosignal = input.mode === 'SMART' && input.biosignal !== null;

  let score: number;
  let biosignalDeviation: number | null = null;

  if (usedBiosignal && input.biosignal) {
    biosignalDeviation = normalizeBiosignal(
      input.biosignal.hrvZ,
      input.biosignal.rhrZ,
      config.biosignalZFullScale,
    );
    const w = CONFIDENCE_WEIGHTS.smart;
    score =
      w.biosignal * biosignalDeviation + w.mealGap * mealGapRatio + w.silence * loggingSilence;
  } else {
    const w = CONFIDENCE_WEIGHTS.basic;
    score = w.mealGap * mealGapRatio + w.silence * loggingSilence;
  }

  score = clamp(score, 0, 1);

  return {
    score,
    mode: input.mode,
    usedBiosignal,
    components: { biosignalDeviation, mealGapRatio, loggingSilence },
    threshold: config.confidenceThreshold,
    fires: score > config.confidenceThreshold,
  };
}
