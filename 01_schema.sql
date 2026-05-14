-- =============================================================
-- FILE: sql/01_schema.sql
-- PURPOSE: Create all tables for the Customer Feedback AI system
-- DATABASE: PostgreSQL 14+ | Also compatible with BigQuery DDL
--           (replace SERIAL with INT64, TEXT with STRING for BQ)
-- RUN: psql -U postgres -d feedback_db -f sql/01_schema.sql
-- =============================================================


-- -------------------------------------------------------------
-- 0. Create database (run as superuser if needed)
-- -------------------------------------------------------------
-- CREATE DATABASE feedback_db;
-- \c feedback_db


-- -------------------------------------------------------------
-- 1. RAW FEEDBACK TABLE
--    Stores unprocessed text exactly as ingested from source.
--    No AI fields here — keeps raw and processed cleanly separated.
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_feedback (
    feedback_id     SERIAL          PRIMARY KEY,
    source          VARCHAR(50)     NOT NULL,           -- 'amazon_review' | 'twitter' | 'support_ticket' | 'yelp'
    source_id       VARCHAR(100),                       -- Original ID from source dataset
    raw_text        TEXT            NOT NULL,           -- The unstructured customer feedback
    rating          NUMERIC(2,1),                       -- Star rating if available (1.0–5.0)
    author          VARCHAR(200),
    feedback_date   DATE,
    product_name    VARCHAR(300),
    ingested_at     TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    is_processed    BOOLEAN         NOT NULL DEFAULT FALSE,

    CONSTRAINT chk_source CHECK (
        source IN ('amazon_review','twitter','support_ticket','yelp','clothing_review','manual')
    ),
    CONSTRAINT chk_rating CHECK (rating IS NULL OR (rating >= 1.0 AND rating <= 5.0))
);

-- Index for unprocessed rows — the AI job queries this constantly
CREATE INDEX IF NOT EXISTS idx_raw_unprocessed ON raw_feedback (is_processed, ingested_at);
CREATE INDEX IF NOT EXISTS idx_raw_source       ON raw_feedback (source);
CREATE INDEX IF NOT EXISTS idx_raw_date         ON raw_feedback (feedback_date);


-- -------------------------------------------------------------
-- 2. PROCESSED FEEDBACK TABLE
--    AI-enriched output. One row per raw_feedback row.
--    Joins back to raw_feedback for the original text.
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS processed_feedback (
    processed_id        SERIAL          PRIMARY KEY,
    feedback_id         INT             NOT NULL REFERENCES raw_feedback(feedback_id) ON DELETE CASCADE,
    sentiment           VARCHAR(20)     NOT NULL,       -- 'positive' | 'neutral' | 'negative'
    sentiment_score     NUMERIC(4,3),                   -- Continuous score: -1.0 (most neg) to +1.0 (most pos)
    topic_label         VARCHAR(100)    NOT NULL,       -- See topic taxonomy below
    topic_confidence    NUMERIC(4,3),                   -- 0.000 to 1.000
    extracted_keywords  TEXT[],                         -- Array: ARRAY['login','mobile','crash']
    summary_sentence    TEXT,                           -- 1-sentence AI-generated summary
    ai_model_used       VARCHAR(100),                   -- e.g. 'claude-3-5-sonnet-20241022'
    processed_at        TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    processing_version  VARCHAR(20)     DEFAULT 'v1.0', -- For pipeline version tracking

    CONSTRAINT chk_sentiment CHECK (sentiment IN ('positive','neutral','negative')),
    CONSTRAINT chk_score     CHECK (sentiment_score IS NULL OR sentiment_score BETWEEN -1.0 AND 1.0),
    CONSTRAINT chk_confidence CHECK (topic_confidence IS NULL OR topic_confidence BETWEEN 0.0 AND 1.0)
);

