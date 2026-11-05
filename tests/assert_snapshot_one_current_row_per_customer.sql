-- SCD2 integrity: every customer has exactly one open row (dbt_valid_to is null).
-- Returns a row (= test fails) for any customer with zero or several open rows.
select customer_id, count(*) as open_rows
from {{ ref('snap_customers') }}
where dbt_valid_to is null
group by customer_id
having count(*) <> 1
