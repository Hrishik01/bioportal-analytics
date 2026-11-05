# Event tracking plan — Bioportal

The contract between whoever instruments the portal (engineers) and whoever consumes the data (analytics). If an event isn't in this doc, it doesn't ship. If it changes, this doc changes first.

## Principles

1. **Name events `object_action`, snake_case, past tense** — `product_viewed`, not `ViewProduct` or `click_product_btn`. Names describe what the user did, not which button they hit.
2. **Few events, rich properties.** One `product_viewed` event with a `product_id` property beats 40 events like `viewed_filter_a`.
3. **Every event carries the same envelope** (below). No exceptions — this is what makes sessionization and joins possible.
4. **IDs, not labels.** Send `product_id`, not `product_name`. Names change; IDs don't. Join to dimensions in dbt.
5. **Additive changes are free, breaking changes bump `schema_version`.**

## Envelope (on every event)

| Field | Type | Required | Notes |
|---|---|---|---|
| event_id | string | yes | Unique per event, generated client-side. Used to dedupe SDK retries. |
| customer_id | integer | yes | Logged-in account. Anonymous traffic is out of scope for v1. |
| event_name | string | yes | From the catalog below. |
| event_ts | timestamp (UTC) | yes | Client time, UTC. Never local time. |
| schema_version | string | yes | `1.0` or `2.0`. |
| device_type | string | v2+ | `desktop`, `mobile`, `tablet`. Added in v2 (nullable for v1 history). |

## Event catalog

| Event | Fires when | Extra properties | Used for |
|---|---|---|---|
| portal_login | Customer signs in | — | Session start, DAU/WAU |
| product_viewed | Product detail page loads | product_id (required) | Funnel top, product interest |
| cart_item_added | Item added to cart | product_id (required) | Funnel middle |
| quote_requested | Customer submits a quote form | — | Sales-assisted pipeline |
| order_placed | Order submitted | — | Funnel bottom; reconcile with `fct_orders` |
| reorder_banner_viewed | Reorder banner enters viewport | — | Experiment exposure (`exp_reorder_banner_01`) |

## Versioning

- **v1.0 → v2.0 (2025-09-01):** added `device_type`. Additive, but history before the cutover is null — the funnel analysis labels that "unknown (schema v1)" rather than guessing.
- Breaking change examples (require a version bump + migration note): renaming an event, changing a property's type, changing what "fires when" means.

## How the plan is enforced downstream (in this dbt project)

| Plan rule | dbt check |
|---|---|
| `event_id` unique | `unique` test on `stg_portal__events`; staging dedupes retries |
| Only catalog events exist | `accepted_values` on `event_name` — a new unregistered event fails the build |
| `customer_id` always present | `not_null` + `relationships` to customers |
| Timestamps sane | `assert_events_not_before_signup` singular test |

## Open questions a real team would resolve

- Anonymous (pre-login) tracking and identity stitching.
- Server-side vs client-side firing for `order_placed` (server is more reliable; client carries device context).
- PII policy: no names/emails in event properties.
