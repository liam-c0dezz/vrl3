import assert from "node:assert/strict";
import test from "node:test";

import {
  applyUniversalPricingControls,
  policyAtGrossMargin,
  type ControlledPricingInput,
} from "./universal_pricing_controls.ts";

const basic: ControlledPricingInput = {
  projectKind: "repair",
  occupiedWorkArea: true,
  debrisLevel: "medium",
  lines: [{
    id: "drywall",
    description: "Drywall repair",
    tradeGroup: "finishes",
    quantity: 10,
    directUnitCost: 20,
    materialUnitCost: 5,
    materialWasteRate: 0.10,
  }],
  catalogGaps: [],
};

test("small standalone work receives waste, a trade minimum, debris, and general conditions", () => {
  const result = applyUniversalPricingControls(basic, policyAtGrossMargin(0.45));
  assert.equal(result.status, "priced");
  if (result.status !== "priced") return;
  assert.equal(result.catalogDirectCost, 200);
  assert.deepEqual(result.adjustments.map((item) => item.kind), [
    "material_waste",
    "trade_minimum",
    "debris",
    "general_conditions",
  ]);
  assert.equal(result.sellingPrice, 1264.09);
});

test("material waste applies to material only, not labor or installed quantity", () => {
  const input: ControlledPricingInput = {
    projectKind: "install",
    occupiedWorkArea: false,
    debrisLevel: "none",
    lines: [{
      id: "floor",
      description: "Flooring",
      tradeGroup: "flooring",
      quantity: 100,
      directUnitCost: 10,
      materialUnitCost: 4,
      materialWasteRate: 0.10,
    }],
    catalogGaps: [],
  };
  const result = applyUniversalPricingControls(input, policyAtGrossMargin(0.40));
  assert.equal(result.status, "priced");
  if (result.status !== "priced") return;
  assert.equal(result.adjustments[0].kind, "material_waste");
  assert.equal(result.adjustments[0].directCost, 40);
});

test("a required catalog gap blocks pricing until it has an explicit allowance", () => {
  const result = applyUniversalPricingControls({
    ...basic,
    catalogGaps: [{ id: "waterproofing", description: "Waterproofing", required: true }],
  }, policyAtGrossMargin(0.40));
  assert.deepEqual(result, { status: "blocked", missingAllowanceIDs: ["waterproofing"] });
});

test("multi-trade projects do not stack a minimum for every trade", () => {
  const result = applyUniversalPricingControls({
    projectKind: "remodel",
    occupiedWorkArea: true,
    debrisLevel: "none",
    lines: [
      { id: "a", description: "A", tradeGroup: "plumbing", quantity: 1, directUnitCost: 100, materialUnitCost: 0 },
      { id: "b", description: "B", tradeGroup: "electrical", quantity: 1, directUnitCost: 100, materialUnitCost: 0 },
    ],
    catalogGaps: [],
  }, policyAtGrossMargin(0.35));
  assert.equal(result.status, "priced");
  if (result.status !== "priced") return;
  assert.ok(!result.adjustments.some((item) => item.kind === "trade_minimum"));
  assert.ok(result.adjustments.some((item) => item.kind === "mobilization"));
});
