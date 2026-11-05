-- Required by the dbt Semantic Layer (MetricFlow): one row per day.
{{ config(materialized='table') }}

with days as (

    {{ dbt.date_spine('day', "cast('2024-01-01' as date)", "cast('2027-01-01' as date)") }}

)

select cast(date_day as date) as date_day
from days
