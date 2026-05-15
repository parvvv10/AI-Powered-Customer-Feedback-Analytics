"""
FILE: python/01_data_ingestion.py
PURPOSE: Load CSV datasets (Kaggle or sample) → PostgreSQL raw_feedback table
USAGE:
    python python/01_data_ingestion.py --source data/sample_feedback.csv
    python python/01_data_ingestion.py --source ~/Downloads/amazon-reviews.csv --dataset amazon
    python python/01_data_ingestion.py --source all   # loads all CSVs in data/ folder
"""

import os
import sys
import argparse
import logging
from datetime import datetime
from pathlib import Path

import pandas as pd
from sqlalchemy import create_engine, text
from dotenv import load_dotenv

# ── Setup ───────────────────────────────────────────────────────────────
load_dotenv()

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
log = logging.getLogger(__name__)

DB_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://postgres:postgres@localhost:5432/feedback_db",
)

# ── Column Mappings per Kaggle dataset ──────────────────────────────────
# Maps each dataset's native columns → our raw_feedback schema.

DATASET_SCHEMAS = {
    "amazon": {
        "source": "amazon_review",
        "text_col": "Text",
        "rating_col": "Score",
        "author_col": "ProfileName",
        "date_col": "Time",           # Unix timestamp
        "product_col": "ProductId",
        "id_col": "Id",
        "date_is_unix": True,
    },
    "twitter": {
        "source": "twitter",
        "text_col": "text",
        "rating_col": None,
        "author_col": "name",
        "date_col": None,
        "product_col": "airline",
        "id_col": "tweet_id",
        "date_is_unix": False,
    },
    "support": {
        "source": "support_ticket",
        "text_col": "Ticket Description",
        "rating_col": "Customer Satisfaction Rating",
        "author_col": "Customer Name",
        "date_col": "Date of Purchase",
        "product_col": "Product Purchased",
        "id_col": "Ticket ID",
        "date_is_unix": False,
    },
    "yelp": {
        "source": "yelp",
        "text_col": "text",
        "rating_col": "stars",
        "author_col": "user_id",
        "date_col": "date",
        "product_col": "business_id",
        "id_col": "review_id",
        "date_is_unix": False,
    },
    "clothing": {
        "source": "clothing_review",
        "text_col": "Review Text",
        "rating_col": "Rating",
        "author_col": None,
        "date_col": None,
        "product_col": "Division Name",
        "id_col": None,
        "date_is_unix": False,
    },
    # Generic fallback for the project's own sample CSV
    "sample": {
        "source": "manual",
        "text_col": "raw_text",
        "rating_col": "rating",
        "author_col": "author",
        "date_col": "feedback_date",
        "product_col": "product_name",
        "id_col": "source_id",
        "date_is_unix": False,
    },
}


# ── Detect dataset type from filename ───────────────────────────────────

def detect_dataset(filepath: str) -> str:
    name = Path(filepath).stem.lower()
    if "amazon" in name:
        return "amazon"
    if "twitter" in name or "airline" in name:
        return "twitter"
    if "support" in name or "ticket" in name:
        return "support"
    if "yelp" in name:
        return "yelp"
    if "clothing" in name or "ecommerce" in name:
        return "clothing"
    return "sample"


# ── Core ingestion logic ─────────────────────────────────────────────────

def load_csv(filepath: str, dataset_type: str, max_rows: int = 50_000) -> pd.DataFrame:
    """
    Read a CSV file and normalize it to the raw_feedback schema.
    Caps at max_rows to avoid overwhelming the DB during development.
    """
    log.info(f"Reading '{filepath}' as dataset type: {dataset_type}")
    schema = DATASET_SCHEMAS[dataset_type]

    try:
        df = pd.read_csv(filepath, nrows=max_rows, low_memory=False)
    except Exception as e:
        log.error(f"Failed to read CSV: {e}")
        raise

    log.info(f"Loaded {len(df):,} rows, columns: {list(df.columns)}")

    # ── Map to canonical column names ──────────────────────────────────
    result = pd.DataFrame()

    result["source"]       = schema["source"]
    result["source_id"]    = df[schema["id_col"]].astype(str) if schema["id_col"] and schema["id_col"] in df else None
    result["raw_text"]     = df[schema["text_col"]].astype(str) if schema["text_col"] in df else ""
    result["rating"]       = pd.to_numeric(df[schema["rating_col"]], errors="coerce") if schema["rating_col"] and schema["rating_col"] in df else None
    result["author"]       = df[schema["author_col"]].astype(str)  if schema["author_col"] and schema["author_col"] in df else None
    result["product_name"] = df[schema["product_col"]].astype(str) if schema["product_col"] and schema["product_col"] in df else None

    # ── Parse dates ────────────────────────────────────────────────────
    if schema["date_col"] and schema["date_col"] in df:
        if schema["date_is_unix"]:
            result["feedback_date"] = pd.to_datetime(df[schema["date_col"]], unit="s", errors="coerce").dt.date
        else:
            result["feedback_date"] = pd.to_datetime(df[schema["date_col"]], errors="coerce").dt.date
    else:
        result["feedback_date"] = None

    # ── Clean up ───────────────────────────────────────────────────────
    # Drop rows with empty text
    before = len(result)
    result = result[result["raw_text"].str.strip().str.len() > 0]
    result = result.dropna(subset=["raw_text"])
    log.info(f"After cleaning: {len(result):,} rows (dropped {before - len(result):,} empty)")

    # Truncate text to 10k chars (prevents DB bloat)
    result["raw_text"] = result["raw_text"].str[:10_000]

    # Add pipeline metadata
    result["is_processed"] = False
    result["ingested_at"]  = datetime.utcnow()

    return result


