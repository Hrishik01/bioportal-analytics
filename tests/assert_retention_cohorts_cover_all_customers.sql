-- Reconciliation: month-0 cohort sizes must add up to every customer in dim_customers.
-- Returns a row (= test fails) if any customer is missing from, or double-counted in, a cohort.
with cohorts as (
    select sum(cohort_size) as total from {{ ref('fct_customer_retention') }} where months_since_signup = 0
),
customers as (
    select count(*) as total from {{ ref('dim_customers') }}
)
select cohorts.total as cohort_total, customers.total as customer_total
from cohorts cross join customers
where cohorts.total <> customers.total
