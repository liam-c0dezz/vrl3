# Fifty-case residential remodeling evaluation

Date: 2026-09-15

This is an isolated evaluation of the universal scope controls, pricing controls, and risk-based 35% / 40% / 45% margin router. It does not call or modify production, Supabase, edge functions, or application data.

## Result

| Measure | Result |
| --- | ---: |
| Tests | 50 |
| Strictly inside published benchmark | 42 / 50 |
| Strict accuracy | **84%** |
| Inside benchmark with ±5% boundary tolerance | 44 / 50 |
| Tolerance accuracy | **88%** |
| High estimates | 8 |
| Low estimates | 0 |
| Clean catalog selections | 42 |
| Conditional catalog selections | 8 |
| Complete scopes | 16 |
| Conditional scopes | 28 |
| Incomplete scopes | 6 |

The strict result is one case below an 85% target. Two misses were immaterial boundary misses: the toilet estimate was 2.4% over the benchmark ceiling and the dishwasher was 2.0% over. A ±5% boundary tolerance produces an 88% result.

## Results by work category

| Category | Cases | Inside benchmark | Result |
| --- | ---: | ---: | ---: |
| Plumbing, fixtures, and appliances | 15 | 11 | 73% |
| Painting and drywall | 8 | 8 | 100% |
| Flooring | 5 | 5 | 100% |
| Doors and windows | 5 | 5 | 100% |
| Fencing | 4 | 0 | 0% |
| Tile and wet-area assemblies | 4 | 4 | 100% |
| Multi-trade remodels | 6 | 6 | 100% |
| Cabinets and countertops | 3 | 3 | 100% |

## Strict failures

| # | Test | Estimate | Benchmark | Variance above ceiling |
| ---: | --- | ---: | ---: | ---: |
| 1 | Standard toilet replacement | $973.00 | $350–$950 | 2.4% |
| 2 | Garbage-disposal replacement | $695.65 | $200–$550 | 26.5% |
| 3 | Standard dishwasher replacement | $1,733.72 | $600–$1,700 | 2.0% |
| 4 | Bathroom-faucet replacement | $643.75 | $150–$600 | 7.3% |
| 14 | 50-LF chain-link fence | $1,928.88 | $450–$1,500 | 28.6% |
| 15 | 80-LF redwood fence | $6,396.77 | $1,600–$4,000 | 59.9% |
| 36 | 100-LF chain-link fence | $3,778.52 | $900–$3,000 | 26.0% |
| 37 | 40-LF redwood fence | $3,198.38 | $800–$2,400 | 33.3% |

Every failure was high. The system did not underprice any of the 50 benchmarked cases.

## Margin routing

| Selected margin | Cases |
| --- | ---: |
| 35% predictable tier | 16 |
| 40% standard-risk tier | 28 |
| 45% complex/remodel tier | 6 |

The router continued to use only universal facts: project type, trade-group count, scope completeness, catalog coverage, wet-area status, and critical-risk flags. It contains no job names or job profiles.

## Main findings

1. Painting, drywall, flooring, tile, doors, windows, cabinets, countertops, and the tested remodel assemblies all landed inside their directional benchmarks.
2. Fence rows are the clear catalog problem. Both chain-link and redwood selections started too high relative to current installed-per-linear-foot benchmarks before risk routing could help.
3. Small plumbing and appliance work is slightly conservative. Toilet and dishwasher were only boundary misses; garbage disposal and faucet need a closer bundled-scope or minimum-charge review.
4. The absence of low estimates is favorable for contractor risk, but it also shows that the current controls lean conservative.
5. Public market ranges are broad and inconsistently scoped. Contractor-approved estimates and completed-job actuals remain the better long-term calibration source.

## Benchmark basis

The test uses current public contractor ranges, normalized to the stated quantities and scope where necessary:

- [HomeGuide home-improvement cost estimator](https://homeguide.com/costs)
- [Bathroom remodeling](https://homeguide.com/costs/bathroom-remodel-cost)
- [Kitchen remodeling](https://homeguide.com/costs/kitchen-remodel-cost/)
- [Flooring installation](https://homeguide.com/costs/flooring-installation-cost)
- [Fence installation](https://homeguide.com/costs/fence-installation-cost)
- [Window replacement](https://homeguide.com/costs/window-replacement-cost)
- [Cabinet installation](https://homeguide.com/costs/cabinet-installation-cost)
- [Drywall repair](https://homeguide.com/costs/drywall-repair-cost)
- [Dishwasher replacement](https://homeguide.com/costs/dishwasher-installation-cost)
- [Sink and faucet installation](https://homeguide.com/costs/sink-installation-cost)

## Limitations

- This is a designed test set of common jobs, not a random sample of production estimates.
- Quantity variants share some catalog rows, so all 50 cases are not statistically independent.
- Public benchmarks do not always include identical material grade, disposal, mobilization, permits, or contractor overhead.
- The score measures whether the final number lands inside a broad market range. It does not prove every line item or quantity is correct.

The test is strong enough to support an editable contractor-draft workflow. It is not a substitute for calibration using contractor edits, accepted quotes, and completed-job costs.
