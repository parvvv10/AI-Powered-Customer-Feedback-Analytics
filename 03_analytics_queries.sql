-- =============================================================
-- FILE: sql/03_analytics_queries.sql
-- PURPOSE: Ad-hoc exploration queries — run in pgAdmin or DBeaver
-- REFERENCE: Google AI Use Case #31 — BI with GenAI
-- =============================================================


-- -------------------------------------------------------------
-- Q1: Overall sentiment breakdown (quick healthcheck)
-- -------------------------------------------------------------
SELECT
    sentiment,
    COUNT(*)                                                     AS total,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)          AS pct
FROM processed_feedback
GROUP BY sentiment
ORDER BY total DESC;


-- -------------------------------------------------------------
-- Q2: Top 10 topics by volume — negative only
--     "What are customers most upset about?"
-- -------------------------------------------------------------
SELECT
    p.topic_label,
    COUNT(*)                                            AS negative_count,
    ROUND(AVG(p.sentiment_score)::NUMERIC, 3)           AS avg_sentiment_score,
    ROUND(AVG(p.topic_confidence)::NUMERIC, 3)          AS avg_confidence
FROM processed_feedback p
WHERE p.sentiment = 'negative'
GROUP BY p.topic_label
ORDER BY negative_count DESC
LIMIT 10;


-- -------------------------------------------------------------
-- Q3: Weekly negative sentiment spike detection
--     Alerts where negative % jumped more than 15 points vs
--     the prior week — simulates the dashboard alert card.
-- -------------------------------------------------------------
WITH weekly_neg AS (
    SELECT
        DATE_TRUNC('week', r.feedback_date)::DATE       AS week_start,
        COUNT(*)                                         AS total,
        SUM(CASE WHEN p.sentiment = 'negative' THEN 1 ELSE 0 END) AS neg_count,
        ROUND(
            100.0 * SUM(CASE WHEN p.sentiment = 'negative' THEN 1 ELSE 0 END)
                  / NULLIF(COUNT(*), 0), 2
        )                                                AS neg_pct
    FROM raw_feedback r
    JOIN processed_feedback p ON r.feedback_id = p.feedback_id
    GROUP BY 1
),
with_lag AS (
    SELECT
        week_start,
        total,
        neg_count,
        neg_pct,
        LAG(neg_pct) OVER (ORDER BY week_start)         AS prev_neg_pct
    FROM weekly_neg
)
SELECT
    week_start,
    total,
    neg_pct,
    prev_neg_pct,
    ROUND(neg_pct - COALESCE(prev_neg_pct, neg_pct), 2) AS delta_pct,
    CASE
        WHEN (neg_pct - COALESCE(prev_neg_pct, 0)) >= 15 THEN '🚨 SPIKE'
        WHEN (neg_pct - COALESCE(prev_neg_pct, 0)) >= 5  THEN '⚠️  WATCH'
        ELSE '✅ NORMAL'
    END                                                  AS status
FROM with_lag
ORDER BY week_start DESC;


-- -------------------------------------------------------------
-- Q4: Source channel comparison
--     Which channels produce the most negative feedback?
-- -------------------------------------------------------------
SELECT
    r.source,
    COUNT(*)                                                        AS total,
    SUM(CASE WHEN p.sentiment = 'negative' THEN 1 ELSE 0 END)      AS negative,
    ROUND(
        100.0 * SUM(CASE WHEN p.sentiment = 'negative' THEN 1 ELSE 0 END)
              / NULLIF(COUNT(*), 0), 2
    )                                                               AS negative_pct,
    ROUND(AVG(p.sentiment_score)::NUMERIC, 3)                       AS avg_score
FROM raw_feedback r
JOIN processed_feedback p ON r.feedback_id = p.feedback_id
GROUP BY r.source
ORDER BY negative_pct DESC;


-- -------------------------------------------------------------
-- Q5: Rolling 4-week average sentiment score
--     Smooth out noise to see true trend.
-- -------------------------------------------------------------
WITH weekly_avg AS (
    SELECT
        DATE_TRUNC('week', r.feedback_date)::DATE   AS week_start,
        ROUND(AVG(p.sentiment_score)::NUMERIC, 3)   AS avg_score
    FROM raw_feedback r
    JOIN processed_feedback p ON r.feedback_id = p.feedback_id
    GROUP BY 1
)
SELECT
    week_start,
    avg_score,
    ROUND(
        AVG(avg_score) OVER (
            ORDER BY week_start
            ROWS BETWEEN 3 PRECEDING AND CURRENT ROW
        )::NUMERIC, 3
    )   AS rolling_4wk_avg
