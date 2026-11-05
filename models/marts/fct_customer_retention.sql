-- Cohort retention. Grain: one row per (signup-month cohort, months since signup 0-6).
-- Retained = customer placed at least one COMPLETED order in that calendar month.
-- Month 0 is the signup month. A month we can't observe gets a NULL rate, not 0, so cohorts
-- don't look like they churned: that means months after `as_of_date`, and months before
-- the first month of order history (the raw data starts in 2025-01).
with customers as (

    select
        customer_id,
        {{ dbt.date_trunc('month', 'signed_up_on') }} as cohort_month
    from {{ ref('dim_customers') }}

),

-- distinct (customer, order month) pairs: ordering twice in a month still counts once
customer_order_months as (

    select distinct
        customer_id,
        {{ dbt.date_trunc('month', 'order_date') }} as order_month
    from {{ ref('fct_orders') }}
    where order_status = 'completed'

),

order_history as (

    select min(order_month) as first_order_month from customer_order_months

),

cohort_sizes as (

    select cohort_month, count(*) as cohort_size
    from customers
    group by cohort_month

),

-- offsets 0..6 (generate_series gives 1..7)
offsets as (

    select generated_number - 1 as months_since_signup
    from ({{ dbt_utils.generate_series(7) }}) as s

),

cohort_periods as (

    select
        c.cohort_month,
        c.cohort_size,
        o.months_since_signup,
        {{ dbt.dateadd('month', 'o.months_since_signup', 'c.cohort_month') }} as period_month
    from cohort_sizes as c
    cross join offsets as o

),

retained as (

    select
        c.cohort_month,
        {{ dbt.datediff('c.cohort_month', 'm.order_month', 'month') }} as months_since_signup,
        count(distinct c.customer_id)                                     as retained_customers
    from customers as c
    inner join customer_order_months as m
        on c.customer_id = m.customer_id
    group by 1, 2

)

select
    p.cohort_month,
    p.months_since_signup,
    p.cohort_size,
    coalesce(r.retained_customers, 0)                                      as retained_customers,
    case
        when p.period_month <= cast('{{ var("as_of_date") }}' as date)
            and p.period_month >= h.first_order_month
        then coalesce(r.retained_customers, 0) * 1.0 / p.cohort_size
    end                                                                    as retention_rate
from cohort_periods as p
cross join order_history as h
left join retained as r
    on p.cohort_month = r.cohort_month
    and p.months_since_signup = r.months_since_signup
