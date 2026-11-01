import assert from "node:assert/strict";
import test from "node:test";

import { chooseRiskBasedMargin } from "./risk_margin_router.ts";

test("complete predictable single-trade work receives 35 percent", () => {
  assert.deepEqual(chooseRiskBasedMargin({
    projectKind: "replace",
    tradeGroupCount: 1,
    scopeCompleteness: "complete",
    catalogCoverage: 1,
    wetArea: false,
    criticalRiskFlags: [],
  }), {
    grossMargin: 0.35,
    tier: "predictable",
    reasons: ["complete, predictable scope with strong catalog coverage"],
  });
});

test("conditional or wet-area work receives 40 percent", () => {
  const decision = chooseRiskBasedMargin({
    projectKind: "replace",
    tradeGroupCount: 1,
    scopeCompleteness: "conditional",
    catalogCoverage: 0.9,
    wetArea: true,
    criticalRiskFlags: [],
  });
  assert.equal(decision.grossMargin, 0.40);
  assert.deepEqual(decision.reasons, ["conditional scope", "wet-area work"]);
});

test("remodel and coordination-heavy work receives 45 percent", () => {
  const decision = chooseRiskBasedMargin({
    projectKind: "remodel",
    tradeGroupCount: 6,
    scopeCompleteness: "incomplete",
    catalogCoverage: 0.75,
    wetArea: false,
    criticalRiskFlags: [],
  });
  assert.equal(decision.grossMargin, 0.45);
  assert.equal(decision.tier, "complex");
  assert.deepEqual(decision.reasons, ["remodel scope", "four or more trade groups"]);
});

test("the router rejects invalid risk facts", () => {
  assert.throws(() => chooseRiskBasedMargin({
    projectKind: "install",
    tradeGroupCount: 0,
    scopeCompleteness: "complete",
    catalogCoverage: 1,
    wetArea: false,
    criticalRiskFlags: [],
  }), /tradeGroupCount/);
});
