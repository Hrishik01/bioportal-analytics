select
    experiment_id,
    customer_id,
    variant,
    cast(assigned_ts as timestamp)      as assigned_at
from {{ source('portal', 'experiment_assignments') }}
