-- AlterEnum
-- This migration adds more than one value to an enum.
-- With PostgreSQL versions 11 and earlier, this is not possible
-- in a single migration. This can be worked around by creating
-- multiple migrations, each migration adding only one value to
-- the enum.


ALTER TYPE "MealSource" ADD VALUE 'SAVED';
ALTER TYPE "MealSource" ADD VALUE 'BARCODE';

-- CreateTable
CREATE TABLE "SavedMeal" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "items" JSONB NOT NULL,
    "kcal" INTEGER NOT NULL,
    "proteinG" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "carbsG" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "fatG" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "suggestSlot" TEXT,
    "useInCheckIns" BOOLEAN NOT NULL DEFAULT false,
    "lastUsedAt" TIMESTAMP(3),
    "useCount" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "SavedMeal_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "BarcodeFood" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "brand" TEXT,
    "servingG" DOUBLE PRECISION,
    "kcal100g" DOUBLE PRECISION NOT NULL,
    "proteinG100g" DOUBLE PRECISION NOT NULL,
    "carbsG100g" DOUBLE PRECISION NOT NULL,
    "fatG100g" DOUBLE PRECISION NOT NULL,
    "fetchedAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "BarcodeFood_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "SavedMeal_userId_lastUsedAt_idx" ON "SavedMeal"("userId", "lastUsedAt");

-- CreateIndex
CREATE INDEX "SavedMeal_userId_suggestSlot_idx" ON "SavedMeal"("userId", "suggestSlot");

-- CreateIndex
CREATE UNIQUE INDEX "BarcodeFood_code_key" ON "BarcodeFood"("code");

-- AddForeignKey
ALTER TABLE "SavedMeal" ADD CONSTRAINT "SavedMeal_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
