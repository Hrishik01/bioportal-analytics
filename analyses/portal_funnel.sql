-- Ad-hoc analysis (compiled by dbt, not materialised): portal funnel by device.
-- Compile with `dbt compile -s portal_funnel`, then run the SQL from target/compiled/.
select
    coalesce(device_type, 'unknown (schema v1)')                       as device,
    count(*)                                                            as sessions,
    avg(added_to_cart)                                                  as pct_added_to_cart,
    avg(placed_order)                                                   as pct_placed_order,
    sum(placed_order) * 1.0 / nullif(sum(added_to_cart), 0)             as cart_to_order_rate
from {{ ref('fct_sessions') }}
group by 1
order by sessions desc
