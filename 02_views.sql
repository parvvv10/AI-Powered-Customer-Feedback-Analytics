-- =============================================================
-- FILE: sql/02_views.sql
-- PURPOSE: Analytics views — Power BI connects to these directly
-- NOTE: Run AFTER 01_schema.sql
-- =============================================================


-- -------------------------------------------------------------
-- VIEW 1: vw_feedback_enriched
-- Master view joining raw + processed for all dashboard tables.
-- Power BI base table — import this view.
-- -------------------------------------------------------------
CREATE OR REPLACE VIEW vw_feedback_enriched AS
SELECT
    r.feedback_id,
    r.source,
    r.raw_text,
    r.rating,
    r.author,
    r.feedback_date,
    r.product_name,
    r.ingested_at,
    p.sentiment,
    p.sentiment_score,
    p.topic_label,
    p.topic_confidence,
    p.extracted_keywords,
    p.summary_sentence,
    p.processed_at,
    p.ai_model_used,
    -- Derived columns for Power BI slicers
    DATE_TRUNC('week',  r.feedback_date)::DATE  AS week_start,
    DATE_TRUNC('month', r.feedback_date)::DATE  AS month_start,
    EXTRACT(YEAR  FROM r.feedback_date)::INT     AS feedback_year,
    EXTRACT(MONTH FROM r.feedback_date)::INT     AS feedback_month,
    EXTRACT(DOW   FROM r.feedback_date)::INT     AS day_of_week,   -- 0=Sun…6=Sat
    -- Numeric encoding for Power BI measures
    CASE p.sentiment
        WHEN 'positive' THEN  1
        WHEN 'neutral'  THEN  0
        WHEN 'negative' THEN -1
        ELSE NULL
    END AS sentiment_numeric,
    -- High-confidence flag
    (p.topic_confidence >= 0.80)::INT AS is_high_confidence
FROM raw_feedback    r
JOIN processed_feedback p ON r.feedback_id = p.feedback_id;


-- -------------------------------------------------------------
-- VIEW 2: vw_weekly_sentiment_trend
-- One row per (week, source). Drives the main trend line chart.
-- -------------------------------------------------------------
CREATE OR REPLACE VIEW vw_weekly_sentiment_trend AS
SELECT
    DATE_TRUNC('week', r.feedback_date)::DATE  AS week_start,
    r.source,
    COUNT(*)                                    AS total_feedback,
    SUM(CASE WHEN p.sentiment = 'positive' THEN 1 ELSE 0 END)  AS positive_count,
    SUM(CASE WHEN p.sentiment = 'neutral'  THEN 1 ELSE 0 END)  AS neutral_count,
    SUM(CASE WHEN p.sentiment = 'negative' THEN 1 ELSE 0 END)  AS negative_count,
    ROUND(
        100.0 * SUM(CASE WHEN p.sentiment = 'positive' THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2
    )   AS positive_pct,
    ROUND(
        100.0 * SUM(CASE WHEN p.sentiment = 'negative' THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2
    )   AS negative_pct,
    ROUND(AVG(p.sentiment_score)::NUMERIC, 3)   AS avg_sentiment_score
FROM raw_feedback r
JOIN processed_feedback p ON r.feedback_id = p.feedback_id
WHERE r.feedback_date IS NOT NULL
GROUP BY 1, 2
ORDER BY 1 DESC, 2;


-- -------------------------------------------------------------
-- VIEW 3: vw_topic_distribution
-- Drives topic bar chart and heatmap.
-- -------------------------------------------------------------
CREATE OR REPLACE VIEW vw_topic_distribution AS
SELECT
    p.topic_label,
    p.sentiment,
    DATE_TRUNC('week', r.feedback_date)::DATE   AS week_start,
    r.source,
    COUNT(*)                                     AS feedback_count,
    ROUND(AVG(p.topic_confidence)::NUMERIC, 3)   AS avg_confidence,
    ROUND(AVG(p.sentiment_score)::NUMERIC, 3)    AS avg_sentiment_score
FROM raw_feedback r
JOIN processed_feedback p ON r.feedback_id = p.feedback_id
GROUP BY 1, 2, 3, 4
ORDER BY week_start DESC, feedback_count DESC;


-- -------------------------------------------------------------
-- VIEW 4: vw_topic_spikes
-- Compares current week vs. previous week per topic.
-- Power BI can use this to draw the alert card.
-- -------------------------------------------------------------
CREATE OR REPLACE VIEW vw_topic_spikes AS
WITH weekly_topic AS (
    SELECT
        DATE_TRUNC('week', r.feedback_date)::DATE  AS week_start,
        p.topic_label,
        COUNT(*)                                    AS cnt
    FROM raw_feedback r
    JOIN processed_feedback p ON r.feedback_id = p.feedback_id
    GROUP BY 1, 2
),
with_prev AS (
    SELECT
        week_start,
        topic_label,
        cnt                                     AS current_count,
        LAG(cnt) OVER (
            PARTITION BY topic_label
            ORDER BY week_start
        )                                       AS previous_count
    FROM weekly_topic
)
SELECT
    week_start,
    topic_label,
    current_count,
    COALESCE(previous_count, 0)                 AS previous_count,
    ROUND(
        100.0 * (current_count - COALESCE(previous_count, 0))
              / NULLIF(COALESCE(previous_count, 0), 0),
        2
    )                                           AS pct_change,
    CASE
        WHEN current_count - COALESCE(previous_count, 0) >= 50 THEN 'critical'
        WHEN current_count - COALESCE(previous_count, 0) >= 20 THEN 'warning'
        ELSE 'info'
    END                                         AS severity
FROM with_prev
WHERE week_start = DATE_TRUNC('week', CURRENT_DATE)::DATE
ORDER BY pct_change DESC NULLS LAST;


-- -------------------------------------------------------------
-- VIEW 5: vw_keyword_frequency
-- Unnests the keyword arrays for the word cloud visual.
-- -------------------------------------------------------------
CREATE OR REPLACE VIEW vw_keyword_frequency AS
SELECT
    kw.keyword,
    p.sentiment,
    p.topic_label,
    COUNT(*)                            AS frequency
FROM processed_feedback p,
     UNNEST(p.extracted_keywords) AS kw(keyword)
WHERE kw.keyword IS NOT NULL
  AND LENGTH(kw.keyword) >= 3          -- skip very short tokens
GROUP BY 1, 2, 3
ORDER BY frequency DESC;


-- -------------------------------------------------------------
-- VIEW 6: vw_source_summary
-- Channel-level breakdown for the source donut chart.
-- -------------------------------------------------------------
CREATE OR REPLACE VIEW vw_source_summary AS
SELECT
    r.source,
    COUNT(*)                                                        AS total_feedback,
    SUM(CASE WHEN p.sentiment = 'positive' THEN 1 ELSE 0 END)      AS positive_count,
    SUM(CASE WHEN p.sentiment = 'negative' THEN 1 ELSE 0 END)      AS negative_count,
    ROUND(AVG(p.sentiment_score)::NUMERIC, 3)                       AS avg_sentiment_score,
    MIN(r.feedback_date)                                            AS earliest_feedback,
    MAX(r.feedback_date)                                            AS latest_feedback
FROM raw_feedback r
JOIN processed_feedback p ON r.feedback_id = p.feedback_id
GROUP BY 1
ORDER BY total_feedback DESC;
