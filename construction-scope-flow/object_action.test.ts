import assert from "node:assert/strict";
import test from "node:test";

import { produceScopeObligations, type StructuredScopeFacts } from "./construction_scope_flow.ts";

test("object actions prevent project-wide remodel demolition from applying to new work", () => {
  const facts: StructuredScopeFacts = {
    summary: "Remodel a bathroom.",
    action: "remodel",
    objects: [
      { id: "tub", name: "tub", action: "replace", quantity: { value: 1, unit: "Ea" } },
      { id: "waterproofing", name: "waterproofing", action: "install", quantity: { value: 70, unit: "SF" } },
    ],
    connectedSystems: [],
    conditions: {},
    assumptions: [],
  };
  const obligations = produceScopeObligations(facts);
  assert.ok(obligations.some((item) => item.id === "tub:removal"));
  assert.ok(obligations.some((item) => item.id === "waterproofing:preparation"));
  assert.ok(!obligations.some((item) => item.id === "waterproofing:demolition"));
});
