-- CreateTable
CREATE TABLE "PendingPhotoDeletion" (
    "id" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "target" TEXT NOT NULL,
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "lastError" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastTriedAt" TIMESTAMP(3),

    CONSTRAINT "PendingPhotoDeletion_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "PendingPhotoDeletion_attempts_createdAt_idx" ON "PendingPhotoDeletion"("attempts", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "PendingPhotoDeletion_kind_target_key" ON "PendingPhotoDeletion"("kind", "target");

