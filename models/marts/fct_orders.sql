select
    order_id,
    customer_id,
    ordered_at,
    order_date,
    order_status,
    order_channel,
    line_count,
    units,
    gross_revenue,
    discount_amount,
    net_revenue,
    -- revenue only counts when the order actually completed
    case when order_status = 'completed' then net_revenue else 0 end   as recognized_revenue,
    case when order_status = 'completed' then 1 else 0 end             as completed_order,
    -- guardrail numerator: orders that did not stick
    case when order_status in ('cancelled', 'returned') then 1 else 0 end as cancelled_or_returned_order,
    row_number() over (partition by customer_id order by ordered_at)   as customer_order_number,
    case when row_number() over (partition by customer_id order by ordered_at) = 1
         then true else false end                                       as is_first_order
from {{ ref('int_orders_enriched') }}
