import assert from "node:assert/strict";
import test from "node:test";

import {
  checkScopeCompleteness,
  produceCandidateQuestions,
  produceScopeObligations,
  runConstructionScopeFlow,
  type CandidateSet,
  type ObligationResolution,
  type ScopeFlowAdapters,
  type ScopeObligation,
  type StructuredScopeFacts,
  type TaggedCostItem,
} from "./construction_scope_flow.ts";

const toiletFacts: StructuredScopeFacts = {
  summary: "Replace one toilet in an occupied bathroom.",
  action: "replace",
  objects: [{
    id: "toilet",
    name: "toilet",
    trade: "plumbing",
    location: "bathroom",
    quantity: { value: 1, unit: "Ea" },
  }],
  connectedSystems: ["water", "drain"],
  conditions: {
    occupiedWorkArea: true,
    intrusiveWork: false,
    wetArea: false,
    exteriorEnvelope: false,
    disturbsExistingFinish: false,
    structuralImpact: false,
    hazardousMaterialsPossible: false,
    layoutChange: false,
  },
  assumptions: [],
};

function item(
  id: string,
  processRole: TaggedCostItem["processRole"],
  attributes: TaggedCostItem["attributes"] = {},
  directCostPerUnit = 100,
): TaggedCostItem {
  return {
    id,
    sourceVersion: "repair-2026-q3",
    sourceRow: Number(id.replace(/\D/g, "")) || 1,
    category: "Test category",
    description: id,
    trade: "plumbing",
    action: processRole === "removal" ? "replace" : "install",
    object: "toilet",
    processRole,
    unit: "Ea",
    directCostPerUnit,
    attributes,
    residentialEligible: true,
    confidence: 0.95,
  };
}

test("universal rules create stable obligations without job profiles", () => {
  const first = produceScopeObligations(toiletFacts);
  const second = produceScopeObligations(toiletFacts);
  assert.deepEqual(first, second);
  assert.deepEqual(first.map((entry) => entry.processRole), [
    "scope_verification",
    "protection",
    "utility_isolation",
    "removal",
    "disposal",
    "concealed_condition_review",
    "preparation",
    "primary_work",
    "connection_and_startup",
    "testing",
    "cleanup",
  ]);
});

test("candidate differences create a stable high-impact question", () => {
  const obligations = produceScopeObligations(toiletFacts);
  const primary = obligations.find((entry) => entry.processRole === "primary_work")!;
  const candidates: CandidateSet[] = [{
    obligationID: primary.id,
    items: [
      item("toilet-standard", "primary_work", { grade: "standard" }, 300),
      item("toilet-premium", "primary_work", { grade: "premium" }, 900),
    ],
  }];
  const questions = produceCandidateQuestions(toiletFacts, obligations, candidates);
  assert.deepEqual(questions.map((question) => question.id), ["toilet:grade"]);
  assert.deepEqual(questions[0].options, ["premium", "standard"]);
  assert.equal(questions[0].priceImpact, 600);
});

test("completeness audit rejects a missing required resolution", () => {
  const obligations = produceScopeObligations(toiletFacts);
  const candidateSets: CandidateSet[] = obligations.map((entry) => ({
    obligationID: entry.id,
    items: entry.catalogItemExpected ? [item(`item-${entry.id}`, entry.processRole)] : [],
  }));
  const resolutions: ObligationResolution[] = obligations
    .filter((entry) => entry.processRole !== "testing")
    .map((entry) => ({
      obligationID: entry.id,
      resolution: entry.catalogItemExpected ? "priced_items" : "plan_only",
      explanation: "Resolved for test",
      selections: entry.catalogItemExpected
        ? [{ costItemID: `item-${entry.id}`, quantity: 1 }]
        : [],
    }));
  const audit = checkScopeCompleteness(obligations, candidateSets, resolutions);
  assert.equal(audit.valid, false);
  assert.deepEqual(audit.unresolvedObligationIDs, ["project:testing"]);
});

test("full flow asks questions, then audits and prices the resolved scope", async () => {
  const search = async (scopeObligation: ScopeObligation): Promise<TaggedCostItem[]> => {
    if (!scopeObligation.catalogItemExpected) return [];
    if (scopeObligation.processRole === "primary_work") {
      return [
        item("toilet-standard", "primary_work", { grade: "standard" }, 300),
        item("toilet-premium", "primary_work", { grade: "premium" }, 900),
      ];
    }
    return [item(`item-${scopeObligation.id}`, scopeObligation.processRole, {}, 25)];
  };
  const adapters: ScopeFlowAdapters = {
    extractStructuredFacts: async () => toiletFacts,
    searchCostItems: search,
    selectItemsAndQuantities: async ({ obligations, candidateSets, answers }) =>
      obligations.map((entry) => {
        const candidates = candidateSets.find((set) => set.obligationID === entry.id)?.items ?? [];
        if (!entry.catalogItemExpected) {
          return {
            obligationID: entry.id,
            resolution: "plan_only" as const,
            explanation: "Covered in the work plan.",
            selections: [],
          };
        }
        const selected = entry.processRole === "primary_work"
          ? candidates.find((candidate) => candidate.attributes.grade === answers["toilet:grade"])
          : candidates[0];
        return {
          obligationID: entry.id,
          resolution: "priced_items" as const,
          explanation: "Matched from the allowed candidates.",
          selections: selected ? [{ costItemID: selected.id, quantity: 1 }] : [],
        };
      }),
  };

  const first = await runConstructionScopeFlow({
    initialRequest: "Replace one toilet",
    pricingPolicy: { regionalFactor: 1, sellingPriceMultiplier: 1.25 },
    adapters,
  });
  assert.equal(first.stage, "questions");
  if (first.stage !== "questions") return;
  assert.ok(first.questions.some((question) => question.id === "toilet:grade"));

  const second = await runConstructionScopeFlow({
    initialRequest: "Replace one toilet",
    answers: { "toilet:grade": "standard" },
    pricingPolicy: { regionalFactor: 1, sellingPriceMultiplier: 1.25 },
    adapters,
  });
  assert.equal(second.stage, "priced");
  if (second.stage !== "priced") return;
  assert.equal(second.audit.valid, true);
  assert.ok(second.pricing.items.some((priced) => priced.costItemID === "toilet-standard"));
  assert.equal(second.pricing.total, 562.5);
});

test("optional catalog obligations can resolve as included elsewhere without a standalone row", async () => {
  const adapters: ScopeFlowAdapters = {
    extractStructuredFacts: async () => toiletFacts,
    searchCostItems: async (scopeObligation) =>
      scopeObligation.allowExplicitExclusion || !scopeObligation.catalogItemExpected
        ? []
        : [item(`required-${scopeObligation.id}`, scopeObligation.processRole)],
    selectItemsAndQuantities: async ({ obligations, candidateSets }) => obligations.map((entry) => {
      const selected = candidateSets.find((set) => set.obligationID === entry.id)?.items[0];
      return selected
        ? {
            obligationID: entry.id,
            resolution: "priced_items" as const,
            explanation: "Separately priced.",
            selections: [{ costItemID: selected.id, quantity: 1 }],
          }
        : {
            obligationID: entry.id,
            resolution: "included_elsewhere" as const,
            explanation: "Included in selected primary work or operating plan.",
            selections: [],
          };
    }),
  };
  const result = await runConstructionScopeFlow({
    initialRequest: "Replace one toilet",
    pricingPolicy: { regionalFactor: 1, sellingPriceMultiplier: 1.25 },
    adapters,
  });
  assert.equal(result.stage, "priced");
  if (result.stage !== "priced") return;
  assert.equal(result.audit.valid, true);
});
