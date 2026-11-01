// Standalone pricing controls for the construction-scope prototype.
//
// These controls intentionally sit after catalog selection and before margin.
// They are universal cost mechanics, not job templates. Production and
// Supabase are not imported here.

export type ProjectKind = "repair" | "replace" | "install" | "remodel";
export type DebrisLevel = "none" | "light" | "medium" | "heavy";

export type PricingLine = {
  id: string;
  description: string;
  tradeGroup: string;
  quantity: number;
  directUnitCost: number;
  materialUnitCost: number;
  materialWasteRate?: number;
};

export type CatalogGapAllowance = {
  id: string;
  description: string;
  required: boolean;
  directCostAllowance?: number;
};

export type ControlledPricingInput = {
  projectKind: ProjectKind;
  occupiedWorkArea: boolean;
  debrisLevel: DebrisLevel;
  lines: PricingLine[];
  catalogGaps: CatalogGapAllowance[];
};

export type UniversalPricingPolicy = {
  grossMargin: number;
  regionalFactor: number;
  standaloneTradeMinimumDirectCost: Record<string, number>;
  defaultStandaloneTradeMinimumDirectCost: number;
  mobilizationDirectCost: {
    belowDirectCost: number;
    amount: number;
  };
  debrisDirectCost: Record<DebrisLevel, number>;
  generalConditionsRate: {
    repair: number;
    replace: number;
    install: number;
    remodel: number;
    occupiedAdder: number;
    multiTradeAdder: number;
    maximum: number;
  };
};

export const defaultUniversalPricingPolicy: Omit<UniversalPricingPolicy, "grossMargin"> = {
  regionalFactor: 1,
  // Applied only when the whole project is one trade group. Multi-trade work
  // receives general conditions instead of stacking a minimum for every trade.
  standaloneTradeMinimumDirectCost: {
    finishes: 475,
    plumbing: 300,
    electrical: 125,
    flooring: 500,
    tile: 600,
    cabinetry: 550,
    carpentry: 400,
    hvac: 400,
  },
  defaultStandaloneTradeMinimumDirectCost: 300,
  // The minimum covers the trade's productive work floor and mobilization.
  // Mobilization is separate only when no trade-minimum adjustment was needed.
  mobilizationDirectCost: { belowDirectCost: 500, amount: 125 },
  debrisDirectCost: { none: 0, light: 0, medium: 200, heavy: 600 },
  generalConditionsRate: {
    repair: 0.02,
    replace: 0.02,
    install: 0.02,
    remodel: 0.06,
    occupiedAdder: 0.01,
    multiTradeAdder: 0.01,
    maximum: 0.10,
  },
};

export type PricingControlAdjustment = {
  kind: "material_waste" | "trade_minimum" | "mobilization" | "debris" |
    "catalog_gap_allowance" | "general_conditions";
  description: string;
  directCost: number;
};

export type ControlledPricingResult =
  | {
      status: "blocked";
      missingAllowanceIDs: string[];
    }
  | {
      status: "priced";
      grossMargin: number;
      catalogDirectCost: number;
      adjustedDirectCost: number;
      sellingPrice: number;
      adjustments: PricingControlAdjustment[];
    };

function money(value: number): number {
  return Math.round(value * 100) / 100;
}

function assertNonnegativeFinite(value: number, label: string) {
  if (!Number.isFinite(value) || value < 0) throw new Error(`${label} must be a nonnegative finite number`);
}

