# Bioportal Analytics — a dbt project

An analytics-engineering portfolio project: raw B2B ordering-portal data → tested, documented dbt models → a semantic layer of governed metrics → an A/B test readout.

It runs entirely on your laptop (DuckDB — no warehouse account needed).

## What's in it

| Layer | What happens | Models |
|---|---|---|
| Raw (EL) | CSVs loaded untouched into `raw` schema | `scripts/load_raw.py` |
| Staging | Rename, cast, clean, dedupe — one model per source table | `stg_portal__*` |
| Intermediate | Reusable business logic: revenue math, sessionization, experiment outcomes | `int_*` |
| Marts | Analyst-facing facts and dimensions | `dim_customers`, `dim_products`, `fct_orders`, `fct_sessions`, `fct_experiment_results` |
| Semantic layer | Metrics defined once: `revenue`, `order_count`, `average_order_value`, `units` | `models/marts/_semantic.yml` |

Plus: generic tests, singular (custom) tests, a unit test, a macro override, dbt packages, analyses, a tracking plan, and an experiment design doc.

## Run it

```bash
python -m venv .venv && source .venv/bin/activate     # Windows: .venv\Scripts\activate
pip install -r requirements.txt

python scripts/generate_raw_data.py     # creates data/raw/*.csv
python scripts/load_raw.py              # loads them into bioportal.duckdb (schema: raw)

dbt deps  --profiles-dir .
dbt build --profiles-dir .              # runs models + tests + unit tests, in dependency order
dbt docs generate --profiles-dir . && dbt docs serve --profiles-dir .   # lineage graph in the browser
```

Query the semantic layer:

```bash
mf query --metrics revenue --group-by metric_time__month,customer__segment
mf query --metrics average_order_value --group-by customer__region
```

Read the experiment result:

```bash
python -c "import duckdb; print(duckdb.connect('bioportal.duckdb').sql('select * from marts.fct_experiment_results').df().T)"
```

Expected (roughly): control ≈ 30% conversion, treatment ≈ 40%, z ≈ 3 — significant. The generator planted that effect, so if your model says something very different, there's a bug to find.

## Things to try once it runs (this is where the learning is)

1. Break a test on purpose (add a bad `order_status` row to `raw.orders`) and watch `dbt build` stop downstream models.
2. Change `session_timeout_minutes` to 15 in `dbt_project.yml` and see how session counts move.
3. Add a new model: monthly cohort retention off `fct_orders`.
4. Add a snapshot (SCD Type 2) on `customers` to track tier changes.
5. Add a guardrail metric (cancellation rate) to the semantic layer and the experiment readout.

## Docs
- `docs/tracking_plan.md` — event instrumentation and schema design
- `docs/experiment_design.md` — hypothesis, sizing, analysis, decision rule

> Data is synthetic. Domain is modelled on B2B life-sciences commercial operations.
