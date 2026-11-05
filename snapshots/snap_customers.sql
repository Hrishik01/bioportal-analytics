{# SCD Type 2 on customers: one row per customer per account_tier they have held.
   Reads the cleaned staging model (not raw) so casing noise like 'Preferred' vs
   'preferred' is not recorded as a tier change.
   dbt_valid_to is null on the current row. #}
{% snapshot snap_customers %}

{{
    config(
        target_schema='snapshots',
        unique_key='customer_id',
        strategy='check',
        check_cols=['account_tier'],
    )
}}

select
    customer_id,
    company_name,
    segment,
    region,
    account_tier
from {{ ref('stg_portal__customers') }}

{% endsnapshot %}
