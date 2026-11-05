with customers as (

    select * from {{ ref('stg_portal__customers') }}

),

order_rollup as (

    select
        customer_id,
        min(ordered_at)     as first_order_at,
        max(ordered_at)     as last_order_at,
        count(*)            as lifetime_orders,
        sum(net_revenue)    as lifetime_revenue
    from {{ ref('int_orders_enriched') }}
    where order_status = 'completed'
    group by customer_id

),

session_rollup as (

    select customer_id, count(distinct session_id) as lifetime_sessions
    from {{ ref('int_events_sessionized') }}
    group by customer_id

),

combined as (

    select
        c.customer_id,
        c.company_name,
        c.segment,
        c.region,
        c.account_tier,
        c.signed_up_on,
        o.first_order_at,
        o.last_order_at,
        coalesce(o.lifetime_orders, 0)      as lifetime_orders,
        coalesce(o.lifetime_revenue, 0)     as lifetime_revenue,
        coalesce(s.lifetime_sessions, 0)    as lifetime_sessions,
        {{ dbt.datediff('o.last_order_at', "cast('" ~ var('as_of_date') ~ "' as date)", 'day') }} as days_since_last_order
    from customers as c
    left join order_rollup as o on c.customer_id = o.customer_id
    left join session_rollup as s on c.customer_id = s.customer_id

)

select
    *,
    -- never-ordered customers have a null gap, so they fall through to false
    case when days_since_last_order <= 90 then true else false end as is_active_90d
from combined