def ingest_to_db(df: pd.DataFrame, engine) -> int:
    """
    Write the normalized DataFrame to raw_feedback, skipping duplicates
    on (source, source_id). Returns the number of new rows inserted.
    """
    if df.empty:
        log.warning("DataFrame is empty — nothing to ingest.")
        return 0

    # Write to a temp table first, then INSERT … ON CONFLICT DO NOTHING
    tmp_table = "tmp_ingest"
    df.to_sql(tmp_table, engine, if_exists="replace", index=False, method="multi", chunksize=500)

    insert_sql = f"""
        INSERT INTO raw_feedback
            (source, source_id, raw_text, rating, author, feedback_date,
             product_name, is_processed, ingested_at)
        SELECT
            source, source_id, raw_text, rating, author, feedback_date,
            product_name, is_processed, ingested_at
        FROM {tmp_table}
        ON CONFLICT DO NOTHING
    """

    with engine.begin() as conn:
        conn.execute(text(f"DROP TABLE IF EXISTS {tmp_table}"))
        # recreate via to_sql above (already done)

    df.to_sql(tmp_table, engine, if_exists="replace", index=False, method="multi", chunksize=500)

    with engine.begin() as conn:
        result = conn.execute(text(insert_sql))
        inserted = result.rowcount
        conn.execute(text(f"DROP TABLE IF EXISTS {tmp_table}"))

    log.info(f"Inserted {inserted:,} new rows into raw_feedback")
    return inserted


def log_run(engine, rows_ingested: int, status: str, error: str = None):
    """Write a record to the pipeline_run_log audit table."""
    sql = """
        INSERT INTO pipeline_run_log
            (rows_ingested, status, error_message, triggered_by, run_completed_at)
        VALUES
            (:rows_ingested, :status, :error, 'manual', NOW())
    """
    with engine.begin() as conn:
        conn.execute(text(sql), {"rows_ingested": rows_ingested, "status": status, "error": error})


# ── CLI entry point ──────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Ingest customer feedback CSV → PostgreSQL")
    parser.add_argument("--source",   required=True, help="Path to CSV file, or 'all' to scan data/ folder")
    parser.add_argument("--dataset",  default=None,  help="Force dataset type: amazon|twitter|support|yelp|clothing|sample")
    parser.add_argument("--max-rows", type=int, default=50_000, help="Max rows per file (default: 50000)")
    parser.add_argument("--dry-run",  action="store_true", help="Parse and validate only, do not write to DB")
    args = parser.parse_args()

    engine = create_engine(DB_URL, echo=False)
    total_inserted = 0

    try:
        # Collect files to process
        if args.source == "all":
            files = list(Path("data").glob("*.csv"))
            if not files:
                log.error("No CSV files found in data/ directory")
                sys.exit(1)
            log.info(f"Found {len(files)} CSV files in data/")
        else:
            files = [Path(args.source)]

        for filepath in files:
            if not filepath.exists():
                log.error(f"File not found: {filepath}")
                continue

            dataset_type = args.dataset or detect_dataset(str(filepath))
            if dataset_type not in DATASET_SCHEMAS:
                log.error(f"Unknown dataset type '{dataset_type}'. Use: {list(DATASET_SCHEMAS.keys())}")
                continue

            df = load_csv(str(filepath), dataset_type, max_rows=args.max_rows)

            if args.dry_run:
                log.info(f"[DRY RUN] Would insert {len(df):,} rows. Sample:")
                print(df[["source", "raw_text", "rating", "feedback_date"]].head(3).to_string())
                continue

            inserted = ingest_to_db(df, engine)
            total_inserted += inserted

        if not args.dry_run:
            log_run(engine, total_inserted, "success")
            log.info(f"✅ Ingestion complete. Total new rows: {total_inserted:,}")

    except Exception as e:
        log.exception(f"Ingestion failed: {e}")
        if not args.dry_run:
            log_run(engine, total_inserted, "failed", str(e))
        sys.exit(1)


if __name__ == "__main__":
    main()
