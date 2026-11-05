# Experiment design — Reorder banner (`exp_reorder_banner_01`)

## Hypothesis
Showing customers a "Time to reorder?" banner will increase the share who place an order within 14 days.

## Setup
| Item | Choice |
|---|---|
| Unit of randomization | Customer (not session — one customer should see one experience) |
| Split | 50 / 50, control vs treatment |
| Eligibility | Customers signed up before the experiment start |
| Assignment | Logged in `experiment_assignments` at assignment time |
| Exposure event | `reorder_banner_viewed` (treatment only) |

## Metrics
- **Primary:** conversion — placed ≥ 1 completed order within 14 days of assignment.
- **Secondary:** revenue per assigned customer over the same window.
- **Guardrail (a real team would add):** cancellation/return rate, so we don't "win" by pushing low-quality orders.

## Sizing (before launch, not after)
Two-proportion test, 5% significance, 80% power. Baseline conversion ≈ 30%, minimum effect worth detecting ≈ +10 points:

    n per arm ≈ (1.96 + 0.84)² × [p1(1−p1) + p2(1−p2)] / (p2 − p1)²
              ≈ 7.84 × (0.21 + 0.24) / 0.10² ≈ 350

We have 400 per arm, so we're adequately powered for a 10-point lift and *underpowered* for anything much smaller. Say that out loud in the readout.

## Analysis
- **Intent-to-treat:** everyone assigned counts in their arm, whether or not they saw the banner (`int_experiment_outcomes`). Only ~85% of treatment customers were exposed, so ITT understates the effect on people who actually saw it — and that's the honest number to ship on.
- **Test:** two-proportion z-test, computed in `fct_experiment_results`.
- **Sanity check first:** Sample Ratio Mismatch test (`assert_no_sample_ratio_mismatch`). If arms aren't ~50/50, don't read results — the assignment is broken.

## Decision rule (written before looking)
Ship if the primary metric is significant at 95% **and** the guardrail doesn't degrade. Otherwise, don't ship; extend only if pre-registered.

## Known caveats
- **Novelty effect:** banners often work best in week one. A 14-day window may overstate the long-run effect.
- **Peeking:** don't check daily and stop when it turns green — that inflates false positives.
- **Multiple metrics:** every extra metric you test raises the chance one looks significant by luck. One primary metric, decided in advance.
