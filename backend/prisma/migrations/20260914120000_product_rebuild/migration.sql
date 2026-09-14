-- Baseline: the complete SetPoint schema.
--
-- The database was built with `prisma db push` before migrations existed.
-- Production was baselined by marking this migration applied
-- (`prisma migrate resolve --applied 20260914120000_product_rebuild`), so it
-- only ever runs on a fresh database (CI, staging, local). Every schema change
-- after this one is a new migration folder.

-- CreateSchema
CREATE SCHEMA IF NOT EXISTS "public";

-- CreateEnum
CREATE TYPE "Goal" AS ENUM ('BULK', 'DIET', 'MAINTAIN');

-- CreateEnum
CREATE TYPE "AppMode" AS ENUM ('BASIC', 'SMART');

-- CreateEnum
CREATE TYPE "Sex" AS ENUM ('MALE', 'FEMALE', 'UNSPECIFIED');

-- CreateEnum
CREATE TYPE "ActivityLevel" AS ENUM ('SEDENTARY', 'LIGHT', 'MODERATE', 'ACTIVE', 'VERY_ACTIVE');

-- CreateEnum
CREATE TYPE "RestrictionSource" AS ENUM ('ALLERGY', 'INTOLERANCE', 'PREFERENCE', 'RELIGIOUS', 'MEDICAL');

-- CreateEnum
CREATE TYPE "EnforcementDisabledReason" AS ENUM ('MEDICAL_SUPERVISION', 'EATING_DISORDER_SCREEN');

-- CreateEnum
CREATE TYPE "CheckInStatus" AS ENUM ('PENDING', 'LOGGED', 'DEFERRED', 'ESCALATED', 'EXPIRED', 'BACKED_OFF');

-- CreateEnum
CREATE TYPE "MealSource" AS ENUM ('TEXT', 'PHOTO', 'PRESCRIPTION', 'MANUAL');

-- CreateEnum
CREATE TYPE "PrescriptionStatus" AS ENUM ('OFFERED', 'ACCEPTED', 'DEFERRED', 'SUPERSEDED');

-- CreateEnum
CREATE TYPE "FoodSource" AS ENUM ('CURATED', 'USDA', 'OPEN_FOOD_FACTS');

-- CreateEnum
CREATE TYPE "DayOutcomeKind" AS ENUM ('ON_TRACK', 'UNDER', 'OVER', 'MISSED');

-- CreateEnum
CREATE TYPE "EscalationOutcome" AS ENUM ('NONE', 'ADJUST_PLAN', 'DELAY_CHECKINS', 'EASE_TARGET', 'PAUSE_CHECKINS', 'SUGGEST_PROFESSIONAL', 'RESUMED');

-- CreateEnum
CREATE TYPE "DeliveryStatus" AS ENUM ('CREATED', 'SENT', 'DELIVERED_UNKNOWN', 'FAILED', 'OPENED', 'ANSWERED');

-- CreateEnum
CREATE TYPE "TargetReviewStatus" AS ENUM ('PENDING', 'ACCEPTED', 'REJECTED', 'UNDONE');

