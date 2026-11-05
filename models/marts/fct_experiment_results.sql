-- One row per experiment: control vs treatment conversion, lift, and a two-proportion z-test.
with by_variant as (

    select
        experiment_id,
        variant,
        count(*)                                    as n_customers,
        sum(converted)                              as n_converted,
        sum(converted) * 1.0 / count(*)             as conversion_rate,
        sum(revenue_in_window) / count(*)           as revenue_per_customer,
        sum(was_exposed) * 1.0 / count(*)           as exposure_rate
    from {{ ref('int_experiment_outcomes') }}
    group by experiment_id, variant

),

compared as (

    select
        t.experiment_id,
        c.n_customers                               as control_n,
        t.n_customers                               as treatment_n,
        c.conversion_rate                           as control_rate,
        t.conversion_rate                           as treatment_rate,
        t.conversion_rate - c.conversion_rate       as absolute_lift,
        (t.conversion_rate - c.conversion_rate) / nullif(c.conversion_rate, 0) as relative_lift,
        (c.n_converted + t.n_converted) * 1.0 / (c.n_customers + t.n_customers) as pooled_rate,
        c.revenue_per_customer                      as control_revenue_per_customer,
        t.revenue_per_customer                      as treatment_revenue_per_customer,
        t.exposure_rate                             as treatment_exposure_rate
    from by_variant as t
    inner join by_variant as c
        on t.experiment_id = c.experiment_id
        and t.variant = 'treatment'
        and c.variant = 'control'

),

tested as (

    select
        *,
        absolute_lift / nullif(
            sqrt(pooled_rate * (1 - pooled_rate) * (1.0 / control_n + 1.0 / treatment_n)),
            0
        ) as z_score
    from compared

)

select
    *,
    case when abs(z_score) > 1.96 then true else false end as is_significant_95
from tested
