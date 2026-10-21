-- Weekly repeating sessions share a series id, so one edit or delete can cover
-- "this and all after". Nullable: one-off and Apple Health workouts have none.
ALTER TABLE "Workout" ADD COLUMN "seriesId" TEXT;

-- CreateIndex
CREATE INDEX "Workout_userId_seriesId_idx" ON "Workout"("userId", "seriesId");
