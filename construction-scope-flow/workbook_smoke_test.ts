import { readFile } from "node:fs/promises";

import {
  runConstructionScopeFlow,
  type ObligationResolution,
  type ScopeFlowAdapters,
  type ScopeFlowResult,
  type ScopeObligation,
  type SearchableAttribute,
  type StructuredScopeFacts,
  type TaggedCostItem,
} from "./construction_scope_flow.ts";

type RawCostRow = {
  sourceRow: number;
  category: string;
  description: string;
  materialCost: number;
  laborCost: number;
  directCost: number;
  equipmentCost: number;
  unit: string;
  crewCode: string;
};

type ExtractedCostbook = {
  source: string;
  sheet: string;
  rowCount: number;
  rows: RawCostRow[];
};

const scenarios: Array<{ request: string; facts: StructuredScopeFacts }> = [
  {
    request: "Replace one standard residential toilet in an occupied bathroom.",
    facts: {
      summary: "Replace one toilet in an occupied bathroom.",
      action: "replace",
      objects: [{
        id: "toilet",
        name: "toilet",
        trade: "plumbing",
        location: "bathroom",
        quantity: { value: 1, unit: "Ea" },
        attributes: { grade: "standard" },
      }],
      connectedSystems: ["water", "drain"],
      conditions: { occupiedWorkArea: true },
      assumptions: ["Existing toilet location remains unchanged."],
    },
  },
  {
    request: "Repair and repaint 40 square feet of damaged drywall in an occupied bedroom.",
    facts: {
      summary: "Repair and repaint a localized drywall area.",
      action: "repair",
      objects: [{
        id: "drywall",
        name: "gypsum wallboard drywall",
        trade: "drywall",
        location: "bedroom",
        quantity: { value: 40, unit: "SF" },
      }],
      connectedSystems: [],
      conditions: {
        occupiedWorkArea: true,
        intrusiveWork: true,
        disturbsExistingFinish: true,
      },
      assumptions: ["Damage is localized and no hazardous material is suspected."],
    },
  },
  {
    request: "Replace one exterior residential window without changing the opening.",
    facts: {
      summary: "Replace one exterior window in the existing opening.",
      action: "replace",
      objects: [{
        id: "window",
        name: "exterior window",
        trade: "openings",
        quantity: { value: 1, unit: "Ea" },
      }],
      connectedSystems: [],
      conditions: {
        occupiedWorkArea: true,
        exteriorEnvelope: true,
        disturbsExistingFinish: true,
      },
      assumptions: ["Existing rough opening remains unchanged."],
    },
  },
  {
    request: "Install 250 square feet of vinyl plank flooring in an occupied room.",
    facts: {
      summary: "Install vinyl plank flooring over a suitable existing subfloor.",
      action: "install",
      objects: [{
        id: "flooring",
        name: "vinyl plank floor covering",
        trade: "flooring",
        quantity: { value: 250, unit: "SF" },
        attributes: { material: "vinyl" },
      }],
      connectedSystems: [],
      conditions: { occupiedWorkArea: true },
      assumptions: ["Subfloor needs ordinary preparation only."],
    },
  },
];

const stopWords = new Set([
  "a", "an", "and", "area", "for", "in", "of", "on", "or", "the", "to", "work",
  "complete", "provide", "required", "requested", "existing", "affected", "account",
]);

const synonyms: Record<string, string[]> = {
  toilet: ["toilet", "water", "closet"],
  drywall: ["drywall", "gypsum", "wallboard", "sheetrock"],
  window: ["window", "glazing"],
  flooring: ["floor", "flooring", "floorcovering", "plank", "vinyl"],
  removal: ["remove", "removal", "demolition"],
  preparation: ["prepare", "preparation", "repair"],
  primary_work: ["installation", "install", "repair", "replace"],
  protection: ["protect", "protection", "temporary"],
  disposal: ["dispose", "disposal", "haul", "debris"],
  cleanup: ["cleanup", "clean", "final clean"],
  weatherproofing: ["flash", "flashing", "seal", "weather", "waterproof"],
  finish_restoration: ["patch", "paint", "finish", "restore"],
};

function tokens(value: string): string[] {
  return [...new Set(value.toLowerCase().replace(/[^a-z0-9]+/g, " ").split(" ")
    .filter((token) => token.length > 1 && !stopWords.has(token)))];
}

function includesAny(text: string, values: string[]): boolean {
  return values.some((value) => text.includes(value));
}

