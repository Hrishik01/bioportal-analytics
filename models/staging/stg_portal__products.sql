select
    product_id,
    product_name,
    category,
    cast(list_price as decimal(12, 2))  as list_price
from {{ source('portal', 'products') }}