-- CreateTable
CREATE TABLE "User" (
    "id" TEXT NOT NULL,
    "appleSub" TEXT,
    "email" TEXT,
    "timezone" TEXT NOT NULL DEFAULT 'UTC',
    "appleRefreshToken" TEXT,
    "wearableModifierEnabled" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PushToken" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "token" TEXT NOT NULL,
    "platform" TEXT NOT NULL DEFAULT 'ios',
    "environment" TEXT NOT NULL DEFAULT 'production',
    "kind" TEXT NOT NULL DEFAULT 'alert',
    "lastSeenAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PushToken_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "OnboardingProfile" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "goal" "Goal" NOT NULL,
    "mode" "AppMode" NOT NULL DEFAULT 'BASIC',
    "sex" "Sex" NOT NULL DEFAULT 'UNSPECIFIED',
    "birthDate" DATE,
    "heightCm" DOUBLE PRECISION,
    "weightKg" DOUBLE PRECISION,
    "activityLevel" "ActivityLevel" NOT NULL DEFAULT 'MODERATE',
    "startWeightKg" DOUBLE PRECISION,
    "targetWeightKg" DOUBLE PRECISION,
    "paceKgPerWeek" DOUBLE PRECISION NOT NULL DEFAULT 0.25,
    "preferredDurationWeeks" INTEGER,
    "goalStartedAt" TIMESTAMP(3),
    "dailyKcalTarget" INTEGER NOT NULL,
    "dailyProteinTargetG" INTEGER,
    "breakfastMin" INTEGER NOT NULL DEFAULT 480,
    "lunchMin" INTEGER NOT NULL DEFAULT 780,
    "dinnerMin" INTEGER NOT NULL DEFAULT 1140,
    "quietHoursStartMin" INTEGER NOT NULL DEFAULT 1380,
    "quietHoursEndMin" INTEGER NOT NULL DEFAULT 420,
    "pantryTokens" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "dislikedFoods" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "prepTimeMaxMin" INTEGER,
    "completedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "OnboardingProfile_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SafetyScreening" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "medicalSupervisionRequired" BOOLEAN NOT NULL DEFAULT false,
    "medicalConditionAffectsEating" BOOLEAN NOT NULL DEFAULT false,
    "scoffMakeSelfSick" BOOLEAN,
    "scoffLostControl" BOOLEAN,
    "scoffLostOneStone" BOOLEAN,
    "scoffBelievesFat" BOOLEAN,
    "scoffFoodDominates" BOOLEAN,
    "scoffScore" INTEGER,
    "scoffFlagged" BOOLEAN NOT NULL DEFAULT false,
    "restrictionsFreeText" TEXT,
    "enforcementEnabled" BOOLEAN NOT NULL DEFAULT true,
    "enforcementDisabledReason" "EnforcementDisabledReason",
    "screenedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "SafetyScreening_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "DietaryRestriction" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "label" TEXT NOT NULL,
    "token" TEXT NOT NULL,
    "source" "RestrictionSource" NOT NULL DEFAULT 'ALLERGY',
    "isHardExclusion" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "DietaryRestriction_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "WeightEntry" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "weightKg" DOUBLE PRECISION NOT NULL,
    "measuredAt" TIMESTAMP(3) NOT NULL,
    "source" TEXT NOT NULL DEFAULT 'manual',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "WeightEntry_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Meal" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "loggedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "source" "MealSource" NOT NULL,
    "rawInput" TEXT,
    "photoUrl" TEXT,
    "photoKey" TEXT,
    "parsedByAI" BOOLEAN NOT NULL DEFAULT false,
    "parseConfidence" DOUBLE PRECISION,
    "notes" TEXT,
    "items" JSONB,
    "parseQuality" TEXT,
    "kcal" INTEGER NOT NULL,
    "proteinG" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "carbsG" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "fatG" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "prescriptionId" TEXT,
    "checkInId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Meal_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "BiosignalState" (
    "userId" TEXT NOT NULL,
    "hrvDeviation" DOUBLE PRECISION NOT NULL,
    "rhrDeviation" DOUBLE PRECISION,
    "source" TEXT NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "BiosignalState_pkey" PRIMARY KEY ("userId")
);

