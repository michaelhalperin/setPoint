-- AlterTable
ALTER TABLE "OnboardingProfile" ADD COLUMN "writeHealthEnergy" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN "writeHealthProtein" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN "writeHealthCarbs" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN "writeHealthFat" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN "writeHealthBodyMass" BOOLEAN NOT NULL DEFAULT false;
