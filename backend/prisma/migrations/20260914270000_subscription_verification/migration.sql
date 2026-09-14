-- AlterTable
ALTER TABLE "User" ADD COLUMN "subscriptionOriginalTransactionId" TEXT,
ADD COLUMN "subscriptionEnvironment" TEXT;

-- Statuses written before purchases were verified can't be trusted.
UPDATE "User" SET "subscriptionStatus" = NULL, "subscriptionExpiresAt" = NULL, "subscriptionProductId" = NULL;

-- CreateIndex
CREATE UNIQUE INDEX "User_subscriptionOriginalTransactionId_key" ON "User"("subscriptionOriginalTransactionId");
