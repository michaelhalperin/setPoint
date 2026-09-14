-- AlterTable
ALTER TABLE "OnboardingProfile" ADD COLUMN "trainingAddCalories" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN "preWorkoutNudgeMin" INTEGER DEFAULT 90;

-- AlterTable
ALTER TABLE "CheckIn" ADD COLUMN "workoutId" TEXT,
ADD COLUMN "coveredByDinner" BOOLEAN NOT NULL DEFAULT false;

-- CreateEnum
CREATE TYPE "WorkoutSource" AS ENUM ('HEALTHKIT', 'PLANNED');

-- CreateEnum
CREATE TYPE "WorkoutKind" AS ENUM ('STRENGTH', 'CARDIO', 'MIXED');

-- CreateTable
CREATE TABLE "Workout" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "source" "WorkoutSource" NOT NULL,
    "kind" "WorkoutKind" NOT NULL,
    "start" TIMESTAMP(3) NOT NULL,
    "durationMin" INTEGER NOT NULL,
    "activeKcal" INTEGER,
    "clientId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Workout_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "Workout_userId_clientId_key" ON "Workout"("userId", "clientId");

-- CreateIndex
CREATE INDEX "Workout_userId_start_idx" ON "Workout"("userId", "start");

-- AddForeignKey
ALTER TABLE "Workout" ADD CONSTRAINT "Workout_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
