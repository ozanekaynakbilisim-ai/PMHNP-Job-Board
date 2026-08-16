-- Fresh-database bootstrap for SavedCandidate.
--
-- Historical context:
-- saved_candidates originally reached the production database through
-- `prisma db push`, not through a checked-in migration. The later migration
-- `20260430_add_saved_candidate_tags` therefore assumes this table already
-- exists and fails on a brand-new database. The comprehensive
-- `20260611_create_missing_tables_baseline` eventually creates this table,
-- but it sorts too late for a clean `prisma migrate deploy`.
--
-- This forward-only migration closes that historical gap without changing
-- existing installations. It is intentionally idempotent so databases that
-- already contain saved_candidates are left untouched. The June baseline
-- remains responsible for its indexes and foreign keys and is also
-- idempotent.

CREATE TABLE IF NOT EXISTS "saved_candidates" (
    "id" TEXT NOT NULL,
    "employer_id" TEXT NOT NULL,
    "candidate_id" TEXT NOT NULL,
    "employer_job_id" TEXT,
    "note" TEXT,
    "tags" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "saved_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "saved_candidates_pkey" PRIMARY KEY ("id")
);
