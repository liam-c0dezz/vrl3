import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

import {
  applyUniversalPricingControls,
  policyAtGrossMargin,
  type CatalogGapAllowance,
  type ControlledPricingInput,
  type DebrisLevel,
  type ProjectKind,
} from "./universal_pricing_controls.ts";
import { chooseRiskBasedMargin } from "./risk_margin_router.ts";

type CostRow = {
  sourceRow: number;
  category: string;
  description: string;
  materialCost: number;
  directCost: number;
  unit: string;
};

type Costbook = { source: string; sheet: string; rowCount: number; rows: CostRow[] };
export type Selection = { row: number; quantity: number; tradeGroup: string; wasteRate?: number };

export type EvaluationCase = {
  id: number;
  request: string;
  projectKind: ProjectKind;
  debrisLevel: DebrisLevel;
  selections: Selection[];
  gaps?: Array<[id: string, description: string, directCostAllowance: number]>;
  market: { low: number; high: number };
  itemSelection: "clean" | "conditional";
  scopeCompleteness: "complete" | "conditional" | "incomplete";
  wetArea?: boolean;
  criticalRiskFlags?: string[];
};

const q = (row: number, quantity: number, tradeGroup: string, wasteRate?: number): Selection =>
  ({ row, quantity, tradeGroup, wasteRate });