function inferRole(text: string): TaggedCostItem["processRole"] {
  if (includesAny(text, ["demolition", "remove ", "removal"])) return "removal";
  if (includesAny(text, ["preparation", "prepare", "patch", "repair "])) return "preparation";
  if (includesAny(text, ["testing", " test "])) return "testing";
  if (includesAny(text, ["flashing", "weather barrier", "waterproof"])) return "weatherproofing";
  return "primary_work";
}

function inferTrade(text: string): string {
  if (includesAny(text, ["toilet", "water closet", "lavatory", "plumb", "pipe", "faucet"])) return "plumbing";
  if (includesAny(text, ["drywall", "gypsum", "wallboard", "sheetrock"])) return "drywall";
  if (includesAny(text, ["window", "glazing"])) return "openings";
  if (includesAny(text, ["floor", "carpet", "vinyl tile", "resilient"])) return "flooring";
  if (includesAny(text, ["paint", "coating", "primer"])) return "painting";
  return "general";
}

function inferObject(text: string): string {
  if (includesAny(text, ["water closet", "toilet"]) && !text.includes("partition")) return "toilet";
  if (includesAny(text, ["drywall", "gypsum", "wallboard", "sheetrock"])) return "drywall";
  if (text.includes("window") && !text.includes("air conditioner")) return "window";
  if (includesAny(text, ["vinyl plank", "vinyl floor", "resilient floor", "floor covering"])) return "flooring";
  return "other";
}

