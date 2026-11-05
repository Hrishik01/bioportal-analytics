"""
Generates a synthetic B2B bioprocess ordering-portal dataset (raw CSVs).

Think of these files as what an EL tool (Fivetran, Airbyte) would drop into your
warehouse: untouched, slightly messy, one table per source-system object.

Run:  python scripts/generate_raw_data.py
"""
from pathlib import Path

import numpy as np
import pandas as pd

SEED = 42
rng = np.random.default_rng(SEED)

OUT = Path(__file__).resolve().parents[1] / "data" / "raw"
OUT.mkdir(parents=True, exist_ok=True)

DATA_START = pd.Timestamp("2025-01-01")
DATA_END = pd.Timestamp("2026-06-30")
EXPERIMENT_START = pd.Timestamp("2026-04-01")
EXPERIMENT_ID = "exp_reorder_banner_01"
EVENT_SCHEMA_V2_START = pd.Timestamp("2025-09-01")  # device_type added in schema v2

# ---------------------------------------------------------------- customers
N_CUSTOMERS = 800
segments = rng.choice(["Biotech", "Pharma", "CDMO", "Academic"], N_CUSTOMERS, p=[0.35, 0.25, 0.15, 0.25])
regions = rng.choice(["NA", "EU", "APAC"], N_CUSTOMERS, p=[0.5, 0.3, 0.2])
tiers = rng.choice(["standard", "preferred", "strategic"], N_CUSTOMERS, p=[0.6, 0.3, 0.1])
signup_span = (pd.Timestamp("2026-02-28") - pd.Timestamp("2024-06-01")).days
signup_dates = pd.to_datetime("2024-06-01") + pd.to_timedelta(rng.integers(0, signup_span, N_CUSTOMERS), unit="D")
customers = pd.DataFrame(
    {
        "customer_id": np.arange(1, N_CUSTOMERS + 1),
        "company_name": [f"{s} Labs {i:03d}" for i, s in enumerate(segments, start=1)],
        "segment": segments,
        "region": regions,
        "signup_date": signup_dates.date,
        "account_tier": tiers,
    }
)
# realistic mess: inconsistent casing in a few rows (staging cleans it)
dirty = rng.random(N_CUSTOMERS) < 0.03
customers.loc[dirty, "region"] = customers.loc[dirty, "region"].str.lower()
customers.loc[dirty, "account_tier"] = customers.loc[dirty, "account_tier"].str.title()

# ----------------------------------------------------------------- products
categories = ["Chromatography", "Filtration", "Process Analytics", "Consumables"]
products = pd.DataFrame(
    {
        "product_id": np.arange(1, 41),
        "product_name": [f"{categories[i % 4]} Item {i + 1:02d}" for i in range(40)],
        "category": [categories[i % 4] for i in range(40)],
        "list_price": np.round(rng.lognormal(mean=5.0, sigma=0.8, size=40), 2),
    }
)

# ------------------------------------------------------------------- orders
monthly_rate = {"Pharma": 1.2, "Biotech": 0.8, "CDMO": 1.5, "Academic": 0.3}
order_rows = []
for c in customers.itertuples():
    start = max(pd.Timestamp(c.signup_date) + pd.Timedelta(days=1), DATA_START)
    days_active = (DATA_END - start).days
    if days_active <= 0:
        continue
    n = rng.poisson(monthly_rate[c.segment] * days_active / 30)
    for off in rng.integers(0, days_active * 24 * 60, n):
        ts = start + pd.Timedelta(minutes=int(off))
        ts = ts.replace(hour=int(rng.integers(7, 19)), minute=int(rng.integers(0, 60)), second=int(rng.integers(0, 60)))
        order_rows.append((c.customer_id, ts))

# ---------------------------------------------------- experiment assignment
# Treatment customers see a "time to reorder?" banner and place slightly more orders.
eligible = customers[pd.to_datetime(customers["signup_date"]) < EXPERIMENT_START]["customer_id"].to_numpy()
variants = rng.choice(["control", "treatment"], len(eligible))
assigned_at = EXPERIMENT_START + pd.to_timedelta(rng.integers(0, 7 * 24 * 60, len(eligible)), unit="m")
assignments = pd.DataFrame(
    {
        "experiment_id": EXPERIMENT_ID,
        "customer_id": eligible,
        "variant": variants,
        "assigned_ts": assigned_at,
    }
)
for a in assignments.itertuples():
    if a.variant == "treatment" and rng.random() < 0.12:  # the "true" effect: an extra order within 14 days
        ts = a.assigned_ts + pd.Timedelta(minutes=int(rng.integers(60, 14 * 24 * 60 - 60)))
        ts = ts.replace(hour=int(rng.integers(7, 19)))
        order_rows.append((a.customer_id, ts))

order_rows.sort(key=lambda r: r[1])
orders = pd.DataFrame(order_rows, columns=["customer_id", "order_ts"])
orders.insert(0, "order_id", np.arange(1, len(orders) + 1))
orders["status"] = rng.choice(["completed", "cancelled", "returned"], len(orders), p=[0.93, 0.04, 0.03])
orders["channel"] = rng.choice(["portal", "sales_rep"], len(orders), p=[0.7, 0.3])
orders.loc[rng.random(len(orders)) < 0.02, "status"] = "COMPLETED"  # more mess

