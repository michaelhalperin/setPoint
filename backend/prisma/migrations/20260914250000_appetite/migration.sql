-- AlterTable
ALTER TABLE "OnboardingProfile" ADD COLUMN "appetiteMode" TEXT NOT NULL DEFAULT 'NORMAL',
ADD COLUMN "drinkableOk" BOOLEAN NOT NULL DEFAULT true;

-- AlterTable
ALTER TABLE "CheckIn" ADD COLUMN "variant" TEXT NOT NULL DEFAULT 'full';

-- CreateTable
CREATE TABLE "DayAppetite" (
    "userId" TEXT NOT NULL,
    "localDate" TEXT NOT NULL,
    "level" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "DayAppetite_pkey" PRIMARY KEY ("userId","localDate")
);

-- AddForeignKey
ALTER TABLE "DayAppetite" ADD CONSTRAINT "DayAppetite_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