function inferAttributes(text: string): TaggedCostItem["attributes"] {
  const attributes: Partial<Record<SearchableAttribute, string | number | boolean>> = {};
  if (text.includes("small volume")) attributes.volume_tier = "small";
  if (text.includes("large volume")) attributes.volume_tier = "large";
  if (text.includes("premium")) attributes.grade = "premium";
  else if (text.includes("economy")) attributes.grade = "economy";
  else if (text.includes("standard")) attributes.grade = "standard";
  if (text.includes("vinyl")) attributes.material = "vinyl";
  else if (text.includes("wood")) attributes.material = "wood";
  else if (text.includes("aluminum")) attributes.material = "aluminum";
  const thickness = text.match(/\b(1\/4|3\/8|1\/2|5\/8|3\/4)\s*(?:inch|\")/);
  if (thickness) attributes.thickness = `${thickness[1]} inch`;
  return attributes;
}

function tagRow(row: RawCostRow): TaggedCostItem {
  const text = `${row.category} ${row.description}`.toLowerCase();
  const processRole = inferRole(text);
  return {
    id: `repair-2026-q3:${row.sourceRow}`,
    sourceVersion: "repair-2026-q3",
    sourceRow: row.sourceRow,
    category: row.category,
    description: `${row.category} — ${row.description}`,
    trade: inferTrade(text),
    action: processRole === "removal" ? "demolish" : processRole === "preparation" ? "repair" : "install",
    object: inferObject(text),
    processRole,
    unit: row.unit,
    directCostPerUnit: row.directCost,
    attributes: inferAttributes(text),
    residentialEligible: !includesAny(text, ["industrial", "institutional", "high rise"]),
    confidence: 0,
  };
}

function obligationTerms(obligation: ScopeObligation, facts: StructuredScopeFacts): string[] {
  const object = obligation.objectID
    ? facts.objects.find((candidate) => candidate.id === obligation.objectID)
    : undefined;
  const expanded = [
    ...obligation.searchTerms,
    obligation.processRole,
    object?.name ?? "",
    object?.id ?? "",
    ...(synonyms[obligation.processRole] ?? []),
    ...(object ? synonyms[object.id] ?? [] : []),
  ];
  return tokens(expanded.join(" "));
}

function makeSearch(items: TaggedCostItem[]) {
  return async (obligation: ScopeObligation, facts: StructuredScopeFacts): Promise<TaggedCostItem[]> => {
    const queryTokens = obligationTerms(obligation, facts);
    const object = obligation.objectID
      ? facts.objects.find((candidate) => candidate.id === obligation.objectID)
      : undefined;
    return items.map((item) => {
      const text = `${item.category} ${item.description}`.toLowerCase();
      const itemTokens = new Set(tokens(text));
      let score = queryTokens.reduce((sum, token) => sum + (itemTokens.has(token) ? 1 : 0), 0);
      if (item.processRole === obligation.processRole) score += 7;
      if (object && item.object === object.id) score += 10;
      if (object?.trade && item.trade === object.trade) score += 2;
      if (object && item.object !== object.id && item.object !== "other") score -= 8;
      if (object?.id === "toilet" && text.includes("partition")) score -= 15;
      if (object?.id === "window" && text.includes("air conditioner")) score -= 15;
      return { item: { ...item, confidence: Math.max(0, Math.min(1, score / 22)) }, score };
    })
      .filter(({ item, score }) => score >= 9 && item.processRole === obligation.processRole)
      .sort((left, right) => right.score - left.score || left.item.directCostPerUnit - right.item.directCostPerUnit)
      .slice(0, 12)
      .map(({ item }) => item);
  };
}

function preferredAnswer(question: Extract<ScopeFlowResult, { stage: "questions" }>["questions"][number]) {
  if (question.responseType === "number") return 1;
  const preferences = ["small", "standard", "average", "vinyl"];
  for (const preferred of preferences) {
    const match = question.options.find((option) => String(option).toLowerCase() === preferred);
    if (match !== undefined) return match;
  }
  return question.options[0];
}

function makeSelector(): ScopeFlowAdapters["selectItemsAndQuantities"] {
  return async ({ facts, obligations, candidateSets, answers }): Promise<ObligationResolution[]> => {
    const objectByID = new Map(facts.objects.map((object) => [object.id, object]));
    return obligations.map((obligation) => {
      const candidates = candidateSets.find((set) => set.obligationID === obligation.id)?.items ?? [];
      if (!obligation.catalogItemExpected) {
        return {
          obligationID: obligation.id,
          resolution: "plan_only",
          explanation: "Operational obligation retained in the work plan.",
          selections: [],
        };
      }
      const object = obligation.objectID ? objectByID.get(obligation.objectID) : undefined;
      const selected = candidates.find((candidate) =>
        Object.entries(candidate.attributes).every(([attribute, value]) => {
          const answer = answers[`${obligation.objectID ?? "project"}:${attribute}`];
          const factValue = object?.attributes?.[attribute as SearchableAttribute];
          return answer === undefined && factValue === undefined || answer === value || factValue === value;
        })
      ) ?? candidates[0];
      return {
        obligationID: obligation.id,
        resolution: "priced_items",
        explanation: "Highest-ranked candidate consistent with supplied answers.",
        selections: selected ? [{
          costItemID: selected.id,
          quantity: object?.quantity?.value ?? 1,
        }] : [],
      };
    });
  };
}

async function runScenario(
  scenario: typeof scenarios[number],
  items: TaggedCostItem[],
): Promise<Record<string, unknown>> {
  const answers: Record<string, string | number | boolean> = {};
  const asked: Array<{ id: string; options: Array<string | number | boolean> }> = [];
  const adapters: ScopeFlowAdapters = {
    extractStructuredFacts: async () => scenario.facts,
    searchCostItems: makeSearch(items),
    selectItemsAndQuantities: makeSelector(),
  };
  let result: ScopeFlowResult | undefined;
  for (let pass = 0; pass < 10; pass += 1) {
    result = await runConstructionScopeFlow({
      initialRequest: scenario.request,
      answers,
      pricingPolicy: { regionalFactor: 1, sellingPriceMultiplier: 1.25 },
      adapters,
    });
    if (result.stage !== "questions") break;
    for (const question of result.questions) {
      if (!asked.some((existing) => existing.id === question.id)) {
        asked.push({ id: question.id, options: question.options });
      }
      answers[question.id] = preferredAnswer(question);
    }
  }
  if (!result) throw new Error("Scenario did not run");
  const candidates = result.candidateSets
    .filter((set) => set.items.length > 0)
    .map((set) => ({
      obligation: set.obligationID,
      top: set.items.slice(0, 2).map((item) => ({
        id: item.id,
        description: item.description,
        unit: item.unit,
        directCost: item.directCostPerUnit,
      })),
    }));
  return {
    request: scenario.request,
    stage: result.stage,
    obligationCount: result.obligations.length,
    questions: asked,
    answers,
    missingCandidateObligations: result.stage === "blocked" ? result.missingCandidateObligationIDs : [],
    auditValid: result.stage === "priced" ? result.audit.valid : result.stage === "blocked" ? result.audit?.valid ?? null : null,
    pricedTotal: result.stage === "priced" ? result.pricing.total : null,
    candidates,
  };
}

async function main() {
  const path = process.argv[2];
  if (!path) throw new Error("Usage: workbook_smoke_test.ts <extracted-costbook.json>");
  const costbook = JSON.parse(await readFile(path, "utf8")) as ExtractedCostbook;
  const items = costbook.rows.map(tagRow);
  const results = [];
  for (const scenario of scenarios) results.push(await runScenario(scenario, items));
  console.log(JSON.stringify({
    source: costbook.source,
    sheet: costbook.sheet,
    rowCount: costbook.rowCount,
    taggedItemCount: items.length,
    note: "Facts and tags are local test fixtures/heuristics, not production AI outputs.",
    results,
  }, null, 2));
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
