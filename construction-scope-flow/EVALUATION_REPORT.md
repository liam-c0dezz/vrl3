# Isolated construction scope and pricing evaluation

Date: 2026-09-15

This evaluation uses the 12,107-row `Costbook Export` worksheet from `Copy of repair-2026-q3.xlsx`. It does not call or modify Supabase, an edge function, production code, or application data.

## Universal pricing controls tested

The pricing layer applies after catalog selection and scope-completeness review:

1. Material waste applies only to the material component of a line item. It does not increase installed labor quantity.
2. Standalone trade minimums apply only to single-trade projects. Multi-trade projects do not stack one minimum per trade.
3. Small-project mobilization applies only when no standalone trade-minimum adjustment was required.
4. Routine light debris is treated as included. Medium and heavy debris receive explicit direct-cost allowances.
5. Remodel general conditions vary by project kind, occupied conditions, and the number of active trades.
6. A required catalog gap blocks pricing until an explicit allowance is supplied.
7. Gross margin is applied to the adjusted direct cost after these controls.

## Original five-case margin comparison

| Case | Adjusted direct cost | 35% margin | 40% margin | 45% margin | Directional benchmark |
| --- | ---: | ---: | ---: | ---: | ---: |
| Kitchen remodel | $9,913.10 | $15,250.92 | $16,521.83 | $18,023.82 | $13,061–$16,375 |
| Bathroom remodel | $5,592.09 | $8,603.22 | $9,320.15 | $10,167.44 | $9,500–$12,500 |
| Bedroom painting | $594.21 | $914.17 | $990.35 | $1,080.38 | $650–$1,300 |
| 600-SF LVP replacement | $4,764.02 | $7,329.26 | $7,940.03 | $8,661.85 | $2,400–$7,200 |
| Ceiling drywall repair | $489.25 | $752.69 | $815.42 | $889.55 | $785–$1,990 |

The original five cases do not support one universal margin. The lower kitchen benchmark favors 35%, the bathroom favors 45%, and the commodity flooring case is already slightly high at 35%.

## Twenty-case independent evaluation

The separate estimator selected real workbook rows and quantities. The deterministic pricing engine then applied the same controls at all three margins.

| # | Test case | Catalog direct | 35% | 40% | 45% |
| ---: | --- | ---: | ---: | ---: | ---: |
| 1 | Standard toilet replacement | $441.80 | $898 in range | $973 in range | $1,061 high |
| 2 | Garbage-disposal replacement | $314.00 | $696 in range | $754 high | $822 high |
| 3 | Dishwasher replacement | $1,094.10 | $1,734 high | $1,878 high | $2,049 high |
| 4 | Bathroom faucet replacement | $293.00 | $594 in range | $644 in range | $702 high |
| 5 | Bathroom exhaust-fan replacement | $123.30 | $396 in range | $429 in range | $468 in range |
| 6 | Vanity light replacement | $64.60 | $317 in range | $343 in range | $375 in range |
| 7 | 50-gallon gas water heater | $1,728.00 | $3,055 in range | $3,310 in range | $3,611 high |
| 8 | Bedroom patch and painting | $564.88 | $914 in range | $990 in range | $1,080 in range |
| 9 | Ceiling drywall repair and paint | $391.80 | $1,070 in range | $1,159 in range | $1,264 in range |
| 10 | 600-SF carpet-to-LVP replacement | $4,280.67 | $7,329 in range | $7,940 in range | $8,662 in range |
| 11 | 300-SF carpet and pad replacement | $836.33 | $1,740 in range | $1,885 in range | $2,057 in range |
| 12 | Prehung bedroom door and lockset | $564.60 | $919 in range | $996 in range | $1,087 in range |
| 13 | Three vinyl windows | $1,812.00 | $3,188 in range | $3,454 in range | $3,768 high |
| 14 | 50-LF chain-link fence | $1,027.00 | $1,929 in range | $2,090 in range | $2,280 in range |
| 15 | 80-LF redwood fence | $3,866.40 | $6,397 in range | $6,930 in range | $7,560 in range |
| 16 | 25-SF kitchen backsplash | $551.75 | $951 low | $1,030 in range | $1,124 in range |
| 17 | 70-SF tub surround | $1,703.80 | $3,920 low | $4,246 in range | $4,632 in range |
| 18 | Powder-room refresh | $1,645.20 | $3,900 low | $4,225 low | $4,609 low |
| 19 | 5×8 hall-bath remodel | $3,924.30 | $8,603 low | $9,320 low | $10,167 low |
| 20 | 10×12 kitchen remodel | $8,069.60 | $15,251 low | $16,522 low | $18,024 in range |

