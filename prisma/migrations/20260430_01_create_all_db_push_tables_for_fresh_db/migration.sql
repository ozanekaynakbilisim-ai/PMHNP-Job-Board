-- Fresh-database bootstrap for tables that historically reached production via
-- `prisma db push` and were only added to the migration history later in
-- 20260611_create_missing_tables_baseline.
--
-- Keep this migration idempotent. The later 20260611 baseline remains in place
-- and will safely no-op for these CREATE TABLE statements on fresh installs.

CREATE TABLE IF NOT EXISTS "job_view_events" (
    "id" TEXT NOT NULL,
    "job_id" TEXT NOT NULL,
    "timestamp" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "session_id" TEXT,
    "referrer" TEXT,
    "user_agent" TEXT,
    CONSTRAINT "job_view_events_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "conversations" (
    "id" TEXT NOT NULL,
    "participant_a" TEXT NOT NULL,
    "participant_b" TEXT NOT NULL,
    "job_id" TEXT,
    "subject" TEXT NOT NULL,
    "last_message_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deleted_by_a" BOOLEAN NOT NULL DEFAULT false,
    "deleted_by_b" BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT "conversations_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "employer_messages" (
    "id" TEXT NOT NULL,
    "sender_id" TEXT NOT NULL,
    "recipient_id" TEXT NOT NULL,
    "conversation_id" TEXT,
    "job_id" TEXT,
    "subject" TEXT NOT NULL,
    "body" TEXT NOT NULL,
    "attachment_url" TEXT,
    "attachment_name" TEXT,
    "deleted_by_sender" BOOLEAN NOT NULL DEFAULT false,
    "deleted_by_recipient" BOOLEAN NOT NULL DEFAULT false,
    "sent_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "read_at" TIMESTAMP(3),
    "edited_at" TIMESTAMP(3),
    CONSTRAINT "employer_messages_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "youtube_videos" (
    "id" TEXT NOT NULL,
    "state_key" TEXT NOT NULL,
    "state_name" TEXT NOT NULL,
    "blog_slug" TEXT NOT NULL,
    "yt_title" TEXT NOT NULL,
    "yt_description" TEXT NOT NULL,
    "yt_tags" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "seo_keywords" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "hashtags" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "thumbnail_url" TEXT,
    "video_url" TEXT,
    "youtube_video_id" TEXT,
    "postiz_post_id" TEXT,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "scheduled_date" TIMESTAMP(3),
    "published_date" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "youtube_videos_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "job_screening_questions" (
    "id" TEXT NOT NULL,
    "job_id" TEXT NOT NULL,
    "question_text" TEXT NOT NULL,
    "question_type" TEXT NOT NULL,
    "options" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "is_required" BOOLEAN NOT NULL DEFAULT false,
    "is_knockout" BOOLEAN NOT NULL DEFAULT false,
    "knockout_answer" TEXT,
    "sort_order" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "job_screening_questions_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "job_reports" (
    "id" TEXT NOT NULL,
    "job_id" TEXT NOT NULL,
    "reason" TEXT NOT NULL,
    "details" TEXT,
    "ip_hash" TEXT,
    "reporter_email" TEXT,
    "reporter_name" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "job_reports_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "user_feedback" (
    "id" TEXT NOT NULL,
    "user_id" TEXT,
    "rating" INTEGER NOT NULL,
    "message" TEXT,
    "page" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "user_feedback_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "autofill_telemetry" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "timestamp" TIMESTAMP(3) NOT NULL,
    "ats_domain" TEXT,
    "field_name" TEXT NOT NULL,
    "field_label" TEXT NOT NULL,
    "field_type" TEXT NOT NULL,
    "match_method" TEXT NOT NULL,
    "profile_key" TEXT,
    "value_sample" TEXT,
    "confidence" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "filled" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "autofill_telemetry_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "rejected_jobs" (
    "id" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "employer" TEXT,
    "location" TEXT,
    "apply_link" TEXT,
    "external_id" TEXT,
    "source_provider" TEXT NOT NULL,
    "rejection_reason" TEXT NOT NULL,
    "raw_data" JSONB,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "rejected_jobs_pkey" PRIMARY KEY ("id")
);

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

CREATE TABLE IF NOT EXISTS "employer_candidate_alerts" (
    "id" TEXT NOT NULL,
    "employer_id" TEXT NOT NULL,
    "specialties" TEXT,
    "states" TEXT,
    "min_experience" INTEGER,
    "work_mode" TEXT,
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "last_sent_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "employer_candidate_alerts_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "email_broadcasts" (
    "id" TEXT NOT NULL,
    "subject" TEXT NOT NULL,
    "body" TEXT NOT NULL,
    "audience" TEXT NOT NULL,
    "audience_count" INTEGER NOT NULL DEFAULT 0,
    "status" TEXT NOT NULL DEFAULT 'draft',
    "scheduled_for" TIMESTAMP(3),
    "sent_at" TIMESTAMP(3),
    "sent_count" INTEGER NOT NULL DEFAULT 0,
    "failed_count" INTEGER NOT NULL DEFAULT 0,
    "template_id" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "email_broadcasts_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "email_broadcast_recipients" (
    "id" TEXT NOT NULL,
    "broadcast_id" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "first_name" TEXT,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "sent_at" TIMESTAMP(3),
    "error" TEXT,
    CONSTRAINT "email_broadcast_recipients_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "email_templates" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "subject" TEXT NOT NULL,
    "body" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "email_templates_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "saved_jobs" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "job_id" TEXT NOT NULL,
    "saved_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "saved_jobs_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "push_subscriptions" (
    "id" TEXT NOT NULL,
    "user_id" TEXT,
    "endpoint" TEXT NOT NULL,
    "p256dh" TEXT NOT NULL,
    "auth" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "push_subscriptions_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "email_sends" (
    "id" TEXT NOT NULL,
    "resend_id" TEXT,
    "to" TEXT NOT NULL,
    "subject" TEXT NOT NULL,
    "email_type" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'sent',
    "metadata" JSONB,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "email_sends_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "PseoStats" (
    "id" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "categorySlug" TEXT NOT NULL,
    "locationSlug" TEXT NOT NULL,
    "totalJobs" INTEGER NOT NULL DEFAULT 0,
    "rawAvgSalary" INTEGER NOT NULL DEFAULT 0,
    "colAdjustedSalary" INTEGER NOT NULL DEFAULT 0,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "PseoStats_pkey" PRIMARY KEY ("id")
);
