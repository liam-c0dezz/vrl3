import {
  applyUniversalPricingControls,
  policyAtGrossMargin,
  type CatalogGapAllowance,
  type ControlledPricingInput,
  type PricingLine,
} from "./universal_pricing_controls.ts";

type RawLine = Omit<PricingLine, "directUnitCost" | "materialUnitCost"> & {
  directUnitCost: number;
  materialUnitCost: number;
};

function line(
  id: string,
  description: string,
  tradeGroup: string,
  quantity: number,
  directUnitCost: number,
  materialUnitCost: number,
  materialWasteRate?: number,
): RawLine {
  return { id, description, tradeGroup, quantity, directUnitCost, materialUnitCost, materialWasteRate };
}

function gap(id: string, description: string, directCostAllowance: number): CatalogGapAllowance {
  return { id, description, required: true, directCostAllowance };
}

const cases: Array<{
  name: string;
  input: ControlledPricingInput;
  market: { low: number; high: number };
}> = [
  {
    name: "Kitchen remodel",
    market: { low: 13_061, high: 16_375 },
    input: {
      projectKind: "remodel",
      occupiedWorkArea: true,
      debrisLevel: "medium",
      lines: [
        line("959", "Cabinet demolition", "demolition", 8, 52.10, 0),
        line("1001", "Base cabinets", "cabinetry", 4, 487.10, 417, 0.05),
        line("1295", "Wall cabinets", "cabinetry", 4, 244.20, 164, 0.05),
        line("2392", "Laminate countertop", "countertops", 14.4, 28.08, 23.40, 0.10),
        line("1659", "Backsplash demolition", "demolition", 25, 2.33, 0),
        line("1673", "Ceramic backsplash", "tile", 25, 19.74, 8.84, 0.10),
        line("10886", "Kitchen sink", "plumbing", 1, 696, 408),
        line("10904", "Kitchen faucet", "plumbing", 1, 335, 152),
        line("3066", "Dishwasher removal", "appliance", 1, 55.10, 0),
        line("3068", "Dishwasher installation", "appliance", 1, 1_039, 595),
        line("9444", "Floor preparation", "flooring", 120, 0.74, 0.11),
        line("9520", "LVP flooring", "flooring", 120, 7.98, 2.65, 0.10),
        line("8890", "Drywall repair", "finishes", 300, 0.60, 0.05),
        line("8868", "Primer", "finishes", 300, 0.59, 0.32),
        line("8872", "Paint", "finishes", 300, 0.81, 0.36, 0.05),
      ],
      catalogGaps: [
        gap("countertop-removal", "Countertop removal allowance.", 200),
        gap("sink-removal", "Sink and faucet removal allowance.", 100),
        gap("floor-removal", "Existing flooring removal allowance.", 300),
        gap("misc-closeout", "Minor transitions, caulk, and closeout allowance.", 100),
      ],
    },
  },
  {
    name: "Bathroom remodel",
    market: { low: 9_500, high: 12_500 },
    input: {
      projectKind: "remodel",
      occupiedWorkArea: true,
      debrisLevel: "medium",
      lines: [
        line("1659", "Tile demolition", "demolition", 70, 2.33, 0),
        line("1677", "Cement backer board", "tile", 70, 2.27, 1.12, 0.10),
        line("1673", "Wall tile", "tile", 70, 19.74, 8.84, 0.10),
        line("11366", "Toilet removal", "plumbing", 1, 45.80, 0),
        line("11386", "Toilet installation", "plumbing", 1, 396, 259),
        line("1359", "Vanity", "cabinetry", 1, 589, 219),
        line("10862", "Vanity faucet", "plumbing", 1, 293, 110),
        line("9444", "Floor preparation", "flooring", 40, 0.74, 0.11),
        line("9520", "LVP flooring", "flooring", 40, 7.98, 2.65, 0.10),
        line("7336", "Bathroom fan", "electrical", 1, 123.30, 37.20),
        line("7846", "Light fixture", "electrical", 1, 64.60, 18.60),
        line("8890", "Drywall repair", "finishes", 180, 0.60, 0.05),
        line("8868", "Primer", "finishes", 180, 0.59, 0.32),
        line("8872", "Paint", "finishes", 180, 0.81, 0.36, 0.05),
      ],
      catalogGaps: [
        gap("waterproofing", "Wet-area waterproofing allowance.", 500),
        gap("floor-removal", "Existing floor removal allowance.", 120),
        gap("electrical-closeout", "Fan/light removal and GFCI closeout allowance.", 350),
      ],
    },
  },
  {
    name: "Bedroom painting",
    market: { low: 650, high: 1_300 },
    input: {
      projectKind: "repair",
      occupiedWorkArea: true,
      debrisLevel: "none",
      lines: [
        line("8890", "Drywall patch", "finishes", 20, 0.60, 0.05),
        line("8868", "Spot primer", "finishes", 20, 0.59, 0.32),
        line("8872", "Wall and ceiling paint", "finishes", 668, 0.81, 0.36, 0.05),
      ],
      catalogGaps: [],
    },
  },
  {
    name: "600 SF LVP flooring",
    market: { low: 2_400, high: 7_200 },
    input: {
      projectKind: "replace",
      occupiedWorkArea: true,
      debrisLevel: "medium",
      lines: [
        line("1470", "Carpet removal", "flooring", 66.6667, 1.48, 0),
        line("9443", "Floor preparation", "flooring", 600, 0.56, 0.10),
        line("9519", "LVP flooring", "flooring", 600, 6.41, 2.41, 0.10),
      ],
      catalogGaps: [],
    },
  },
  {
    name: "Ceiling drywall repair",
    market: { low: 785, high: 1_990 },
    input: {
      projectKind: "repair",
      occupiedWorkArea: true,
      debrisLevel: "light",
      lines: [
        line("3618", "Ceiling drywall removal", "finishes", 48, 0.44, 0),
        line("3630", "Ceiling drywall installation", "finishes", 48, 2.07, 0.92, 0.10),
        line("8868", "Primer", "finishes", 48, 0.59, 0.32),
        line("8872", "Ceiling paint", "finishes", 300, 0.81, 0.36, 0.05),
      ],
      catalogGaps: [],
    },
  },
];

function marketAssessment(price: number, low: number, high: number) {
  if (price < low) return { status: "low", varianceFromRange: (price - low) / low };
  if (price > high) return { status: "high", varianceFromRange: (price - high) / high };
  return { status: "within", varianceFromRange: 0 };
}

const margins = [0.35, 0.40, 0.45];
const results = cases.map((testCase) => {
  const marginResults = margins.map((grossMargin) => {
    const result = applyUniversalPricingControls(testCase.input, policyAtGrossMargin(grossMargin));
    if (result.status !== "priced") return { grossMargin, ...result };
    return {
      grossMargin,
      adjustedDirectCost: result.adjustedDirectCost,
      sellingPrice: result.sellingPrice,
      ...marketAssessment(result.sellingPrice, testCase.market.low, testCase.market.high),
    };
  });
  const detailed = applyUniversalPricingControls(testCase.input, policyAtGrossMargin(0.40));
  return {
    name: testCase.name,
    market: testCase.market,
    catalogDirectCost: detailed.status === "priced" ? detailed.catalogDirectCost : null,
    adjustmentsAt40Percent: detailed.status === "priced" ? detailed.adjustments : [],
    results: marginResults,
  };
});

console.log(JSON.stringify({ margins, results }, null, 2));