-- CreateTable
CREATE TABLE "BiosignalReading" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "capturedAt" TIMESTAMP(3) NOT NULL,
    "hrvDeviation" DOUBLE PRECISION NOT NULL,
    "rhrDeviation" DOUBLE PRECISION,
    "source" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "BiosignalReading_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ConfidenceScore" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "computedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "mode" "AppMode" NOT NULL,
    "score" DOUBLE PRECISION NOT NULL,
    "scoringVersion" TEXT NOT NULL DEFAULT 'behavior.v1',
    "behaviorScore" DOUBLE PRECISION,
    "wearableModifier" DOUBLE PRECISION,
    "wearableUsed" BOOLEAN NOT NULL DEFAULT false,
    "biosignalDeviation" DOUBLE PRECISION,
    "hoursSinceMeal" DOUBLE PRECISION,
    "expectedGapHours" DOUBLE PRECISION,
    "loggingSilence" DOUBLE PRECISION,
    "overdueMin" DOUBLE PRECISION,
    "loggingReliability" DOUBLE PRECISION,
    "deferRate" DOUBLE PRECISION,
    "dismissRate" DOUBLE PRECISION,
    "targetCoverage" DOUBLE PRECISION,
    "components" JSONB,
    "threshold" DOUBLE PRECISION NOT NULL DEFAULT 0.45,
    "firedCheckIn" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "ConfidenceScore_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CheckIn" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "confidenceScoreId" TEXT,
    "tier" INTEGER NOT NULL DEFAULT 1,
    "status" "CheckInStatus" NOT NULL DEFAULT 'PENDING',
    "deliveryStatus" "DeliveryStatus" NOT NULL DEFAULT 'CREATED',
    "message" TEXT,
    "slot" TEXT,
    "episodeKey" TEXT,
    "deliveredAt" TIMESTAMP(3),
    "lastPushError" TEXT,
    "liveActivityId" TEXT,
    "deferUntil" TIMESTAMP(3),
    "deferCount" INTEGER NOT NULL DEFAULT 0,
    "resolvedAt" TIMESTAMP(3),
    "feedbackPositive" BOOLEAN,
    "feedbackAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "CheckIn_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "EscalationState" (
    "userId" TEXT NOT NULL,
    "consecutiveMisses" INTEGER NOT NULL DEFAULT 0,
    "currentTier" INTEGER NOT NULL DEFAULT 1,
    "lastCheckInAt" TIMESTAMP(3),
    "backedOffUntil" TIMESTAMP(3),
    "checkInsPaused" BOOLEAN NOT NULL DEFAULT false,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "EscalationState_pkey" PRIMARY KEY ("userId")
);

-- CreateTable
CREATE TABLE "EscalationConversation" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "checkInId" TEXT,
    "transcript" JSONB NOT NULL DEFAULT '[]',
    "outcome" "EscalationOutcome" NOT NULL DEFAULT 'NONE',
    "pendingProposal" JSONB,
    "appliedProposal" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "resolvedAt" TIMESTAMP(3),

    CONSTRAINT "EscalationConversation_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Prescription" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "checkInId" TEXT,
    "targetKcal" INTEGER NOT NULL,
    "targetProteinG" DOUBLE PRECISION,
    "totalKcal" INTEGER NOT NULL,
    "totalProteinG" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "totalCarbsG" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "totalFatG" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "status" "PrescriptionStatus" NOT NULL DEFAULT 'OFFERED',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Prescription_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PrescriptionItem" (
    "id" TEXT NOT NULL,
    "prescriptionId" TEXT NOT NULL,
    "foodItemId" TEXT,
    "name" TEXT NOT NULL,
    "quantity" DOUBLE PRECISION NOT NULL,
    "unit" TEXT NOT NULL,
    "kcal" INTEGER NOT NULL,
    "proteinG" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "carbsG" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "fatG" DOUBLE PRECISION NOT NULL DEFAULT 0,

    CONSTRAINT "PrescriptionItem_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "FoodItem" (
    "id" TEXT NOT NULL,
    "slug" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "servingDesc" TEXT NOT NULL,
    "servingGrams" DOUBLE PRECISION,
    "kcal" INTEGER NOT NULL,
    "proteinG" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "carbsG" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "fatG" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "tags" TEXT[],
    "allergens" TEXT[],
    "isStaple" BOOLEAN NOT NULL DEFAULT true,
    "source" "FoodSource" NOT NULL DEFAULT 'CURATED',
    "externalId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "FoodItem_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "DayOutcome" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "date" DATE NOT NULL,
    "kind" "DayOutcomeKind" NOT NULL,
    "kcalConsumed" INTEGER NOT NULL,
    "kcalTarget" INTEGER NOT NULL,
    "summaryLine" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "DayOutcome_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AiUsage" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AiUsage_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "WeightTargetReview" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "status" "TargetReviewStatus" NOT NULL DEFAULT 'PENDING',
    "formulaVersion" TEXT NOT NULL DEFAULT 'adapt.v1',
    "previousKcal" INTEGER NOT NULL,
    "proposedKcal" INTEGER NOT NULL,
    "reason" TEXT NOT NULL,
    "windowStart" TIMESTAMP(3) NOT NULL,
    "windowEnd" TIMESTAMP(3) NOT NULL,
    "weighInCount" INTEGER NOT NULL,
    "trendKgPerWeek" DOUBLE PRECISION NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "decidedAt" TIMESTAMP(3),

    CONSTRAINT "WeightTargetReview_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SchedulerHeartbeat" (
    "job" TEXT NOT NULL,
    "lastRunAt" TIMESTAMP(3) NOT NULL,
    "lastOk" BOOLEAN NOT NULL,
    "durationMs" INTEGER,
    "summary" JSONB,

    CONSTRAINT "SchedulerHeartbeat_pkey" PRIMARY KEY ("job")
);

