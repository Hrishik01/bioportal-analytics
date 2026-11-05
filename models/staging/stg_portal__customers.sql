select
    customer_id,
    trim(company_name)                  as company_name,
    segment,
    upper(region)                       as region,
    cast(signup_date as date)           as signed_up_on,
    lower(account_tier)                 as account_tier
from {{ source('portal', 'customers') }}
