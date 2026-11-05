select
    order_item_id,
    order_id,
    product_id,
    quantity,
    cast(unit_price_at_sale as decimal(12, 2))  as unit_price_at_sale,
    cast(discount_pct as decimal(5, 4))         as discount_pct
from {{ source('portal', 'order_items') }}
