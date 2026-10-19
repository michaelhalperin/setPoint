-- CreateTable
CREATE TABLE "FeatureFlag" (
    "key" TEXT NOT NULL,
    "enabled" BOOLEAN NOT NULL DEFAULT false,
    "cohorts" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "roles" "UserRole"[] DEFAULT ARRAY[]::"UserRole"[],
    "userIds" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "note" TEXT,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "FeatureFlag_pkey" PRIMARY KEY ("key")
);
