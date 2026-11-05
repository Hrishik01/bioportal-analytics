-- Sample Ratio Mismatch check: with a 50/50 split, arm sizes should differ only by chance.
-- Returns a row (= test fails) if the gap is more than 3 standard deviations.
select
    experiment_id,
    control_n,
    treatment_n
from {{ ref('fct_experiment_results') }}
where abs(treatment_n - control_n) * 1.0 / sqrt(treatment_n + control_n) > 3
