-- AlterTable
ALTER TABLE "OnboardingProfile" ADD COLUMN "calendarCountFree" BOOLEAN NOT NULL DEFAULT false;

-- CreateTable
CREATE TABLE "CalendarKeep" (
    "userId" TEXT NOT NULL,
    "localDate" TEXT NOT NULL,
    "slot" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CalendarKeep_pkey" PRIMARY KEY ("userId","localDate","slot")
);

-- AddForeignKey
ALTER TABLE "CalendarKeep" ADD CONSTRAINT "CalendarKeep_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
