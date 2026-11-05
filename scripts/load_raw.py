"""
The "EL" step: load raw CSVs into DuckDB as the `raw` schema, untouched.
In a real company a tool like Fivetran or Airbyte does this for you.

Run:  python scripts/load_raw.py
"""
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "data" / "raw"
TABLES = ["customers", "products", "orders", "order_items", "events", "experiment_assignments"]

con = duckdb.connect(str(ROOT / "bioportal.duckdb"))
con.execute("create schema if not exists raw")
for t in TABLES:
    con.execute(f"create or replace table raw.{t} as select * from read_csv_auto('{(RAW / f'{t}.csv').as_posix()}')")
    n = con.execute(f"select count(*) from raw.{t}").fetchone()[0]
    print(f"raw.{t}: {n:,} rows")
con.close()