FROM weekly_avg
ORDER BY week_start DESC;


-- -------------------------------------------------------------
-- Q6: Most common negative keywords this month
--     Feed this into a word cloud visualization.
-- -------------------------------------------------------------
SELECT
    kw.keyword,
    COUNT(*)    AS frequency
FROM processed_feedback p,
     UNNEST(p.extracted_keywords) AS kw(keyword)
JOIN raw_feedback r ON r.feedback_id = p.feedback_id
WHERE p.sentiment = 'negative'
  AND r.feedback_date >= DATE_TRUNC('month', CURRENT_DATE)
  AND LENGTH(kw.keyword) >= 4
GROUP BY kw.keyword
ORDER BY frequency DESC
LIMIT 30;


-- -------------------------------------------------------------
-- Q7: AI model performance audit
--     Check confidence scores per model — useful if you
--     switch between Claude and GPT-4o.
-- -------------------------------------------------------------
SELECT
    p.ai_model_used,
    COUNT(*)                                            AS total_processed,
    ROUND(AVG(p.topic_confidence)::NUMERIC, 3)          AS avg_topic_confidence,
    ROUND(AVG(ABS(p.sentiment_score))::NUMERIC, 3)      AS avg_sentiment_magnitude,
    SUM(CASE WHEN p.topic_confidence >= 0.90 THEN 1 ELSE 0 END)  AS high_confidence_count,
    ROUND(
        100.0 * SUM(CASE WHEN p.topic_confidence >= 0.90 THEN 1 ELSE 0 END)
              / NULLIF(COUNT(*), 0), 2
    )                                                   AS high_confidence_pct
FROM processed_feedback p
GROUP BY p.ai_model_used
ORDER BY total_processed DESC;


-- -------------------------------------------------------------
-- Q8: Product-specific sentiment (for Amazon/e-commerce data)
-- -------------------------------------------------------------
SELECT
    r.product_name,
    COUNT(*)                                                        AS review_count,
    ROUND(AVG(r.rating)::NUMERIC, 2)                               AS avg_star_rating,
    ROUND(AVG(p.sentiment_score)::NUMERIC, 3)                      AS avg_ai_sentiment,
    SUM(CASE WHEN p.sentiment = 'positive' THEN 1 ELSE 0 END)      AS positive_count,
    SUM(CASE WHEN p.sentiment = 'negative' THEN 1 ELSE 0 END)      AS negative_count
FROM raw_feedback r
JOIN processed_feedback p ON r.feedback_id = p.feedback_id
WHERE r.product_name IS NOT NULL
GROUP BY r.product_name
HAVING COUNT(*) >= 5              -- Only products with enough reviews
ORDER BY avg_ai_sentiment ASC     -- Worst-rated products first
LIMIT 20;


-- -------------------------------------------------------------
-- Q9: Feedback volume by day of week
--     Useful to understand when customers are most active.
-- -------------------------------------------------------------
SELECT
    TO_CHAR(r.feedback_date, 'Day')                             AS day_name,
    EXTRACT(DOW FROM r.feedback_date)::INT                      AS day_num,
    COUNT(*)                                                    AS total_feedback,
    ROUND(AVG(p.sentiment_score)::NUMERIC, 3)                  AS avg_sentiment
FROM raw_feedback r
JOIN processed_feedback p ON r.feedback_id = p.feedback_id
WHERE r.feedback_date IS NOT NULL
GROUP BY 1, 2
ORDER BY 2;


-- -------------------------------------------------------------
-- Q10: Pipeline efficiency report
--     How many rows are still awaiting AI processing?
-- -------------------------------------------------------------
SELECT
    COUNT(*)                                                            AS total_raw,
    SUM(CASE WHEN is_processed THEN 1 ELSE 0 END)                      AS processed,
    SUM(CASE WHEN NOT is_processed THEN 1 ELSE 0 END)                  AS pending,
    ROUND(
        100.0 * SUM(CASE WHEN is_processed THEN 1 ELSE 0 END)
              / NULLIF(COUNT(*), 0), 2
    )                                                                   AS processing_pct
FROM raw_feedback;
