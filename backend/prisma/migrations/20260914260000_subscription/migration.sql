-- AlterTable
ALTER TABLE "User" ADD COLUMN "subscriptionStatus" TEXT,
ADD COLUMN "subscriptionExpiresAt" TIMESTAMP(3),
ADD COLUMN "subscriptionProductId" TEXT;
