with orders as (

    select * from {{ ref('stg_portal__orders') }}

),

line_rollup as (

    select
        order_id,
        count(*)                as line_count,
        sum(quantity)           as units,
        sum(gross_line_amount)  as gross_revenue,
        sum(discount_amount)    as discount_amount,
        sum(net_line_amount)    as net_revenue
    from {{ ref('int_order_lines') }}
    group by order_id

)

select
    o.order_id,
    o.customer_id,
    o.ordered_at,
    cast(o.ordered_at as date)              as order_date,
    o.order_status,
    o.order_channel,
    coalesce(l.line_count, 0)               as line_count,
    coalesce(l.units, 0)                    as units,
    coalesce(l.gross_revenue, 0)            as gross_revenue,
    coalesce(l.discount_amount, 0)          as discount_amount,
    coalesce(l.net_revenue, 0)              as net_revenue
from orders as o
left join line_rollup as l
    on o.order_id = l.order_id
