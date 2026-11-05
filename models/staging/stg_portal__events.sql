-- Dedupe client-SDK retries: keep one row per event_id.
with source as (

    select * from {{ source('portal', 'events') }}

),

ranked as (

    select
        *,
        row_number() over (partition by event_id order by event_ts) as row_num
    from source

)

select
    event_id,
    customer_id,
    event_name,
    cast(event_ts as timestamp)         as event_at,
    product_id,
    device_type,                        -- null before tracking schema v2
    cast(schema_version as varchar)     as schema_version
from ranked
where row_num = 1
