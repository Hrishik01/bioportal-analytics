-- Line-level revenue math lives here, once, so nothing downstream re-derives it.
select
    oi.order_item_id,
    oi.order_id,
    oi.product_id,
    p.category                                              as product_category,
    oi.quantity,
    oi.quantity * oi.unit_price_at_sale                     as gross_line_amount,
    oi.quantity * oi.unit_price_at_sale * oi.discount_pct   as discount_amount,
    oi.quantity * oi.unit_price_at_sale * (1 - oi.discount_pct) as net_line_amount
from {{ ref('stg_portal__order_items') }} as oi
left join {{ ref('stg_portal__products') }} as p
    on oi.product_id = p.product_id