### Scores

| Measure | Result |
| --- | ---: |
| Clean catalog selections | 17 of 20 |
| Conditional catalog selections | 3 of 20 |
| Scope classified complete | 7 of 20 |
| Scope classified conditional | 9 of 20 |
| Scope classified incomplete | 4 of 20 |
| Price inside benchmark at 35% margin | 14 of 20 |
| Price inside benchmark at 40% margin | 15 of 20 |
| Price inside benchmark at 45% margin | 12 of 20 |
| Price inside benchmark with risk-based margin routing | **17 of 20** |

## Risk-based margin router

The finalized baseline remains intact. An additional deterministic router now selects the margin from structured risk facts:

- 35% for complete, predictable work with strong catalog coverage
- 40% for conditional or incomplete scope, multiple trades, wet-area work, weaker catalog coverage, or one critical risk flag
- 45% for remodels, four or more trade groups, or multiple critical risk flags

The router does not contain job names or job profiles. On the same 20 cases it selected a price inside the directional benchmark for 17 cases, or 85%.

The remaining misses were the high catalog cost for the dishwasher and under-scoped powder-room and hall-bath remodels. Those require catalog review or stronger scope obligations rather than a higher universal margin.

## Findings

Forty percent is the strongest default in this small test set, but margin should not be used to compensate for incomplete scope.

- The catalog-selection result is promising. Seventeen cases used clean, believable rows and three required explicit assumptions. No case required inventing a job profile.
- Simple replacements and defined single-trade work generally price plausibly after minimum and mobilization controls.
- The dishwasher remains high at every margin because the selected catalog installation row is expensive before any pricing control. This requires a catalog-row review, not a margin change.
- The powder-room and hall-bath cases remain low because their scope is incomplete or their market benchmark includes broader contractor scope than the selected obligations.
- The kitchen reaches the broader remodel benchmark only at 45%, while the narrower budget-kitchen benchmark favors 35%. Benchmark scope must match the exact estimate before it can serve as an accuracy label.
- Forty-five percent overprices several well-defined replacements. It should be a risk tier for uncertain or coordination-heavy work, not the universal default.

## Recommended pricing policy for the next prototype iteration

- Use 40% gross margin as the provisional default.
- Allow 35% for complete, predictable, price-sensitive commodity work when catalog coverage is strong.
- Allow 45% for complex or uncertainty-heavy work only after the scope-completeness engine confirms every required obligation or allowance.
- Block a final fixed price when a required wet-area, demolition, disposal, weatherproofing, code, or finish-restoration obligation lacks either a catalog row or an explicit allowance.
- Treat benchmark comparison as a separate evaluation layer. A benchmark must state location, project definition, quality tier, and included/excluded work.

## Directional market sources

- [Angi: Denver room painting](https://www.angi.com/articles/how-much-does-it-cost-paint-room/co/denver)
- [Colorado Space Remodeling: Denver bathroom remodel cost](https://www.csremodeling.com/blog/denver-bathroom-remodel-cost-2026)
- [Colorado Space Remodeling: Denver kitchen remodel cost](https://www.csremodeling.com/blog/denver-kitchen-remodel-cost-2026)
- [Angi: interior door installation](https://www.angi.com/articles/how-much-does-it-cost-install-interior-door.htm)
- [Angi: window replacement](https://www.angi.com/articles/how-much-does-window-replacement-cost.htm)
- [LatestCost: carpet removal and LVP](https://latestcost.com/carpet-removal-vinyl-plank-flooring-cost/)

These sources provide directional ranges, not ground truth. The next accuracy phase should use the contractor's own won/lost estimates and completed-job actuals.
