"""
Proves the incremental fct_sessions behaves correctly on a second (and third) `dbt run`.

It injects fake events into raw.events, runs the incremental model, then compares the result
with a from-scratch full refresh. Cleans up after itself (removes the fake events, full-refreshes).

Run (venv active, after `dbt build`):  python scripts/verify_incremental_sessions.py
"""
import subprocess
from datetime import timedelta
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[1]
DB = str(ROOT / "bioportal.duckdb")
SIM = "evt_sim_%"


def dbt_run(*extra):
    cmd = ["dbt", "run", "--profiles-dir", ".", "-s", "fct_sessions", *extra]
    subprocess.run(cmd, cwd=ROOT, check=True, capture_output=True)


def query(sql, params=None):
    con = duckdb.connect(DB, read_only=True)
    try:
        return con.execute(sql, params or []).fetchall()
    finally:
        con.close()


def write(sql, params=None):
    con = duckdb.connect(DB)
    try:
        con.execute(sql, params or [])
    finally:
        con.close()


def table():
    return sorted(query("select * from marts.fct_sessions"))


def check(label, ok):
    print(f"{'PASS' if ok else 'FAIL'}  {label}")
    if not ok:
        raise SystemExit(1)


def add_event(i, customer_id, name, ts, product_id=None):
    write(
        "insert into raw.events (event_id, customer_id, event_name, event_ts, product_id, device_type, schema_version) "
        "values (?, ?, ?, ?, ?, 'desktop', 2.0)",
        [f"evt_sim_{i:03d}", customer_id, name, ts, product_id],
    )


# --- 0. clean baseline: no fake events, table built from scratch
write("delete from raw.events where event_id like ?", [SIM])
dbt_run("--full-refresh")
baseline = table()
n0 = len(baseline)

# --- 1. second run with no new data changes nothing
dbt_run()
check("re-run with no new events leaves the table identical (no duplicates)", table() == baseline)

# --- 2. new events: one brand-new session, one event that extends the newest existing session
watermark = query("select max(session_ended_at) from marts.fct_sessions")[0][0]
grow_id, grow_customer, grow_end, grow_events = query(
    "select session_id, customer_id, session_ended_at, event_count from marts.fct_sessions "
    "order by session_ended_at desc limit 1"
)[0]
new_customer = query("select customer_id from marts.fct_sessions where customer_id <> ? limit 1", [grow_customer])[0][0]
add_event(1, grow_customer, "product_viewed", grow_end.replace(microsecond=0) + timedelta(minutes=10), 1)
future = watermark + timedelta(days=2)
add_event(2, new_customer, "portal_login", future)
add_event(3, new_customer, "product_viewed", future + timedelta(minutes=1), 2)

dbt_run()
after_inc = table()
rows = {r[0]: r for r in after_inc}
check("a brand-new session is added (+1 row)", len(after_inc) == n0 + 1)
check("session_id stays unique", len({r[0] for r in after_inc}) == len(after_inc))
check(f"existing session {grow_id} grew in place (event_count {grow_events} -> {rows[grow_id][5]})",
      rows[grow_id][5] == grow_events + 1)
inc_snapshot = after_inc
dbt_run("--full-refresh")
check("incremental result == full refresh result", table() == inc_snapshot)

# --- 3. late event inside the lookback window that lands BEFORE an existing session
#        (renumbers that customer's later sessions: the nasty case)
late = query(
    """
    with s as (
        select customer_id, session_id, session_started_at,
               lag(session_ended_at) over (partition by customer_id order by session_started_at) as prev_end,
               row_number() over (partition by customer_id order by session_started_at desc) as rn
        from marts.fct_sessions
    )
    select customer_id, session_started_at from s
    where rn = 1 and prev_end is not null
      and session_started_at >= (select max(session_ended_at) - interval 20 hour from marts.fct_sessions)
      and prev_end < session_started_at - interval 4 hour
    limit 1
    """
)
check("found a customer to simulate a late-arriving event", len(late) == 1)
late_customer, late_start = late[0]
add_event(4, late_customer, "portal_login", late_start - timedelta(hours=2))
n_before_late = len(table())
dbt_run()
after_late = table()
check("late event adds one session", len(after_late) == n_before_late + 1)
dbt_run("--full-refresh")
check("incremental result == full refresh result (late event, renumbered sessions)", table() == after_late)

# --- 4. cleanup: drop fake events and rebuild so the project is back to baseline
write("delete from raw.events where event_id like ?", [SIM])
dbt_run("--full-refresh")
check("cleanup restores the original table", table() == baseline)
print("All incremental checks passed.")
