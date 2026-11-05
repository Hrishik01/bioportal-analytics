"""
Simulates account-tier changes in the source system so the SCD2 snapshot has history to record.
Updates raw.customers in place (as the ERP would). Idempotent: it sets fixed target tiers.

Demo flow:
    dbt build --profiles-dir .                  # snapshot records every customer's starting tier
    python scripts/simulate_tier_changes.py     # 6 customers change tier in the source
    dbt snapshot --profiles-dir .               # closes the old rows, opens new ones

`python scripts/load_raw.py` resets raw.customers to the original CSV tiers.
"""
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[1]

# customer_id -> new tier (3 upgrades to preferred/strategic, 1 to strategic, 2 downgrades)
CHANGES = {
    17: "preferred",
    42: "strategic",
    108: "preferred",
    250: "strategic",
    3: "standard",
    401: "standard",
}

con = duckdb.connect(str(ROOT / "bioportal.duckdb"))
for customer_id, tier in CHANGES.items():
    old = con.execute("select account_tier from raw.customers where customer_id = ?", [customer_id]).fetchone()[0]
    con.execute("update raw.customers set account_tier = ? where customer_id = ?", [tier, customer_id])
    print(f"customer {customer_id}: {old} -> {tier}")
con.close()
