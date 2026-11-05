# Bioportal Analytics — a dbt project

All data is synthetic.

An analytics-engineering portfolio project: raw B2B ordering-portal data → tested, documented dbt models → a semantic layer of governed metrics → an A/B test readout.

It runs entirely on your laptop (DuckDB — no warehouse account needed).

## What's in it

| Layer | What happens | Models |
|---|---|---|
| Raw (EL) | CSVs loaded untouched into `raw` schema | `scripts/load_raw.py` |
| Staging | Rename, cast, clean, dedupe — one model per source table | `stg_portal__*` |
| Intermediate | Reusable business logic: revenue math, sessionization, experiment outcomes | `int_*` |
| Marts | Analyst-facing facts and dimensions | `dim_customers`, `dim_products`, `fct_orders`, `fct_sessions` (incremental), `fct_experiment_results`, `fct_customer_retention` |
| Snapshots | SCD Type 2 history of customer `account_tier` | `snap_customers` |
| Semantic layer | Metrics defined once: `revenue`, `order_count`, `average_order_value`, `units`, `all_orders`, `cancelled_or_returned_orders`, `cancellation_rate` | `models/marts/_semantic.yml` |

Plus: generic tests, singular (custom) tests, a unit test, a macro override, dbt packages, analyses, a tracking plan, and an experiment design doc.

## Run it

