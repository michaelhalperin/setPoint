-- CreateEnum
CREATE TYPE "ExpertKind" AS ENUM ('NUTRITION');

-- CreateEnum
CREATE TYPE "ExpertProposalStatus" AS ENUM ('PENDING', 'CONFIRMED', 'DISMISSED', 'EXPIRED', 'SUPERSEDED', 'INVALID');

-- CreateTable
CREATE TABLE "ExpertConversation" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "kind" "ExpertKind" NOT NULL DEFAULT 'NUTRITION',
    "transcript" JSONB NOT NULL DEFAULT '[]',
    "consentedAt" TIMESTAMP(3),
    "reviewConsentAt" TIMESTAMP(3),
    "lockedUntil" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ExpertConversation_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ExpertProposal" (
    "id" TEXT NOT NULL,
    "conversationId" TEXT NOT NULL,
    "status" "ExpertProposalStatus" NOT NULL DEFAULT 'PENDING',
    "kind" TEXT NOT NULL,
    "args" JSONB NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "resolvedAt" TIMESTAMP(3),

    CONSTRAINT "ExpertProposal_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ExpertSafetyTrip" (
    "id" TEXT NOT NULL,
    "conversationId" TEXT,
    "userId" TEXT NOT NULL,
    "layer" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "userMessage" TEXT,
    "discardedReply" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ExpertSafetyTrip_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ExpertReviewAudit" (
    "id" TEXT NOT NULL,
    "reviewer" TEXT NOT NULL,
    "conversationId" TEXT NOT NULL,
    "reason" TEXT NOT NULL,
    "at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ExpertReviewAudit_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "ExpertConversation_userId_kind_key" ON "ExpertConversation"("userId", "kind");
CREATE INDEX "ExpertConversation_userId_idx" ON "ExpertConversation"("userId");
CREATE INDEX "ExpertProposal_conversationId_status_idx" ON "ExpertProposal"("conversationId", "status");
CREATE INDEX "ExpertSafetyTrip_userId_createdAt_idx" ON "ExpertSafetyTrip"("userId", "createdAt");
CREATE INDEX "ExpertSafetyTrip_conversationId_idx" ON "ExpertSafetyTrip"("conversationId");
CREATE INDEX "ExpertReviewAudit_conversationId_at_idx" ON "ExpertReviewAudit"("conversationId", "at");

ALTER TABLE "ExpertConversation" ADD CONSTRAINT "ExpertConversation_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ExpertProposal" ADD CONSTRAINT "ExpertProposal_conversationId_fkey" FOREIGN KEY ("conversationId") REFERENCES "ExpertConversation"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ExpertSafetyTrip" ADD CONSTRAINT "ExpertSafetyTrip_conversationId_fkey" FOREIGN KEY ("conversationId") REFERENCES "ExpertConversation"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ExpertSafetyTrip" ADD CONSTRAINT "ExpertSafetyTrip_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
