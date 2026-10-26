-- CreateEnum
CREATE TYPE "WorkoutOutcome" AS ENUM ('DONE', 'SKIPPED');

-- AlterTable: a planned session the person confirmed (null = not answered yet)
ALTER TABLE "Workout" ADD COLUMN "outcome" "WorkoutOutcome";

-- AlterTable: minutes after a usual meal time, with nothing logged, before a check-in
ALTER TABLE "OnboardingProfile" ADD COLUMN "checkInGraceMin" INTEGER NOT NULL DEFAULT 45;
