-- Business-rule test: no tracking event should happen before the customer signed up.
select e.event_id, e.customer_id, e.event_at, c.signed_up_on
from {{ ref('stg_portal__events') }} as e
inner join {{ ref('stg_portal__customers') }} as c
    on e.customer_id = c.customer_id
where cast(e.event_at as date) < c.signed_up_on
