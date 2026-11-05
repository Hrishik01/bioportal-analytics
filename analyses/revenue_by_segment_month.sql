-- The same question the semantic layer answers, written by hand — compare the results with:
--   mf query --metrics revenue --group-by metric_time__month,customer__segment
select
    date_trunc('month', o.order_date)   as month,
    c.segment,
    sum(o.recognized_revenue)           as revenue
from {{ ref('fct_orders') }} as o
inner join {{ ref('dim_customers') }} as c on o.customer_id = c.customer_id
group by 1, 2
order by 1, 2