export const evaluationCases: EvaluationCase[] = [
  { id: 1, request: "Replace a rocking standard two-piece toilet in the same location.", projectKind: "replace", debrisLevel: "light", selections: [q(11366, 1, "plumbing"), q(11386, 1, "plumbing")], market: { low: 500, high: 1_000 }, itemSelection: "clean", scopeCompleteness: "conditional" },
  { id: 2, request: "Replace a failed standard garbage disposal.", projectKind: "replace", debrisLevel: "light", selections: [q(6004, 1, "plumbing")], market: { low: 350, high: 750 }, itemSelection: "clean", scopeCompleteness: "complete" },
  { id: 3, request: "Replace a standard dishwasher in the same opening.", projectKind: "replace", debrisLevel: "light", selections: [q(3066, 1, "appliance"), q(3068, 1, "appliance")], market: { low: 675, high: 1_250 }, itemSelection: "clean", scopeCompleteness: "complete" },
  { id: 4, request: "Replace a standard bathroom sink faucet.", projectKind: "replace", debrisLevel: "none", selections: [q(10862, 1, "plumbing")], gaps: [["faucet-removal", "Existing faucet removal allowance.", 75]], market: { low: 250, high: 700 }, itemSelection: "clean", scopeCompleteness: "conditional" },
  { id: 5, request: "Replace an existing 50-CFM bathroom exhaust fan.", projectKind: "replace", debrisLevel: "light", selections: [q(7336, 1, "electrical")], gaps: [["fan-removal", "Fan removal and existing duct verification allowance.", 125]], market: { low: 150, high: 550 }, itemSelection: "clean", scopeCompleteness: "conditional" },
  { id: 6, request: "Replace a standard vanity light bar.", projectKind: "replace", debrisLevel: "none", selections: [q(7846, 1, "electrical")], gaps: [["light-removal", "Existing light removal allowance.", 75]], market: { low: 200, high: 500 }, itemSelection: "clean", scopeCompleteness: "conditional" },
  { id: 7, request: "Replace a 50-gallon atmospheric gas water heater.", projectKind: "replace", debrisLevel: "medium", selections: [q(11466, 1, "plumbing"), q(11524, 1, "plumbing")], market: { low: 1_800, high: 3_500 }, itemSelection: "clean", scopeCompleteness: "conditional" },
  { id: 8, request: "Patch 20 SF and paint 500-SF walls plus a 168-SF ceiling.", projectKind: "repair", debrisLevel: "none", selections: [q(8890, 20, "finishes"), q(8868, 20, "finishes"), q(8872, 668, "finishes", 0.05)], market: { low: 423, high: 1_693 }, itemSelection: "clean", scopeCompleteness: "complete" },
  { id: 9, request: "Replace 48 SF of ceiling drywall and repaint a 300-SF ceiling.", projectKind: "repair", debrisLevel: "light", selections: [q(3618, 48, "finishes"), q(3630, 48, "finishes", 0.10), q(8868, 48, "finishes"), q(8872, 300, "finishes", 0.05)], gaps: [["texture", "Ceiling texture-match allowance.", 200]], market: { low: 600, high: 1_800 }, itemSelection: "clean", scopeCompleteness: "conditional" },
  { id: 10, request: "Remove 600 SF of carpet and install standard LVP on wood subfloor.", projectKind: "replace", debrisLevel: "medium", selections: [q(1470, 66.6667, "flooring"), q(9443, 600, "flooring"), q(9519, 600, "flooring", 0.10)], market: { low: 4_800, high: 9_000 }, itemSelection: "clean", scopeCompleteness: "complete" },
  { id: 11, request: "Replace 300 SF of carpet and pad with standard cut-pile carpet and pad.", projectKind: "replace", debrisLevel: "medium", selections: [q(1470, 33.3333, "flooring"), q(1472, 33.3333, "flooring"), q(1480, 33.3333, "flooring", 0.10), q(1482, 33.3333, "flooring", 0.10)], market: { low: 1_200, high: 2_400 }, itemSelection: "clean", scopeCompleteness: "complete" },
  { id: 12, request: "Replace one hollow-core prehung bedroom door and lockset.", projectKind: "replace", debrisLevel: "light", selections: [q(2958, 1, "carpentry"), q(3490, 1, "carpentry", 0.05), q(3164, 1, "carpentry")], market: { low: 362, high: 1_235 }, itemSelection: "clean", scopeCompleteness: "conditional" },
  { id: 13, request: "Replace three average vinyl double-hung windows, 9–12 SF each.", projectKind: "replace", debrisLevel: "medium", selections: [q(11796, 3, "openings")], market: { low: 2_100, high: 3_600 }, itemSelection: "clean", scopeCompleteness: "conditional" },
  { id: 14, request: "Install 50 LF of four-foot 9-gauge chain-link fence with no gate.", projectKind: "install", debrisLevel: "none", selections: [q(3952, 50, "exterior", 0.05)], gaps: [["terminal-posts", "Terminal-post and end-condition allowance.", 150]], market: { low: 1_000, high: 2_500 }, itemSelection: "clean", scopeCompleteness: "complete" },
  { id: 15, request: "Install 80 LF of four-to-six-foot redwood basketweave fence.", projectKind: "install", debrisLevel: "none", selections: [q(3870, 80, "exterior", 0.05)], market: { low: 4_000, high: 8_000 }, itemSelection: "clean", scopeCompleteness: "complete" },
  { id: 16, request: "Replace 25 SF of ceramic kitchen backsplash.", projectKind: "replace", debrisLevel: "light", selections: [q(1659, 25, "tile"), q(1673, 25, "tile", 0.10)], market: { low: 1_000, high: 2_500 }, itemSelection: "clean", scopeCompleteness: "conditional" },
  { id: 17, request: "Replace 70 SF of tub-surround tile with backer board.", projectKind: "replace", debrisLevel: "medium", selections: [q(1659, 70, "tile"), q(1677, 70, "tile", 0.10), q(1673, 70, "tile", 0.10)], gaps: [["waterproofing", "Tub-surround waterproofing allowance.", 500]], market: { low: 4_000, high: 9_000 }, itemSelection: "clean", scopeCompleteness: "incomplete", wetArea: true },
  { id: 18, request: "Refresh a powder room with toilet, vanity, faucet, mirror, light, and paint.", projectKind: "remodel", debrisLevel: "medium", selections: [q(11366, 1, "plumbing"), q(11386, 1, "plumbing"), q(2820, 1, "demolition"), q(1359, 1, "cabinetry"), q(10862, 1, "plumbing"), q(723, 1, "openings"), q(7846, 1, "electrical"), q(8868, 120, "finishes"), q(8872, 120, "finishes", 0.05)], gaps: [["fixture-removals", "Faucet, mirror, and light removal allowance.", 250], ["bath-closeout", "Bathroom consumables and electrical closeout allowance.", 250]], market: { low: 5_000, high: 15_000 }, itemSelection: "conditional", scopeCompleteness: "incomplete" },
  { id: 19, request: "Remodel a 5×8 hall bath with surround, toilet, vanity, LVP, fan, light, and paint.", projectKind: "remodel", debrisLevel: "medium", selections: [q(1659, 70, "demolition"), q(1677, 70, "tile", 0.10), q(1673, 70, "tile", 0.10), q(11366, 1, "plumbing"), q(11386, 1, "plumbing"), q(1359, 1, "cabinetry"), q(10862, 1, "plumbing"), q(9444, 40, "flooring"), q(9520, 40, "flooring", 0.10), q(7336, 1, "electrical"), q(7846, 1, "electrical"), q(8890, 180, "finishes"), q(8868, 180, "finishes"), q(8872, 180, "finishes", 0.05)], gaps: [["waterproofing", "Wet-area waterproofing allowance.", 500], ["floor-removal", "Existing floor removal allowance.", 120], ["electrical-closeout", "Fan/light removal and GFCI closeout allowance.", 350]], market: { low: 18_000, high: 35_000 }, itemSelection: "conditional", scopeCompleteness: "incomplete", wetArea: true },
  { id: 20, request: "Remodel a 10×12 kitchen with cabinets, laminate top, backsplash, sink, dishwasher, LVP, and paint.", projectKind: "remodel", debrisLevel: "medium", selections: [q(959, 8, "demolition"), q(1001, 4, "cabinetry", 0.05), q(1295, 4, "cabinetry", 0.05), q(2392, 14.4, "countertops", 0.10), q(1659, 25, "demolition"), q(1673, 25, "tile", 0.10), q(10886, 1, "plumbing"), q(10904, 1, "plumbing"), q(3066, 1, "appliance"), q(3068, 1, "appliance"), q(9444, 120, "flooring"), q(9520, 120, "flooring", 0.10), q(8890, 300, "finishes"), q(8868, 300, "finishes"), q(8872, 300, "finishes", 0.05)], gaps: [["countertop-removal", "Countertop removal allowance.", 200], ["sink-removal", "Sink and faucet removal allowance.", 100], ["floor-removal", "Existing flooring removal allowance.", 300], ["misc-closeout", "Minor transitions, caulk, and closeout allowance.", 100]], market: { low: 18_000, high: 35_000 }, itemSelection: "conditional", scopeCompleteness: "incomplete" },
];