# -------------------------------------------------------------- order items
discount_by_tier = {"standard": 0.0, "preferred": 0.05, "strategic": 0.10}
tier_lookup = customers.assign(account_tier=customers["account_tier"].str.lower()).set_index("customer_id")["account_tier"]
price_lookup = products.set_index("product_id")["list_price"]
item_rows = []
item_id = 1
for o in orders.itertuples():
    n_items = int(rng.integers(1, 6))
    chosen = rng.choice(products["product_id"], n_items, replace=False)
    base_disc = discount_by_tier[tier_lookup[o.customer_id]]
    for pid in chosen:
        qty = int(min(1 + rng.geometric(0.25), 40))
        disc = round(base_disc + (0.02 if rng.random() < 0.1 else 0.0), 4)
        price = round(float(price_lookup[pid]) * rng.uniform(0.97, 1.03), 2)  # price at time of sale drifts a bit
        item_rows.append((item_id, o.order_id, int(pid), qty, price, disc))
        item_id += 1
order_items = pd.DataFrame(
    item_rows, columns=["order_item_id", "order_id", "product_id", "quantity", "unit_price_at_sale", "discount_pct"]
)

# ------------------------------------------------------------------- events
event_rows = []


def device_for(ts):
    return None if ts < EVENT_SCHEMA_V2_START else str(rng.choice(["desktop", "mobile", "tablet"], p=[0.8, 0.1, 0.1]))


def add_event(cid, name, ts, pid=None, device=None):
    event_rows.append((cid, name, ts, pid, device, "1.0" if ts < EVENT_SCHEMA_V2_START else "2.0"))


items_by_order = order_items.groupby("order_id")["product_id"].apply(list).to_dict()
for o in orders[orders["channel"] == "portal"].itertuples():
    dev = device_for(o.order_ts)
    t = o.order_ts - pd.Timedelta(minutes=int(rng.integers(8, 28)))
    add_event(o.customer_id, "portal_login", t, None, dev)
    for pid in items_by_order[o.order_id]:
        t += pd.Timedelta(seconds=int(rng.integers(20, 120)))
        add_event(o.customer_id, "product_viewed", t, pid, dev)
        t += pd.Timedelta(seconds=int(rng.integers(10, 60)))
        add_event(o.customer_id, "cart_item_added", t, pid, dev)
    add_event(o.customer_id, "order_placed", o.order_ts, None, dev)

# browse-only sessions (no purchase); some add to cart, some request a quote
for c in customers.itertuples():
    start = max(pd.Timestamp(c.signup_date) + pd.Timedelta(days=1), DATA_START)
    days_active = (DATA_END - start).days
    if days_active <= 0:
        continue
    for _ in range(rng.poisson(days_active / 30 * 1.2)):
        t = start + pd.Timedelta(minutes=int(rng.integers(0, days_active * 24 * 60)))
        t = t.replace(hour=int(rng.integers(7, 19)))
        dev = device_for(t)
        add_event(c.customer_id, "portal_login", t, None, dev)
        for _ in range(int(rng.integers(1, 5))):
            t += pd.Timedelta(seconds=int(rng.integers(20, 200)))
            pid = int(rng.integers(1, 41))
            add_event(c.customer_id, "product_viewed", t, pid, dev)
            if rng.random() < 0.15:
                t += pd.Timedelta(seconds=30)
                add_event(c.customer_id, "cart_item_added", t, pid, dev)
        if rng.random() < 0.15:
            t += pd.Timedelta(seconds=45)
            add_event(c.customer_id, "quote_requested", t, None, dev)

# banner exposure for ~85% of treatment customers, shortly after assignment
for a in assignments[assignments["variant"] == "treatment"].itertuples():
    if rng.random() < 0.85:
        t = a.assigned_ts + pd.Timedelta(hours=int(rng.integers(1, 72)))
        add_event(a.customer_id, "reorder_banner_viewed", t, None, device_for(t))

events = pd.DataFrame(
    event_rows, columns=["customer_id", "event_name", "event_ts", "product_id", "device_type", "schema_version"]
).sort_values("event_ts", kind="stable")
events.insert(0, "event_id", [f"evt_{i:07d}" for i in range(1, len(events) + 1)])
events["product_id"] = events["product_id"].astype("Int64")
# realistic mess: ~0.5% duplicated events (client SDK retries)
dupes = events.sample(frac=0.005, random_state=SEED)
events = pd.concat([events, dupes]).sort_values(["event_ts", "event_id"], kind="stable")

# -------------------------------------------------------------------- write
customers.to_csv(OUT / "customers.csv", index=False)
products.to_csv(OUT / "products.csv", index=False)
orders.to_csv(OUT / "orders.csv", index=False)
order_items.to_csv(OUT / "order_items.csv", index=False)
events.to_csv(OUT / "events.csv", index=False)
assignments.to_csv(OUT / "experiment_assignments.csv", index=False)

print(
    f"customers={len(customers):,} products={len(products):,} orders={len(orders):,} "
    f"order_items={len(order_items):,} events={len(events):,} assignments={len(assignments):,}"
)

# quick sanity readout of the experiment (so you know what the dbt model should roughly say)
cutoff = assignments.assign(window_end=assignments["assigned_ts"] + pd.Timedelta(days=14))
merged = cutoff.merge(orders[["customer_id", "order_ts", "status"]], on="customer_id", how="left")
merged["hit"] = (
    (merged["order_ts"] >= merged["assigned_ts"])
    & (merged["order_ts"] < merged["window_end"])
    & (merged["status"].str.lower() == "completed")
)
conv = merged.groupby(["customer_id", "variant"])["hit"].any().reset_index().groupby("variant")["hit"].agg(["mean", "count"])
print(conv)