-- CreateIndex
CREATE UNIQUE INDEX "User_appleSub_key" ON "User"("appleSub");

-- CreateIndex
CREATE UNIQUE INDEX "User_email_key" ON "User"("email");

-- CreateIndex
CREATE UNIQUE INDEX "PushToken_token_key" ON "PushToken"("token");

-- CreateIndex
CREATE INDEX "PushToken_userId_idx" ON "PushToken"("userId");

-- CreateIndex
CREATE INDEX "PushToken_userId_kind_idx" ON "PushToken"("userId", "kind");

-- CreateIndex
CREATE UNIQUE INDEX "OnboardingProfile_userId_key" ON "OnboardingProfile"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "SafetyScreening_userId_key" ON "SafetyScreening"("userId");

-- CreateIndex
CREATE INDEX "DietaryRestriction_userId_idx" ON "DietaryRestriction"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "DietaryRestriction_userId_token_key" ON "DietaryRestriction"("userId", "token");

-- CreateIndex
CREATE INDEX "WeightEntry_userId_measuredAt_idx" ON "WeightEntry"("userId", "measuredAt");

-- CreateIndex
CREATE UNIQUE INDEX "WeightEntry_userId_measuredAt_key" ON "WeightEntry"("userId", "measuredAt");

-- CreateIndex
CREATE INDEX "Meal_userId_loggedAt_idx" ON "Meal"("userId", "loggedAt");

-- CreateIndex
CREATE INDEX "BiosignalReading_userId_capturedAt_idx" ON "BiosignalReading"("userId", "capturedAt");

-- CreateIndex
CREATE INDEX "ConfidenceScore_userId_computedAt_idx" ON "ConfidenceScore"("userId", "computedAt");

-- CreateIndex
CREATE UNIQUE INDEX "CheckIn_confidenceScoreId_key" ON "CheckIn"("confidenceScoreId");

-- CreateIndex
CREATE INDEX "CheckIn_userId_status_idx" ON "CheckIn"("userId", "status");

-- CreateIndex
CREATE INDEX "CheckIn_status_deferUntil_idx" ON "CheckIn"("status", "deferUntil");

-- CreateIndex
CREATE INDEX "CheckIn_deliveryStatus_status_idx" ON "CheckIn"("deliveryStatus", "status");

