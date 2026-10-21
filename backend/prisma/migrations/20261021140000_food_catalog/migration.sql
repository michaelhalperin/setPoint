-- AlterEnum
ALTER TYPE "MealSource" ADD VALUE 'CATALOG';

-- CreateTable
CREATE TABLE "CatalogFood" (
    "id" TEXT NOT NULL,
    "fdcId" INTEGER NOT NULL,
    "name" TEXT NOT NULL,
    "category" TEXT,
    "servingG" DOUBLE PRECISION,
    "servingDesc" TEXT,
    "kcal100g" DOUBLE PRECISION NOT NULL,
    "proteinG100g" DOUBLE PRECISION NOT NULL,
    "carbsG100g" DOUBLE PRECISION NOT NULL,
    "fatG100g" DOUBLE PRECISION NOT NULL,
    "dataType" TEXT NOT NULL,
    "source" "FoodSource" NOT NULL DEFAULT 'USDA',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "CatalogFood_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "CatalogFood_fdcId_key" ON "CatalogFood"("fdcId");

-- CreateIndex
CREATE INDEX "CatalogFood_name_idx" ON "CatalogFood"("name");
