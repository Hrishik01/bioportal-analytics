{{
    config(
        materialized='incremental',
        unique_key='session_id',
        incremental_strategy='delete+insert'
    )
}}

-- Incremental: on later runs, only re-aggregate sessions that have an event within the lookback
-- window before the newest session already loaded. A session is rebuilt from ALL of its events
-- (never from a partial slice), and delete+insert on session_id replaces the old row, so
-- a session that grows (new event within 30 min) is updated in place, not duplicated.
-- Events older than the lookback arriving late need `dbt run --full-refresh -s fct_sessions`.
with events as (

    select * from {{ ref('int_events_sessionized') }}

),

{% if is_incremental() %}
touched_sessions as (

    select distinct session_id
    from events
    where event_at >= (
        select {{ dbt.dateadd('hour', -1 * var('sessions_lookback_hours'), 'max(session_ended_at)') }}
        from {{ this }}
    )

),

events_to_aggregate as (

    select e.*
    from events as e
    inner join touched_sessions as t
        on e.session_id = t.session_id

)
{% else %}
events_to_aggregate as (

    select * from events

)
{% endif %}

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
from events_to_aggregate
group by session_id, customer_id
