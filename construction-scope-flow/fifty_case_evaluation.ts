import { readFile } from "node:fs/promises";

import { chooseRiskBasedMargin } from "./risk_margin_router.ts";
import { evaluationCases, type EvaluationCase, type Selection } from "./twenty_case_evaluation.ts";
import {
  applyUniversalPricingControls,
  policyAtGrossMargin,
  type CatalogGapAllowance,
  type ControlledPricingInput,
} from "./universal_pricing_controls.ts";

type CostRow = {
  sourceRow: number;
  category: string;
  description: string;
  materialCost: number;
  directCost: number;
  unit: string;
};
type Costbook = { source: string; sheet: string; rowCount: number; rows: CostRow[] };

const q = (row: number, quantity: number, tradeGroup: string, wasteRate?: number): Selection =>
  ({ row, quantity, tradeGroup, wasteRate });

// Thirty additional variants broaden quantity, assembly, and coordination
// coverage without introducing job-profile logic into the pricing engine.
const additionalCases: EvaluationCase[] = [
  { id: 21, request: "Replace two standard two-piece toilets in existing locations.", projectKind: "replace", debrisLevel: "medium", selections: [q(11366, 2, "plumbing"), q(11386, 2, "plumbing")], market: { low: 700, high: 1_900 }, itemSelection: "clean", scopeCompleteness: "conditional" },
  { id: 22, request: "Replace a standard double-bowl kitchen sink and faucet.", projectKind: "replace", debrisLevel: "light", selections: [q(10886, 1, "plumbing"), q(10904, 1, "plumbing")], gaps: [["sink-removal", "Existing sink and faucet removal allowance.", 100]], market: { low: 600, high: 2_000 }, itemSelection: "clean", scopeCompleteness: "conditional" },
  { id: 23, request: "Replace a 31-inch bathroom vanity and standard faucet.", projectKind: "replace", debrisLevel: "medium", selections: [q(2820, 1, "cabinetry"), q(1359, 1, "cabinetry"), q(10862, 1, "plumbing")], market: { low: 700, high: 4_500 }, itemSelection: "clean", scopeCompleteness: "conditional" },
  { id: 24, request: "Replace a standard 60-inch acrylic alcove bathtub in the same location.", projectKind: "replace", debrisLevel: "medium", selections: [q(935, 1, "plumbing"), q(783, 1, "plumbing")], gaps: [["tub-closeout", "Drain, setting, and finish-closeout allowance.", 350]], market: { low: 1_500, high: 8_000 }, itemSelection: "clean", scopeCompleteness: "conditional", wetArea: true },
  { id: 25, request: "Replace a standard tub/shower mixer valve through a closed wall.", projectKind: "replace", debrisLevel: "light", selections: [q(951, 1, "plumbing")], gaps: [["access-patch", "Wall access and finish-patching allowance.", 250]], market: { low: 500, high: 1_500 }, itemSelection: "clean", scopeCompleteness: "conditional", wetArea: true },
  { id: 26, request: "Paint 1,000 SF of living-room walls with two coats.", projectKind: "repair", debrisLevel: "none", selections: [q(8872, 1_000, "finishes", 0.05)], market: { low: 800, high: 3_000 }, itemSelection: "clean", scopeCompleteness: "complete" },
  { id: 27, request: "Patch and paint three average bedrooms totaling 2,004 SF of walls and ceilings.", projectKind: "repair", debrisLevel: "none", selections: [q(8890, 60, "finishes"), q(8868, 60, "finishes"), q(8872, 2_004, "finishes", 0.05)], market: { low: 1_500, high: 5_000 }, itemSelection: "clean", scopeCompleteness: "complete" },
  { id: 28, request: "Repair 100 SF of damaged wall drywall and repaint a 300-SF wall area.", projectKind: "repair", debrisLevel: "light", selections: [q(8890, 100, "finishes"), q(8868, 100, "finishes"), q(8872, 300, "finishes", 0.05)], gaps: [["texture", "Wall texture-match allowance.", 125]], market: { low: 650, high: 2_000 }, itemSelection: "clean", scopeCompleteness: "conditional" },
  { id: 29, request: "Replace 100 SF of ceiling drywall and repaint a 500-SF ceiling.", projectKind: "repair", debrisLevel: "medium", selections: [q(3618, 100, "finishes"), q(3630, 100, "finishes", 0.10), q(8868, 100, "finishes"), q(8872, 500, "finishes", 0.05)], gaps: [["texture", "Ceiling texture-match allowance.", 250]], market: { low: 900, high: 3_000 }, itemSelection: "clean", scopeCompleteness: "conditional" },
  { id: 30, request: "Install 250 SF of standard LVP over a suitable wood subfloor.", projectKind: "install", debrisLevel: "none", selections: [q(9444, 250, "flooring"), q(9520, 250, "flooring", 0.10)], market: { low: 1_000, high: 4_000 }, itemSelection: "clean", scopeCompleteness: "complete" },
  { id: 31, request: "Remove carpet and install 1,000 SF of standard LVP.", projectKind: "replace", debrisLevel: "heavy", selections: [q(1470, 111.1111, "flooring"), q(9443, 1_000, "flooring"), q(9519, 1_000, "flooring", 0.10)], market: { low: 4_000, high: 16_000 }, itemSelection: "clean", scopeCompleteness: "complete" },
  { id: 32, request: "Replace 1,000 SF of carpet and pad with standard cut-pile carpet and pad.", projectKind: "replace", debrisLevel: "heavy", selections: [q(1470, 111.1111, "flooring"), q(1472, 111.1111, "flooring"), q(1480, 111.1111, "flooring", 0.10), q(1482, 111.1111, "flooring", 0.10)], market: { low: 3_000, high: 8_000 }, itemSelection: "clean", scopeCompleteness: "complete" },
  { id: 33, request: "Replace three hollow-core prehung bedroom doors and locksets.", projectKind: "replace", debrisLevel: "medium", selections: [q(2958, 3, "carpentry"), q(3490, 3, "carpentry", 0.05), q(3164, 3, "carpentry")], market: { low: 900, high: 3_600 }, itemSelection: "clean", scopeCompleteness: "conditional" },
  { id: 34, request: "Replace one average vinyl double-hung window in the existing opening.", projectKind: "replace", debrisLevel: "light", selections: [q(11796, 1, "openings")], market: { low: 450, high: 1_500 }, itemSelection: "clean", scopeCompleteness: "conditional" },
  { id: 35, request: "Replace six average vinyl double-hung windows.", projectKind: "replace", debrisLevel: "heavy", selections: [q(11796, 6, "openings")], market: { low: 2_700, high: 9_000 }, itemSelection: "clean", scopeCompleteness: "conditional" },
  { id: 36, request: "Install 100 LF of four-foot 9-gauge chain-link fence.", projectKind: "install", debrisLevel: "none", selections: [q(3952, 100, "exterior", 0.05)], gaps: [["terminal-posts", "Terminal-post and end-condition allowance.", 250]], market: { low: 900, high: 3_000 }, itemSelection: "clean", scopeCompleteness: "complete" },
  { id: 37, request: "Install 40 LF of four-to-six-foot redwood basketweave fence.", projectKind: "install", debrisLevel: "none", selections: [q(3870, 40, "exterior", 0.05)], market: { low: 800, high: 2_400 }, itemSelection: "clean", scopeCompleteness: "complete" },
  { id: 38, request: "Replace 50 SF of ceramic kitchen backsplash.", projectKind: "replace", debrisLevel: "medium", selections: [q(1659, 50, "tile"), q(1673, 50, "tile", 0.10)], market: { low: 500, high: 2_500 }, itemSelection: "clean", scopeCompleteness: "conditional" },
  { id: 39, request: "Replace 100 SF of tub-surround tile with backer board and waterproofing.", projectKind: "replace", debrisLevel: "medium", selections: [q(1659, 100, "tile"), q(1677, 100, "tile", 0.10), q(1673, 100, "tile", 0.10)], gaps: [["waterproofing", "Tub-surround waterproofing allowance.", 700]], market: { low: 2_000, high: 8_000 }, itemSelection: "clean", scopeCompleteness: "conditional", wetArea: true },
  { id: 40, request: "Replace eight average kitchen cabinet modules while keeping the layout.", projectKind: "replace", debrisLevel: "medium", selections: [q(959, 8, "cabinetry"), q(1001, 4, "cabinetry", 0.05), q(1295, 4, "cabinetry", 0.05)], market: { low: 4_500, high: 15_000 }, itemSelection: "conditional", scopeCompleteness: "conditional" },
  { id: 41, request: "Replace six average wall-cabinet modules.", projectKind: "replace", debrisLevel: "medium", selections: [q(959, 6, "cabinetry"), q(1295, 6, "cabinetry", 0.05)], market: { low: 1_500, high: 6_000 }, itemSelection: "conditional", scopeCompleteness: "conditional" },
  { id: 42, request: "Replace 20 LF of standard laminate countertop.", projectKind: "replace", debrisLevel: "medium", selections: [q(2392, 20, "countertops", 0.10)], gaps: [["countertop-removal", "Existing countertop removal allowance.", 300]], market: { low: 1_000, high: 4_500 }, itemSelection: "clean", scopeCompleteness: "conditional" },
  { id: 43, request: "Replace a kitchen sink, faucet, and garbage disposal together.", projectKind: "replace", debrisLevel: "medium", selections: [q(10886, 1, "plumbing"), q(10904, 1, "plumbing"), q(6004, 1, "plumbing")], gaps: [["fixture-removal", "Existing fixture removal allowance.", 150]], market: { low: 850, high: 3_350 }, itemSelection: "clean", scopeCompleteness: "conditional" },
  { id: 44, request: "Refresh a half bath with toilet, vanity, faucet, mirror, and light, excluding painting.", projectKind: "remodel", debrisLevel: "medium", selections: [q(11366, 1, "plumbing"), q(11386, 1, "plumbing"), q(2820, 1, "demolition"), q(1359, 1, "cabinetry"), q(10862, 1, "plumbing"), q(723, 1, "openings"), q(7846, 1, "electrical")], gaps: [["fixture-removals", "Faucet, mirror, and light removal allowance.", 250]], market: { low: 2_300, high: 7_500 }, itemSelection: "conditional", scopeCompleteness: "conditional" },
  { id: 45, request: "Remodel a 5x10 primary bath with tub surround, toilet, vanity, flooring, fan, light, and paint.", projectKind: "remodel", debrisLevel: "heavy", selections: [q(1659, 120, "demolition"), q(1677, 120, "tile", 0.10), q(1673, 120, "tile", 0.10), q(11366, 1, "plumbing"), q(11386, 1, "plumbing"), q(1359, 1, "cabinetry"), q(10862, 1, "plumbing"), q(9444, 80, "flooring"), q(9520, 80, "flooring", 0.10), q(7336, 1, "electrical"), q(7846, 1, "electrical"), q(8890, 300, "finishes"), q(8868, 300, "finishes"), q(8872, 300, "finishes", 0.05)], gaps: [["waterproofing", "Wet-area waterproofing allowance.", 800], ["floor-removal", "Existing floor removal allowance.", 200], ["electrical-closeout", "Fan/light removal and GFCI closeout allowance.", 400]], market: { low: 12_500, high: 25_000 }, itemSelection: "conditional", scopeCompleteness: "incomplete", wetArea: true },
  { id: 46, request: "Remodel a larger same-layout kitchen with twelve cabinet modules, laminate top, backsplash, sink, dishwasher, LVP, and paint.", projectKind: "remodel", debrisLevel: "heavy", selections: [q(959, 12, "demolition"), q(1001, 6, "cabinetry", 0.05), q(1295, 6, "cabinetry", 0.05), q(2392, 20, "countertops", 0.10), q(1659, 40, "demolition"), q(1673, 40, "tile", 0.10), q(10886, 1, "plumbing"), q(10904, 1, "plumbing"), q(3066, 1, "appliance"), q(3068, 1, "appliance"), q(9444, 180, "flooring"), q(9520, 180, "flooring", 0.10), q(8890, 400, "finishes"), q(8868, 400, "finishes"), q(8872, 400, "finishes", 0.05)], gaps: [["countertop-removal", "Countertop removal allowance.", 300], ["sink-removal", "Sink and faucet removal allowance.", 100], ["floor-removal", "Existing flooring removal allowance.", 450], ["misc-closeout", "Minor transitions, caulk, and closeout allowance.", 150]], market: { low: 18_000, high: 35_000 }, itemSelection: "conditional", scopeCompleteness: "incomplete" },
  { id: 47, request: "Patch 40 SF and paint 1,000 SF of interior walls.", projectKind: "repair", debrisLevel: "none", selections: [q(8890, 40, "finishes"), q(8868, 40, "finishes"), q(8872, 1_000, "finishes", 0.05)], market: { low: 800, high: 2_500 }, itemSelection: "clean", scopeCompleteness: "complete" },
  { id: 48, request: "Prime and paint 800 SF of interior ceiling.", projectKind: "repair", debrisLevel: "none", selections: [q(8868, 800, "finishes"), q(8872, 800, "finishes", 0.05)], market: { low: 800, high: 2_400 }, itemSelection: "clean", scopeCompleteness: "complete" },
  { id: 49, request: "Replace one bathroom exhaust fan and one vanity light.", projectKind: "replace", debrisLevel: "light", selections: [q(7336, 1, "electrical"), q(7846, 1, "electrical")], gaps: [["fixture-removals", "Existing fan and light removal allowance.", 200]], market: { low: 300, high: 1_200 }, itemSelection: "clean", scopeCompleteness: "conditional" },
  { id: 50, request: "Replace a 50-gallon gas water heater with permit and standard closeout allowance.", projectKind: "replace", debrisLevel: "medium", selections: [q(11466, 1, "plumbing"), q(11524, 1, "plumbing")], gaps: [["permit-closeout", "Permit and standard code-closeout allowance.", 300]], market: { low: 1_800, high: 4_500 }, itemSelection: "clean", scopeCompleteness: "conditional" },
];

