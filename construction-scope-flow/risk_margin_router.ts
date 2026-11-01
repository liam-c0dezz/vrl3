import type { ProjectKind } from "./universal_pricing_controls.ts";

export type ScopeCompletenessLevel = "complete" | "conditional" | "incomplete";
export type SupportedGrossMargin = 0.35 | 0.40 | 0.45;

export type MarginRiskInput = {
  projectKind: ProjectKind;
  tradeGroupCount: number;
  scopeCompleteness: ScopeCompletenessLevel;
  catalogCoverage: number;
  wetArea: boolean;
  criticalRiskFlags: string[];
};

export type MarginDecision = {
  grossMargin: SupportedGrossMargin;
  tier: "predictable" | "standard" | "complex";
  reasons: string[];
};

// Deterministic risk routing. AI supplies structured facts; it does not choose
// a percentage. The rules are intentionally universal and contain no job names.
export function chooseRiskBasedMargin(input: MarginRiskInput): MarginDecision {
  if (!Number.isInteger(input.tradeGroupCount) || input.tradeGroupCount < 1) {
    throw new Error("tradeGroupCount must be a positive integer");
  }
  if (!Number.isFinite(input.catalogCoverage) || input.catalogCoverage < 0 || input.catalogCoverage > 1) {
    throw new Error("catalogCoverage must be between zero and one");
  }

  const reasons: string[] = [];
  if (input.projectKind === "remodel") reasons.push("remodel scope");
  if (input.tradeGroupCount >= 4) reasons.push("four or more trade groups");
  if (input.criticalRiskFlags.length >= 2) reasons.push("multiple critical risk flags");
  if (reasons.length > 0) {
    return { grossMargin: 0.45, tier: "complex", reasons };
  }

  if (input.scopeCompleteness !== "complete") reasons.push(`${input.scopeCompleteness} scope`);
  if (input.tradeGroupCount >= 2) reasons.push("multiple trade groups");
  if (input.catalogCoverage < 0.90) reasons.push("catalog coverage below 90%");
  if (input.wetArea) reasons.push("wet-area work");
  if (input.criticalRiskFlags.length === 1) reasons.push("one critical risk flag");
  if (reasons.length > 0) {
    return { grossMargin: 0.40, tier: "standard", reasons };
  }

  return {
    grossMargin: 0.35,
    tier: "predictable",
    reasons: ["complete, predictable scope with strong catalog coverage"],
  };
}
