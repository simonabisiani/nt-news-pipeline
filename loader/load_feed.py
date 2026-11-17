"""
Load an RSS feed into the raw layer (Extract + Load in ELT).

Every run appends one row per feed item, tagged with a batch_id and fetched_at.
Nothing is cleaned or deduplicated here: the raw table is an append-only log,
and all transformation happens in dbt. Keeping the log lets the models detect
headline changes, articles that drop out of the feed and gaps in collection.

Usage:
    # Local development (DuckDB file)
    python loader/load_feed.py --target duckdb

    # Load a saved XML file instead of fetching (used in CI)
    python loader/load_feed.py --target duckdb --from-file tests/fixtures/fetch_1.xml \
        --fetched-at 2026-11-16T08:00:00

    # Snowflake (credentials from environment variables, see README)
    python loader/load_feed.py --target snowflake
"""

from __future__ import annotations

import argparse
import logging
import os
import sys
import time
import urllib.error
import urllib.request
import uuid
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

DEFAULT_FEED_URL = "https://www.nt.se/rss/lokalt"
USER_AGENT = "nt-news-pipeline/1.0 (portfolio data engineering project)"
RAW_TABLE = "nt_feed_items"

COLUMNS = [
    "batch_id",
    "fetched_at",
    "feed_url",
    "item_position",
    "guid",
    "link",
    "title",
    "description",
    "pub_date_raw",
]

DDL = f"""
create table if not exists {{schema}}.{RAW_TABLE} (
    batch_id      varchar   not null,
    fetched_at    timestamp not null,
    feed_url      varchar   not null,
    item_position integer,
    guid          varchar,
    link          varchar,
    title         varchar,
    description   varchar,
    pub_date_raw  varchar
)
"""

log = logging.getLogger("load_feed")


def fetch_xml(url: str, retries: int = 3, timeout: int = 20) -> bytes:
    """Fetch the feed with a few retries and exponential backoff."""
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    for attempt in range(1, retries + 1):
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return response.read()
        except (urllib.error.URLError, TimeoutError) as exc:
            if attempt == retries:
                raise
            wait = 2**attempt
            log.warning("Fetch failed (%s), retrying in %ss", exc, wait)
            time.sleep(wait)
    raise RuntimeError("unreachable")


def parse_items(xml_bytes: bytes) -> list[dict]:
    """Extract raw item fields as strings. No cleaning: that is dbt's job."""
    root = ET.fromstring(xml_bytes)
    items = []
    for position, item in enumerate(root.iter("item"), start=1):
        def text(tag: str) -> str | None:
            node = item.find(tag)
            return node.text.strip() if node is not None and node.text else None

        items.append(
            {
                "item_position": position,
                "guid": text("guid"),
                "link": text("link"),
                "title": text("title"),
                "description": text("description"),
                "pub_date_raw": text("pubDate"),
            }
        )
    return items


def build_rows(items: list[dict], feed_url: str, fetched_at: datetime) -> list[tuple]:
    batch_id = str(uuid.uuid4())
    rows = []
    for item in items:
        record = {"batch_id": batch_id, "fetched_at": fetched_at, "feed_url": feed_url, **item}
        rows.append(tuple(record[col] for col in COLUMNS))
    return rows


def load_duckdb(rows: list[tuple], path: str, schema: str) -> None:
    import duckdb

    con = duckdb.connect(path)
    con.execute(f"create schema if not exists {schema}")
    con.execute(DDL.format(schema=schema))
    placeholders = ", ".join(["?"] * len(COLUMNS))
    con.executemany(
        f"insert into {schema}.{RAW_TABLE} ({', '.join(COLUMNS)}) values ({placeholders})", rows
    )
    con.close()


def load_snowflake(rows: list[tuple], schema: str) -> None:
    import snowflake.connector

    con = snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_LOADER_USER"],
        private_key_file=os.environ["SNOWFLAKE_LOADER_PRIVATE_KEY_PATH"],
        role=os.environ.get("SNOWFLAKE_LOADER_ROLE", "LOADER"),
        warehouse=os.environ.get("SNOWFLAKE_WAREHOUSE", "NEWS_WH"),
        database=os.environ.get("SNOWFLAKE_DATABASE", "NEWS"),
        schema=schema,
    )
    try:
        # The table is created by snowflake/setup.sql. LOADER may only insert.
        cur = con.cursor()
        placeholders = ", ".join(["%s"] * len(COLUMNS))
        cur.executemany(
            f"insert into {schema}.{RAW_TABLE} ({', '.join(COLUMNS)}) values ({placeholders})",
            rows,
        )
    finally:
        con.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--target", choices=["duckdb", "snowflake"], default="duckdb")
    parser.add_argument("--feed-url", default=os.environ.get("FEED_URL", DEFAULT_FEED_URL))
    parser.add_argument("--from-file", help="Load a saved XML file instead of fetching the feed")
    parser.add_argument("--fetched-at", help="Override fetched_at (ISO, UTC). Useful for fixtures.")
    parser.add_argument("--duckdb-path", default=os.environ.get("DUCKDB_PATH", "nt_news.duckdb"))
    parser.add_argument("--schema", default=os.environ.get("RAW_SCHEMA", "raw"))
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    if args.from_file:
        with open(args.from_file, "rb") as fh:
            xml_bytes = fh.read()
    else:
        xml_bytes = fetch_xml(args.feed_url)

    fetched_at = (
        datetime.fromisoformat(args.fetched_at)
        if args.fetched_at
        else datetime.now(timezone.utc).replace(tzinfo=None, microsecond=0)
    )

    items = parse_items(xml_bytes)
    if not items:
        # An empty feed is suspicious. Fail loudly so the scheduler flags it.
        log.error("Feed returned no items: %s", args.feed_url)
        return 1

    rows = build_rows(items, args.feed_url, fetched_at)
    if args.target == "duckdb":
        load_duckdb(rows, args.duckdb_path, args.schema)
    else:
        load_snowflake(rows, args.schema)

    log.info("Loaded %s items into %s.%s (%s)", len(rows), args.schema, RAW_TABLE, args.target)
    return 0


if __name__ == "__main__":
    sys.exit(main())