-- Topic taxonomy (enforced via application, documented here):
-- 'UI/UX Issue'         — interface problems, design complaints, navigation issues
-- 'Performance Issue'   — slow load times, crashes, timeouts
-- 'Bug / Error'         — software defects, broken features
-- 'Billing Issue'       — payment problems, incorrect charges, refund requests
-- 'Feature Request'     — suggestions for new functionality
-- 'Feature Praise'      — positive comments about specific features
-- 'Customer Support'    — feedback about support team quality
-- 'General Positive'    — broad satisfaction without specific topic
-- 'General Negative'    — broad dissatisfaction without specific topic
-- 'Shipping / Delivery' — delivery timing, packaging (for e-commerce)
-- 'Other'               — does not fit above categories

CREATE INDEX IF NOT EXISTS idx_proc_feedback_id  ON processed_feedback (feedback_id);
CREATE INDEX IF NOT EXISTS idx_proc_sentiment     ON processed_feedback (sentiment);
CREATE INDEX IF NOT EXISTS idx_proc_topic         ON processed_feedback (topic_label);
CREATE INDEX IF NOT EXISTS idx_proc_processed_at  ON processed_feedback (processed_at);


-- -------------------------------------------------------------
-- 3. WEEKLY SUMMARY TABLE
--    Pre-aggregated snapshot for dashboard performance.
--    Populated by a weekly aggregation job.
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS weekly_summary (
    summary_id          SERIAL          PRIMARY KEY,
    week_start          DATE            NOT NULL,
    source              VARCHAR(50),                    -- NULL = all sources combined
    total_feedback      INT             NOT NULL DEFAULT 0,
    positive_count      INT             NOT NULL DEFAULT 0,
    neutral_count       INT             NOT NULL DEFAULT 0,
    negative_count      INT             NOT NULL DEFAULT 0,
    positive_pct        NUMERIC(5,2),
    negative_pct        NUMERIC(5,2),
    avg_sentiment_score NUMERIC(5,3),
    top_topic           VARCHAR(100),
    top_topic_count     INT,
    computed_at         TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_week_source UNIQUE (week_start, source)
);


-- -------------------------------------------------------------
-- 4. TOPIC SPIKE ALERTS TABLE
--    Stores detected anomalies for the dashboard alert card.
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS topic_spike_alerts (
    alert_id            SERIAL          PRIMARY KEY,
    detected_at         TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    week_start          DATE            NOT NULL,
    topic_label         VARCHAR(100)    NOT NULL,
    current_count       INT             NOT NULL,
    previous_count      INT             NOT NULL,
    pct_change          NUMERIC(6,2)    NOT NULL,   -- e.g. 30.00 = 30% increase
    severity            VARCHAR(20)     NOT NULL DEFAULT 'warning',  -- 'info' | 'warning' | 'critical'
    is_acknowledged     BOOLEAN         NOT NULL DEFAULT FALSE,

    CONSTRAINT chk_severity CHECK (severity IN ('info','warning','critical'))
);


-- -------------------------------------------------------------
-- 5. PIPELINE RUN LOG
--    Audit table: every execution of the ingestion + AI job.
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pipeline_run_log (
    run_id              SERIAL          PRIMARY KEY,
    run_started_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    run_completed_at    TIMESTAMPTZ,
    rows_ingested       INT             DEFAULT 0,
    rows_processed      INT             DEFAULT 0,
    rows_failed         INT             DEFAULT 0,
    status              VARCHAR(20)     NOT NULL DEFAULT 'running',  -- 'running' | 'success' | 'failed'
    error_message       TEXT,
    triggered_by        VARCHAR(50)     DEFAULT 'manual',           -- 'manual' | 'github_actions' | 'api'

    CONSTRAINT chk_status CHECK (status IN ('running','success','failed'))
);


-- =============================================================
-- VERIFICATION QUERIES (uncomment to test after running schema)
-- =============================================================
-- SELECT table_name FROM information_schema.tables WHERE table_schema = 'public';
-- \d raw_feedback
-- \d processed_feedback
