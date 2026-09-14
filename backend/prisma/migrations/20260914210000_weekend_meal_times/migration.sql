-- AlterTable
ALTER TABLE "OnboardingProfile" ADD COLUMN "weekendBreakfastMin" INTEGER,
ADD COLUMN "weekendLunchMin" INTEGER,
ADD COLUMN "weekendDinnerMin" INTEGER,
ADD COLUMN "weekendDays" INTEGER NOT NULL DEFAULT 65;
