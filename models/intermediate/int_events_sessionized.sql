-- Sessionization: a new session starts when a customer's gap between events
-- exceeds `session_timeout_minutes` (default 30).
with events as (

    select * from {{ ref('stg_portal__events') }}

),

with_previous as (

    select
        *,
        lag(event_at) over (partition by customer_id order by event_at, event_id) as previous_event_at
    from events

),

flagged as (

    select
        *,
        case
            when previous_event_at is null then 1
            when {{ dbt.datediff('previous_event_at', 'event_at', 'second') }} > {{ var('session_timeout_minutes') * 60 }} then 1
            else 0
        end as is_new_session
    from with_previous

),

numbered as (

    select
        *,
        sum(is_new_session) over (
            partition by customer_id
            order by event_at, event_id
            rows between unbounded preceding and current row
        ) as session_number
    from flagged

)

select
    event_id,
    customer_id,
    event_name,
    event_at,
    product_id,
    device_type,
    session_number,
    cast(customer_id as varchar) || '-' || cast(session_number as varchar) as session_id
from numbered
