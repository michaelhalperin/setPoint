-- AlterTable
ALTER TABLE "Meal" ADD COLUMN     "clientId" TEXT;

-- CreateIndex
CREATE UNIQUE INDEX "Meal_userId_clientId_key" ON "Meal"("userId", "clientId");

