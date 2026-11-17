#!/usr/bin/env bash
# Load the three synthetic fixture fetches into a fresh local DuckDB file.
# Used in CI and for trying the project without network access.
set -euo pipefail
export DUCKDB_PATH="${DUCKDB_PATH:-nt_news.duckdb}"
rm -f "$DUCKDB_PATH"
python loader/load_feed.py --from-file tests/fixtures/fetch_1.xml --fetched-at 2026-11-16T08:00:00
python loader/load_feed.py --from-file tests/fixtures/fetch_2.xml --fetched-at 2026-11-16T10:00:00
python loader/load_feed.py --from-file tests/fixtures/fetch_3.xml --fetched-at 2026-11-16T20:00:00
