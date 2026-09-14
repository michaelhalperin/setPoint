-- AlterTable
ALTER TABLE "ConfidenceScore" ADD COLUMN     "episodeKey" TEXT,
ALTER COLUMN "scoringVersion" SET DEFAULT 'behavior.v2',
ALTER COLUMN "threshold" SET DEFAULT 0.5;

-- CreateIndex
CREATE UNIQUE INDEX "ConfidenceScore_userId_episodeKey_key" ON "ConfidenceScore"("userId", "episodeKey");

