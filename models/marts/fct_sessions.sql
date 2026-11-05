select
    session_id,
    customer_id,
    min(event_at)                                                       as session_started_at,
    max(event_at)                                                       as session_ended_at,
    {{ dbt.datediff('min(event_at)', 'max(event_at)', 'second') }}      as session_duration_seconds,
    count(*)                                                            as event_count,
    count(case when event_name = 'product_viewed' then 1 end)           as product_views,
    max(case when event_name = 'cart_item_added'  then 1 else 0 end)    as added_to_cart,
    max(case when event_name = 'quote_requested'  then 1 else 0 end)    as requested_quote,
    max(case when event_name = 'order_placed'     then 1 else 0 end)    as placed_order,
    max(device_type)                                                    as device_type
from {{ ref('int_events_sessionized') }}
group by session_id, customer_id
