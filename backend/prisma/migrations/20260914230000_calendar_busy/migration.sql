-- AlterTable
ALTER TABLE "OnboardingProfile" ADD COLUMN "calendarEnabled" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN "calendarLeadMin" INTEGER NOT NULL DEFAULT 45,
ADD COLUMN "calendarMinBlockMin" INTEGER NOT NULL DEFAULT 60,
ADD COLUMN "calendarWorkdaysOnly" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN "calendarIncludeAllDay" BOOLEAN NOT NULL DEFAULT false;

-- AlterTable
ALTER TABLE "CheckIn" ADD COLUMN "kind" TEXT NOT NULL DEFAULT 'MEAL',
ADD COLUMN "movedFromMin" INTEGER,
ADD COLUMN "busyUntil" TIMESTAMP(3);

-- CreateTable
CREATE TABLE "CalendarBusyBlock" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "start" TIMESTAMP(3) NOT NULL,
    "end" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CalendarBusyBlock_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "CalendarBusyBlock_userId_start_idx" ON "CalendarBusyBlock"("userId", "start");

-- AddForeignKey
ALTER TABLE "CalendarBusyBlock" ADD CONSTRAINT "CalendarBusyBlock_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