Needs **Python 3.12** (3.13 can't install the pinned `dbt-metricflow`; 3.10–3.12 work).

```bash
python3.12 -m venv .venv && source .venv/bin/activate     # Windows: .venv\Scripts\activate
pip install -r requirements.txt

python scripts/generate_raw_data.py     # creates data/raw/*.csv (seeded, so reproducible)
python scripts/load_raw.py              # loads them into bioportal.duckdb (schema: raw)

dbt deps  --profiles-dir .
dbt build --profiles-dir .              # models + tests + unit test + snapshot, in dependency order
dbt docs generate --profiles-dir .      # then `dbt docs serve --profiles-dir .` for the lineage graph
```

`pip` prints "dbt-metricflow does not provide the extra 'duckdb'" — harmless; the DuckDB adapter comes from `dbt-duckdb`.

`packages.yml` pulls `dbt_utils` 1.3.0 from its GitHub tag instead of the dbt Hub (same release). That keeps `dbt deps` working where `hub.getdbt.com` is blocked. To use the Hub instead: `package: dbt-labs/dbt_utils`, `version: 1.3.0`.

Query the semantic layer (set `DBT_PROFILES_DIR=.` once, or run from this folder with the profile in place):

```bash
export DBT_PROFILES_DIR=.
mf validate-configs
mf query --metrics revenue --group-by metric_time__month,customer__segment
mf query --metrics average_order_value --group-by customer__region
mf query --metrics cancellation_rate --group-by customer__segment
```

Read the experiment result:

```bash
python -c "import duckdb; print(duckdb.connect('bioportal.duckdb').sql('select * from marts.fct_experiment_results').df().T)"
```

Compile and run an analysis (these aren't materialised):

```bash
dbt compile --profiles-dir .
python -c "import duckdb; print(duckdb.connect('bioportal.duckdb').sql(open('target/compiled/bioportal_analytics/analyses/portal_funnel.sql').read()).df())"
```

## Results (as built from a clean state)

`dbt build`: **96 of 96 pass** — 17 models (10 views, 6 tables, 1 incremental) + 1 snapshot + 77 data tests (72 generic, 5 singular) + 1 unit test. No warnings, no skips.

Experiment `exp_reorder_banner_01` (14-day window, intent-to-treat):

| | Control | Treatment |
|---|---|---|
| Customers | 400 | 400 |
| Conversion | 29.75% | 39.75% |
| Absolute lift | | +10.0 pts (+33.6% relative) |
| z-score | | 2.97 → significant at 95% |
| Revenue per customer | $930.56 | $1,501.82 |
| Treatment exposure rate | | 86% |
| Orders placed in window | 152 | 209 |
| Cancellation rate (guardrail) | 3.95% | 3.35% |
| Guardrail breached? (limit +2 pts) | | **No** |

Decision rule from `docs/experiment_design.md`: significant primary metric and no guardrail breach → ship. Caveat to say out loud: the guardrail rests on only 152 and 209 orders, so it can't rule out a small increase in cancellations. The primary metric is powered for a 10-point lift (n = 400 per arm), the guardrail is not.

How the checks were validated rather than assumed:
- The SRM test sees exactly 400/400 (statistic 0), so it passes trivially on this data. Its logic was checked on synthetic splits: silent at 390/410, fires at 450/350 and 500/300.
- The revenue reconciliation test compares `fct_orders` with `int_order_lines`; the same total ($25,493,519.25) was recomputed independently from `raw.order_items`.
- `mf query --metrics revenue --group-by metric_time__month,customer__segment` matches `analyses/revenue_by_segment_month.sql` on all 72 month × segment rows (max difference 0.0).

## Extensions

**Cohort retention — `fct_customer_retention`.** Grain: signup-month cohort × months 0–6 after signup. Retained = at least one *completed* order in that calendar month (month 0 = signup month). Months that can't be observed give a NULL rate, not 0: months after `as_of_date`, and months before the first month of order data (the synthetic orders start in 2025-01, so 2024 cohorts would otherwise show a fake 0%). Tests: unique grain, value ranges, `retained <= cohort_size`, and a singular test that cohort sizes add up to `dim_customers`.

**SCD2 snapshot — `snap_customers`.** Tracks `account_tier` (check strategy) from the cleaned staging model, so casing noise isn't recorded as a tier change. To see history accumulate:

```bash
python scripts/simulate_tier_changes.py     # changes 6 customers' tiers in raw.customers
dbt snapshot --profiles-dir .               # 800 rows -> 806 (6 closed, 6 opened); 800 current
```

`python scripts/load_raw.py` resets the source tiers.

**Guardrail metric.** `cancellation_rate` = (cancelled + returned orders) ÷ all orders, defined once in the semantic layer (overall 6.6%). `fct_experiment_results` adds `control_cancellation_rate`, `treatment_cancellation_rate`, `cancellation_rate_lift` and `is_guardrail_breached`. The breach limit is the `guardrail_max_cancellation_increase` var (0.02 = 2 points). That margin is my choice; set it before the experiment, not after.

**Incremental `fct_sessions`** (`unique_key = session_id`, `delete+insert`). Each run re-aggregates only sessions with an event in the last `sessions_lookback_hours` (24) before the newest loaded session, always from *all* of a session's events, so a session that grows is updated in place. Prove it:

```bash
python scripts/verify_incremental_sessions.py
```

It checks that a no-op re-run changes nothing, that new events add a session and extend an existing one in place, and that a late-arriving event inside the lookback (which renumbers a customer's later sessions) still equals a full refresh. It cleans up after itself. Events that arrive later than the lookback need `dbt run --full-refresh -s fct_sessions`.

## What I fixed on the way

| What broke | Why the fix is right |
|---|---|
| Unit test `'var' is undefined` | dbt 1.8 pre-renders a model's SQL for unit tests with a context that has no `var()`, even with `overrides: vars`. The timeout is now read through a `session_timeout_seconds()` macro, which can call `var()`. The test also pins `session_timeout_minutes: 30`. |
| Bare boolean expressions (`x = 1 as flag`, `coalesce(a <= 90, false)`) | Worked on DuckDB but aren't portable. Now `case when … then true else false end`. |
| `dbt deps` blocked (`hub.getdbt.com` not reachable here) | Same dbt_utils release, pulled from its git tag. |
| `requirements.txt` pins | Unchanged. They install fine on Python 3.12 (not 3.13). |

Nothing else needed fixing: the date macros, `metricflow_time_spine` and the semantic-layer YAML all worked as written, and no test failed because of bad data.

## Things to try

1. Break a test on purpose (add a bad `order_status` row to `raw.orders`) and watch `dbt build` stop downstream models.
2. Change `session_timeout_minutes` to 15 in `dbt_project.yml` and see how session counts move (then `dbt run --full-refresh -s fct_sessions`, since the incremental table keeps old sessions).
3. Change `guardrail_max_cancellation_increase` to `-0.01` and watch `is_guardrail_breached` flip.

## What I'd change at warehouse scale

- **Sessionization is the bottleneck, not `fct_sessions`.** `int_events_sessionized` is a view that window-scans every event on each run. At billions of events I'd make it incremental too, partitioned by event date, and carry each customer's last open session forward.
- **Stable session IDs.** `customer_id-session_number` shifts when a late event lands before existing sessions. Better: a hash of `customer_id` + the session's first `event_at`, so IDs never renumber.
- **Late data.** Use a load timestamp (`_loaded_at`) instead of event time to pick up changed rows, and keep the lookback as a safety net. Run `--full-refresh` on a schedule.
- **Incremental strategy per warehouse.** `delete+insert` is fine on DuckDB, Snowflake and Postgres; on BigQuery I'd use `merge` or `insert_overwrite` with partitioning.
- **Materialization.** Marts as tables are fine here. At scale, `fct_orders` and `fct_sessions` should be partitioned/clustered by date, and the staging views would become tables for the biggest sources.
- **Snapshots.** Snapshot the raw source table (or a CDC feed) on a schedule, not a transformed model. With the check strategy, `dbt snapshot` must run on every change cadence you care about; change history between runs is lost.
- **Experiments.** Compute the z-test in a BI/stats layer for many experiments, use sequential or CUPED methods, and treat the guardrail with a proper non-inferiority test rather than a fixed margin.
- **Semantic layer.** Keep the MetricFlow YAML, add saved queries and exports, and run `mf validate-configs` in CI along with `dbt build --select state:modified+`.
- **Testing and CI.** Slim CI with `--defer`, `dbt test` severities (`warn` vs `error`), source freshness checks, and a data-diff on PRs.

## Docs
- `docs/tracking_plan.md` — event instrumentation and schema design
- `docs/experiment_design.md` — hypothesis, sizing, analysis, decision rule

> Data is synthetic. Domain is modelled on B2B life-sciences commercial operations.
