-- One row per (experiment, customer): did they place a completed order within the
-- outcome window after being assigned? Intent-to-treat: everyone assigned counts,
-- whether or not they actually saw the banner.
with assignments as (

    select * from {{ ref('stg_portal__experiment_assignments') }}

),

completed_orders as (

    select * from {{ ref('int_orders_enriched') }}
    where order_status = 'completed'

),

exposures as (

    select customer_id, min(event_at) as first_exposed_at
    from {{ ref('stg_portal__events') }}
    where event_name = 'reorder_banner_viewed'
    group by customer_id

),

joined as (

    select
        a.experiment_id,
        a.customer_id,
        a.variant,
        a.assigned_at,
        count(o.order_id)                       as orders_in_window,
        coalesce(sum(o.net_revenue), 0)         as revenue_in_window
    from assignments as a
    left join completed_orders as o
        on a.customer_id = o.customer_id
        and o.ordered_at >= a.assigned_at
        and o.ordered_at < {{ dbt.dateadd('day', var('experiment_window_days'), 'a.assigned_at') }}
    group by a.experiment_id, a.customer_id, a.variant, a.assigned_at

)

select
    j.*,
    case when j.orders_in_window > 0 then 1 else 0 end as converted,
    case when e.first_exposed_at is not null then 1 else 0 end as was_exposed
from joined as j
left join exposures as e
    on j.customer_id = e.customer_id
