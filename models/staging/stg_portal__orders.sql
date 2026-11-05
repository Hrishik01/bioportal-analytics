select
    order_id,
    customer_id,
    cast(order_ts as timestamp)         as ordered_at,
    lower(status)                       as order_status,
    lower(channel)                      as order_channel
from {{ source('portal', 'orders') }}