export function applyUniversalPricingControls(
  input: ControlledPricingInput,
  policy: UniversalPricingPolicy,
): ControlledPricingResult {
  if (!Number.isFinite(policy.grossMargin) || policy.grossMargin <= 0 || policy.grossMargin >= 1) {
    throw new Error("grossMargin must be between zero and one");
  }
  if (!Number.isFinite(policy.regionalFactor) || policy.regionalFactor <= 0) {
    throw new Error("regionalFactor must be a positive finite number");
  }
  for (const line of input.lines) {
    assertNonnegativeFinite(line.quantity, `${line.id} quantity`);
    assertNonnegativeFinite(line.directUnitCost, `${line.id} directUnitCost`);
    assertNonnegativeFinite(line.materialUnitCost, `${line.id} materialUnitCost`);
    if (line.materialWasteRate !== undefined) {
      assertNonnegativeFinite(line.materialWasteRate, `${line.id} materialWasteRate`);
    }
  }

  const missingAllowanceIDs = input.catalogGaps
    .filter((gap) => gap.required && gap.directCostAllowance === undefined)
    .map((gap) => gap.id);
  if (missingAllowanceIDs.length > 0) return { status: "blocked", missingAllowanceIDs };

  const catalogDirectCost = input.lines.reduce(
    (sum, line) => sum + line.quantity * line.directUnitCost,
    0,
  ) * policy.regionalFactor;
  const adjustments: PricingControlAdjustment[] = [];

  const wasteDirectCost = input.lines.reduce((sum, line) =>
    sum + line.quantity * line.materialUnitCost * (line.materialWasteRate ?? 0), 0
  ) * policy.regionalFactor;
  if (wasteDirectCost > 0) {
    adjustments.push({
      kind: "material_waste",
      description: "Material-only waste; installed labor quantity is unchanged.",
      directCost: money(wasteDirectCost),
    });
  }

  let runningDirectCost = catalogDirectCost + wasteDirectCost;
  const tradeGroups = [...new Set(input.lines.map((line) => line.tradeGroup))];
  let tradeMinimumApplied = false;
  if (tradeGroups.length === 1) {
    const minimum = policy.standaloneTradeMinimumDirectCost[tradeGroups[0]] ??
      policy.defaultStandaloneTradeMinimumDirectCost;
    if (runningDirectCost < minimum) {
      const adjustment = minimum - runningDirectCost;
      adjustments.push({
        kind: "trade_minimum",
        description: `Standalone ${tradeGroups[0]} minimum.`,
        directCost: money(adjustment),
      });
      runningDirectCost = minimum;
      tradeMinimumApplied = true;
    }
  }

  if (!tradeMinimumApplied && runningDirectCost < policy.mobilizationDirectCost.belowDirectCost) {
    adjustments.push({
      kind: "mobilization",
      description: "Small-project mobilization.",
      directCost: money(policy.mobilizationDirectCost.amount),
    });
    runningDirectCost += policy.mobilizationDirectCost.amount;
  }

  const debrisCost = policy.debrisDirectCost[input.debrisLevel];
  if (debrisCost > 0) {
    adjustments.push({
      kind: "debris",
      description: `${input.debrisLevel} debris handling allowance.`,
      directCost: money(debrisCost),
    });
    runningDirectCost += debrisCost;
  }

  for (const gap of input.catalogGaps) {
    const allowance = gap.directCostAllowance ?? 0;
    assertNonnegativeFinite(allowance, `${gap.id} directCostAllowance`);
    if (allowance > 0) {
      adjustments.push({
        kind: "catalog_gap_allowance",
        description: gap.description,
        directCost: money(allowance * policy.regionalFactor),
      });
      runningDirectCost += allowance * policy.regionalFactor;
    }
  }

  const baseRate = policy.generalConditionsRate[input.projectKind];
  const generalConditionsRate = Math.min(
    policy.generalConditionsRate.maximum,
    baseRate +
      (input.occupiedWorkArea ? policy.generalConditionsRate.occupiedAdder : 0) +
      (tradeGroups.length > 1 ? policy.generalConditionsRate.multiTradeAdder : 0),
  );
  const generalConditions = runningDirectCost * generalConditionsRate;
  if (generalConditions > 0) {
    adjustments.push({
      kind: "general_conditions",
      description: `${money(generalConditionsRate * 100)}% general conditions.`,
      directCost: money(generalConditions),
    });
    runningDirectCost += generalConditions;
  }

  const adjustedDirectCost = money(runningDirectCost);
  return {
    status: "priced",
    grossMargin: policy.grossMargin,
    catalogDirectCost: money(catalogDirectCost),
    adjustedDirectCost,
    sellingPrice: money(adjustedDirectCost / (1 - policy.grossMargin)),
    adjustments,
  };
}

export function policyAtGrossMargin(grossMargin: number): UniversalPricingPolicy {
  return { ...defaultUniversalPricingPolicy, grossMargin };
}