-- CreateIndex
CREATE UNIQUE INDEX "CheckIn_userId_episodeKey_key" ON "CheckIn"("userId", "episodeKey");

-- CreateIndex
CREATE UNIQUE INDEX "EscalationConversation_checkInId_key" ON "EscalationConversation"("checkInId");

-- CreateIndex
CREATE INDEX "EscalationConversation_userId_idx" ON "EscalationConversation"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "Prescription_checkInId_key" ON "Prescription"("checkInId");

-- CreateIndex
CREATE INDEX "Prescription_userId_createdAt_idx" ON "Prescription"("userId", "createdAt");

-- CreateIndex
CREATE INDEX "PrescriptionItem_prescriptionId_idx" ON "PrescriptionItem"("prescriptionId");

-- CreateIndex
CREATE UNIQUE INDEX "FoodItem_slug_key" ON "FoodItem"("slug");

-- CreateIndex
CREATE INDEX "DayOutcome_userId_date_idx" ON "DayOutcome"("userId", "date");

-- CreateIndex
CREATE UNIQUE INDEX "DayOutcome_userId_date_key" ON "DayOutcome"("userId", "date");

-- CreateIndex
CREATE INDEX "AiUsage_userId_kind_createdAt_idx" ON "AiUsage"("userId", "kind", "createdAt");

-- CreateIndex
CREATE INDEX "AiUsage_createdAt_idx" ON "AiUsage"("createdAt");

-- CreateIndex
CREATE INDEX "WeightTargetReview_userId_status_createdAt_idx" ON "WeightTargetReview"("userId", "status", "createdAt");

-- AddForeignKey
ALTER TABLE "PushToken" ADD CONSTRAINT "PushToken_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "OnboardingProfile" ADD CONSTRAINT "OnboardingProfile_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SafetyScreening" ADD CONSTRAINT "SafetyScreening_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DietaryRestriction" ADD CONSTRAINT "DietaryRestriction_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "WeightEntry" ADD CONSTRAINT "WeightEntry_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Meal" ADD CONSTRAINT "Meal_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Meal" ADD CONSTRAINT "Meal_prescriptionId_fkey" FOREIGN KEY ("prescriptionId") REFERENCES "Prescription"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Meal" ADD CONSTRAINT "Meal_checkInId_fkey" FOREIGN KEY ("checkInId") REFERENCES "CheckIn"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "BiosignalState" ADD CONSTRAINT "BiosignalState_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "BiosignalReading" ADD CONSTRAINT "BiosignalReading_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ConfidenceScore" ADD CONSTRAINT "ConfidenceScore_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CheckIn" ADD CONSTRAINT "CheckIn_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CheckIn" ADD CONSTRAINT "CheckIn_confidenceScoreId_fkey" FOREIGN KEY ("confidenceScoreId") REFERENCES "ConfidenceScore"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "EscalationState" ADD CONSTRAINT "EscalationState_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "EscalationConversation" ADD CONSTRAINT "EscalationConversation_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "EscalationConversation" ADD CONSTRAINT "EscalationConversation_checkInId_fkey" FOREIGN KEY ("checkInId") REFERENCES "CheckIn"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Prescription" ADD CONSTRAINT "Prescription_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Prescription" ADD CONSTRAINT "Prescription_checkInId_fkey" FOREIGN KEY ("checkInId") REFERENCES "CheckIn"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PrescriptionItem" ADD CONSTRAINT "PrescriptionItem_prescriptionId_fkey" FOREIGN KEY ("prescriptionId") REFERENCES "Prescription"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PrescriptionItem" ADD CONSTRAINT "PrescriptionItem_foodItemId_fkey" FOREIGN KEY ("foodItemId") REFERENCES "FoodItem"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DayOutcome" ADD CONSTRAINT "DayOutcome_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AiUsage" ADD CONSTRAINT "AiUsage_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "WeightTargetReview" ADD CONSTRAINT "WeightTargetReview_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

