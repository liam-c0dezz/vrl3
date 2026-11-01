import { readFile } from "node:fs/promises";

import {
  runConstructionScopeFlow,
  type ObligationResolution,
  type ScopeFlowAdapters,
  type StructuredScopeFacts,
  type TaggedCostItem,
} from "./construction_scope_flow.ts";

type RawCostRow = {
  sourceRow: number;
  category: string;
  description: string;
  directCost: number;
  unit: string;
};

type ExtractedCostbook = {
  source: string;
  rowCount: number;
  rows: RawCostRow[];
};

const customerRequest = "The toilet in our upstairs hall bathroom rocks and leaks around the base. " +
  "We want it replaced with a standard white two-piece toilet in the same location. " +
  "The house is occupied, the contractor should supply it, and there is no visible floor damage.";

// Returned by the independent AI fact extractor after applying the ontology's
// operational definition of wetArea.
const aiFacts: StructuredScopeFacts = {
  summary: "Replace one leaking, rocking toilet in the occupied upstairs hall bathroom with a contractor-supplied standard white two-piece toilet in the same location.",
  action: "replace",
  objects: [{
    id: "toilet-1",
    name: "toilet",
    trade: "plumbing",
    location: "upstairs hall bathroom",
    quantity: { value: 1, unit: "each" },
    attributes: {
      grade: "standard",
      fixture_type: "two-piece toilet",
      customer_supply: false,
    },
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
  assumptions: [
    "No concealed floor or subfloor damage is included because none is visible.",
    "The replacement remains in the existing location and uses the existing water and drain connections.",
    "The existing toilet will be removed as part of the replacement scope.",
  ],
};

// Returned by the independent AI selector after it saw only obligation IDs and
// the retrieved candidate rows. Every obligation must be resolved exactly once.
const aiResolutions: ObligationResolution[] = [
  { obligationID: "project:scope_verification", resolution: "plan_only", explanation: "Verify the existing fixture, shutoff, drain location, and site conditions before work.", selections: [] },
  { obligationID: "project:protection", resolution: "plan_only", explanation: "Provide ordinary protection for the occupied bathroom and access path.", selections: [] },
  { obligationID: "project:utility_isolation", resolution: "included_elsewhere", explanation: "Shutting off and restoring the toilet water supply is included in removal and installation.", selections: [] },
  { obligationID: "toilet-1:removal", resolution: "priced_items", explanation: "Small-volume removal of one existing toilet.", selections: [{ costItemID: "repair-2026-q3:11366", quantity: 1 }] },
  { obligationID: "toilet-1:disposal", resolution: "included_elsewhere", explanation: "Routine handling and disposal is included with demolition.", selections: [] },
  { obligationID: "toilet-1:concealed_condition_review", resolution: "plan_only", explanation: "Inspect the flange and exposed floor after removal; concealed repairs are excluded until discovered.", selections: [] },
  { obligationID: "toilet-1:preparation", resolution: "included_elsewhere", explanation: "Ordinary preparation is included in the toilet installation item.", selections: [] },
  { obligationID: "toilet-1:primary_work", resolution: "priced_items", explanation: "Small-volume standard two-piece toilet installation including seat and supply.", selections: [{ costItemID: "repair-2026-q3:11386", quantity: 1 }] },
  { obligationID: "project:connection_and_startup", resolution: "included_elsewhere", explanation: "Existing water and drain reconnection is included in installation.", selections: [] },
  { obligationID: "project:testing", resolution: "included_elsewhere", explanation: "Operational and leak testing is included in completed installation.", selections: [] },
  { obligationID: "project:cleanup", resolution: "included_elsewhere", explanation: "Ordinary cleanup is included with removal and installation.", selections: [] },
];

function taggedItem(row: RawCostRow): TaggedCostItem {
  const isRemoval = row.sourceRow === 11365 || row.sourceRow === 11366;
  const isSmall = row.description.toLowerCase().includes("small volume");
  const isStandard = row.sourceRow === 11385 || row.sourceRow === 11386;
  return {
    id: `repair-2026-q3:${row.sourceRow}`,
    sourceVersion: "repair-2026-q3",
    sourceRow: row.sourceRow,
    category: row.category,
    description: `${row.category} — ${row.description}`,
    trade: "plumbing",
    action: isRemoval ? "demolish" : "install",
    object: "toilet",
    processRole: isRemoval ? "removal" : "primary_work",
    unit: row.unit,
    directCostPerUnit: row.directCost,
    attributes: {
      volume_tier: isSmall ? "small" : "large",
      ...(isRemoval ? {} : {
        grade: isStandard ? "standard" : "average",
        fixture_type: "two-piece toilet",
        customer_supply: false,
      }),
    },
    residentialEligible: true,
    confidence: isRemoval || isStandard ? 0.99 : 0.9,
  };
}

async function main() {
  const extractedPath = process.argv[2];
  if (!extractedPath) throw new Error("Usage: independent_ai_job_test.ts <extracted-costbook.json>");
  const costbook = JSON.parse(await readFile(extractedPath, "utf8")) as ExtractedCostbook;
  const candidateRows = new Set([11365, 11366, 11379, 11380, 11385, 11386]);
  const candidates = costbook.rows.filter((row) => candidateRows.has(row.sourceRow)).map(taggedItem);
  if (candidates.length !== candidateRows.size) {
    throw new Error(`Expected ${candidateRows.size} candidate rows, found ${candidates.length}`);
  }

  const adapters: ScopeFlowAdapters = {
    extractStructuredFacts: async () => aiFacts,
    searchCostItems: async (obligation) => {
      if (obligation.id === "toilet-1:removal") {
        return candidates.filter((item) => item.processRole === "removal");
      }
      if (obligation.id === "toilet-1:primary_work") {
        return candidates.filter((item) => item.processRole === "primary_work");
      }
      return [];
    },
    selectItemsAndQuantities: async () => aiResolutions,
  };

  const pricingPolicy = { regionalFactor: 1, sellingPriceMultiplier: 1.25 };
  const result = await runConstructionScopeFlow({
    initialRequest: customerRequest,
    answers: { "toilet-1:volume_tier": "small" },
    pricingPolicy,
    adapters,
  });
  if (result.stage !== "priced") {
    throw new Error(`Expected priced result, received ${result.stage}: ${JSON.stringify(result)}`);
  }

  console.log(JSON.stringify({
    customerRequest,
    aiFacts,
    obligationCount: result.obligations.length,
    completenessAudit: result.audit,
    separatelyPricedItems: result.pricing.items,
    directCostSubtotal: result.pricing.items.reduce((sum, item) => sum + item.directUnitCost * item.quantity, 0),
    pricingPolicy,
    estimatedSellingPrice: result.pricing.total,
    includedOrPlanOnly: result.resolutions
      .filter((resolution) => resolution.resolution !== "priced_items")
      .map((resolution) => ({
        obligationID: resolution.obligationID,
        resolution: resolution.resolution,
        explanation: resolution.explanation,
      })),
    source: { workbook: costbook.source, workbookRows: costbook.rowCount },
  }, null, 2));
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
