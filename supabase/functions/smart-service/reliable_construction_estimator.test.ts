import assert from "node:assert/strict";
import test from "node:test";

import { runReliableConstructionEstimator } from "./reliable_construction_estimator.ts";

function readyTurn() {
  return {
    stage: "estimate_ready",
    reply_text: "I built a preliminary cost breakdown for your review.",
    title: "Standard Bathroom Remodel",
    template_id: "bathroom_full_same_layout",
    question_ids: [],
    location: null,
    assumptions: ["The bathroom is assumed to be approximately 5 ft by 8 ft."],
    exclusions: ["Layout changes are excluded."],
    plan_sections: [
      {
        title: "Protection and demolition",
        steps: [
          "Protect the path to the bathroom.",
          "Remove the existing finishes included in the scope.",
          "Collect and dispose of normal remodeling debris.",
        ],
      },
      {
        title: "Installation and closeout",
        steps: [
          "Install the selected bathroom finishes.",
          "Reconnect and test the included fixtures.",
          "Clean the work area for contractor review.",
        ],
      },
    ],
    line_items: [
      {
        assembly_id: "site_protection_basic",
        quantity: 1,
        finish_tier: "standard",
        difficulty: "standard",
      },
      {
        assembly_id: "tile_floor_standard",
        quantity: 40,
        finish_tier: "standard",
        difficulty: "standard",
      },
      {
        assembly_id: "final_cleanup",
        quantity: 40,
        finish_tier: "standard",
        difficulty: "standard",
      },
    ],
  };
}

test("returns an estimate directly without exposing catalog questions", async () => {
  let calls = 0;
  const result = await runReliableConstructionEstimator({
    modelInput: [{ role: "user", content: "Remodel a standard bathroom." }],
    maxOutputTokens: 4_000,
    generateStructured: async () => {
      calls += 1;
      return readyTurn();
    },
  });

  assert.equal(calls, 1);
  assert.equal(result.stage, "estimate_ready");
  assert.equal(result.estimate.title, "Standard Bathroom Remodel");
  assert.equal(result.estimate.categories.length, 2);
  assert.equal(
    result.estimate.categories.flatMap((category) => category.items)
      .some((item) => item.name.toLowerCase().includes("cleanup")),
    false,
  );
  assert.ok(result.estimate.total > 0);
});

test("corrects an intake response instead of returning another form", async () => {
  let calls = 0;
  const result = await runReliableConstructionEstimator({
    modelInput: [{ role: "user", content: "Remodel a standard bathroom." }],
    maxOutputTokens: 4_000,
    generateStructured: async () => {
      calls += 1;
      if (calls === 1) {
        return {
          stage: "intake",
          reply_text: "Answer these details.",
          title: null,
          template_id: "bathroom_full_same_layout",
          question_ids: ["dimensions"],
          location: null,
          assumptions: [],
          exclusions: [],
          plan_sections: [],
          line_items: [],
        };
      }
      return readyTurn();
    },
  });

  assert.equal(calls, 2);
  assert.equal(result.stage, "estimate_ready");
  assert.equal(result.estimate.categories[1].items[0].quantity, 40);
});