function gap([id, description, directCostAllowance]: [string, string, number]): CatalogGapAllowance {
  return { id, description, required: true, directCostAllowance };
}

function assessment(price: number, market: { low: number; high: number }) {
  if (price < market.low) return { status: "low", variance: (price - market.low) / market.low };
  if (price > market.high) return { status: "high", variance: (price - market.high) / market.high };
  return { status: "within", variance: 0 };
}

async function main() {
  const sourcePath = process.argv[2];
  if (!sourcePath) throw new Error("Usage: twenty_case_evaluation.ts <extracted-costbook.json>");
  const costbook = JSON.parse(await readFile(sourcePath, "utf8")) as Costbook;
  const byRow = new Map(costbook.rows.map((row) => [row.sourceRow, row]));
  const margins = [0.35, 0.40, 0.45];

  const evaluations = evaluationCases.map((testCase) => {
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
      catalogGaps: (testCase.gaps ?? []).map(gap),
    };
    const tradeGroupCount = new Set(lines.map((line) => line.tradeGroup)).size;
    const catalogCoverage = testCase.scopeCompleteness === "complete"
      ? 1
      : testCase.scopeCompleteness === "conditional"
      ? 0.90
      : 0.75;
    const marginDecision = chooseRiskBasedMargin({
      projectKind: testCase.projectKind,
      tradeGroupCount,
      scopeCompleteness: testCase.scopeCompleteness,
      catalogCoverage,
      wetArea: testCase.wetArea ?? false,
      criticalRiskFlags: testCase.criticalRiskFlags ?? [],
    });
    const marginResults = margins.map((grossMargin) => {
      const result = applyUniversalPricingControls(input, policyAtGrossMargin(grossMargin));
      if (result.status !== "priced") return { grossMargin, ...result };
      return {
        grossMargin,
        adjustedDirectCost: result.adjustedDirectCost,
        sellingPrice: result.sellingPrice,
        ...assessment(result.sellingPrice, testCase.market),
      };
    });
    const detailed = applyUniversalPricingControls(input, policyAtGrossMargin(0.40));
    const riskPriced = applyUniversalPricingControls(
      input,
      policyAtGrossMargin(marginDecision.grossMargin),
    );
    return {
      id: testCase.id,
      request: testCase.request,
      workbookRows: testCase.selections.map((selection) => ({ row: selection.row, quantity: selection.quantity })),
      market: testCase.market,
      itemSelection: testCase.itemSelection,
      scopeCompleteness: testCase.scopeCompleteness,
      catalogDirectCost: detailed.status === "priced" ? detailed.catalogDirectCost : null,
      controls: detailed.status === "priced" ? detailed.adjustments : [],
      margins: marginResults,
      riskBased: riskPriced.status === "priced"
        ? {
            decision: marginDecision,
            sellingPrice: riskPriced.sellingPrice,
            ...assessment(riskPriced.sellingPrice, testCase.market),
          }
        : { decision: marginDecision, ...riskPriced },
    };
  });

  const priceWithinBenchmark = Object.fromEntries(margins.map((grossMargin, index) => [
    String(grossMargin),
    evaluations.filter((evaluation) => evaluation.margins[index].status === "within").length,
  ]));
  const summary = {
    tests: evaluations.length,
    itemSelection: {
      clean: evaluations.filter((item) => item.itemSelection === "clean").length,
      conditional: evaluations.filter((item) => item.itemSelection === "conditional").length,
    },
    scopeCompleteness: {
      complete: evaluations.filter((item) => item.scopeCompleteness === "complete").length,
      conditional: evaluations.filter((item) => item.scopeCompleteness === "conditional").length,
      incomplete: evaluations.filter((item) => item.scopeCompleteness === "incomplete").length,
    },
    priceWithinBenchmark,
    riskBasedPriceWithinBenchmark: evaluations.filter((evaluation) =>
      evaluation.riskBased.status === "within"
    ).length,
  };
  console.log(JSON.stringify({ source: costbook.source, margins, summary, evaluations }, null, 2));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error: unknown) => {
    console.error(error);
    process.exitCode = 1;
  });
}
