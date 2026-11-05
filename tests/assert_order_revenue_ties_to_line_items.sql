-- Reconciliation: order-level revenue must equal the sum of its line items.
-- Returns a row (= test fails) if the totals differ by more than a rounding cent.
with orders as (select sum(net_revenue) as total from {{ ref('fct_orders') }}),
     lines  as (select sum(net_line_amount) as total from {{ ref('int_order_lines') }})
select orders.total as order_total, lines.total as line_total
from orders cross join lines
where abs(orders.total - lines.total) > 0.01