function allowance([id, description, directCostAllowance]: [string, string, number]): CatalogGapAllowance {
  return { id, description, required: true, directCostAllowance };
}

function assess(price: number, low: number, high: number) {
  if (price < low) return { status: "low" as const, variance: (price - low) / low };
  if (price > high) return { status: "high" as const, variance: (price - high) / high };
  return { status: "within" as const, variance: 0 };
}

async function main() {
  const sourcePath = process.argv[2];
  if (!sourcePath) throw new Error("Usage: fifty_case_evaluation.ts <extracted-costbook.json>");
  const costbook = JSON.parse(await readFile(sourcePath, "utf8")) as Costbook;
  const byRow = new Map(costbook.rows.map((row) => [row.sourceRow, row]));

  // Use current, consistently scoped public ranges for the original cases.
  const benchmarkOverrides = new Map<number, { low: number; high: number }>([
    [1, { low: 350, high: 950 }], [2, { low: 200, high: 550 }],
    [3, { low: 600, high: 1_700 }], [4, { low: 150, high: 600 }],
    [5, { low: 150, high: 550 }], [6, { low: 150, high: 600 }],
    [7, { low: 1_500, high: 4_000 }], [8, { low: 423, high: 1_693 }],
    [9, { low: 600, high: 1_800 }], [10, { low: 2_400, high: 9_600 }],
    [11, { low: 900, high: 2_400 }], [12, { low: 300, high: 1_200 }],
    [13, { low: 1_350, high: 4_500 }], [14, { low: 450, high: 1_500 }],
    [15, { low: 1_600, high: 4_000 }], [16, { low: 250, high: 1_250 }],
    [17, { low: 1_500, high: 6_000 }], [18, { low: 3_800, high: 7_500 }],
    [19, { low: 8_800, high: 17_500 }], [20, { low: 12_800, high: 21_200 }],
  ]);
  const cases = [...evaluationCases, ...additionalCases].map((testCase) => ({
    ...testCase,
    market: benchmarkOverrides.get(testCase.id) ?? testCase.market,
  }));

  const evaluations = cases.map((testCase) => {
    const lines = testCase.selections.map((selection) => {
      const row = byRow.get(selection.row);
      if (!row) throw new Error(`Missing workbook row ${selection.row}`);
      return {
        id: `repair-2026-q3:${row.sourceRow}`,
        description: `${row.category} — ${row.description}`,
        tradeGroup: selection.tradeGroup,
        quantity: selection.quantity,
        directUnitCost: row.directCost,
        materialUnitCost: row.materialCost,
        materialWasteRate: selection.wasteRate,
      };
    });
    const input: ControlledPricingInput = {
      projectKind: testCase.projectKind,
      occupiedWorkArea: true,
      debrisLevel: testCase.debrisLevel,
      lines,
      catalogGaps: (testCase.gaps ?? []).map(allowance),
    };
    const tradeGroupCount = new Set(lines.map((line) => line.tradeGroup)).size;
    const coverage = testCase.scopeCompleteness === "complete" ? 1
      : testCase.scopeCompleteness === "conditional" ? 0.90 : 0.75;
    const decision = chooseRiskBasedMargin({
      projectKind: testCase.projectKind,
      tradeGroupCount,
      scopeCompleteness: testCase.scopeCompleteness,
      catalogCoverage: coverage,
      wetArea: testCase.wetArea ?? false,
      criticalRiskFlags: testCase.criticalRiskFlags ?? [],
    });
    const result = applyUniversalPricingControls(input, policyAtGrossMargin(decision.grossMargin));
    if (result.status !== "priced") throw new Error(`Case ${testCase.id} unexpectedly blocked`);
    return {
      id: testCase.id,
      request: testCase.request,
      workbookRows: testCase.selections.map(({ row, quantity }) => ({ row, quantity })),
      itemSelection: testCase.itemSelection,
      scopeCompleteness: testCase.scopeCompleteness,
      market: testCase.market,
      catalogDirectCost: result.catalogDirectCost,
      adjustedDirectCost: result.adjustedDirectCost,
      marginDecision: decision,
      sellingPrice: result.sellingPrice,
      ...assess(result.sellingPrice, testCase.market.low, testCase.market.high),
    };
  });

  const within = evaluations.filter((item) => item.status === "within");
  const withinFivePercentTolerance = evaluations.filter((item) =>
    item.sellingPrice >= item.market.low * 0.95 && item.sellingPrice <= item.market.high * 1.05
  );
  const high = evaluations.filter((item) => item.status === "high");
  const low = evaluations.filter((item) => item.status === "low");
  const summary = {
    tests: evaluations.length,
    withinBenchmark: within.length,
    accuracyPercent: Math.round(within.length / evaluations.length * 10_000) / 100,
    withinFivePercentTolerance: withinFivePercentTolerance.length,
    toleranceAccuracyPercent: Math.round(
      withinFivePercentTolerance.length / evaluations.length * 10_000,
    ) / 100,
    high: high.length,
    low: low.length,
    marginUse: {
      "35%": evaluations.filter((item) => item.marginDecision.grossMargin === 0.35).length,
      "40%": evaluations.filter((item) => item.marginDecision.grossMargin === 0.40).length,
      "45%": evaluations.filter((item) => item.marginDecision.grossMargin === 0.45).length,
    },
    selection: {
      clean: evaluations.filter((item) => item.itemSelection === "clean").length,
      conditional: evaluations.filter((item) => item.itemSelection === "conditional").length,
    },
    scope: {
      complete: evaluations.filter((item) => item.scopeCompleteness === "complete").length,
      conditional: evaluations.filter((item) => item.scopeCompleteness === "conditional").length,
      incomplete: evaluations.filter((item) => item.scopeCompleteness === "incomplete").length,
    },
  };
  console.log(JSON.stringify({ source: costbook.source, summary, failures: [...high, ...low], evaluations }, null, 2));
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
