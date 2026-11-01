import { constructionCatalog } from "./construction_catalog.ts";

const NATIONAL_CONSTRUCTION_WAGE = 31.42;
const LABOR_BURDEN_FACTOR = 1.5;
const REMODELER_GROSS_MARGIN = 0.299;
const MAX_ESTIMATE_ITEMS = 80;
const MIN_PLAN_SECTIONS = 2;
const MAX_PLAN_SECTIONS = 24;
const MIN_PLAN_STEPS = 3;
const MAX_PLAN_STEPS = 10;

type FinishTier = "economy" | "standard" | "premium" | "luxury";
type DifficultyTier = "easy" | "standard" | "difficult" | "extreme";

export type ConstructionTurn = {
  stage: "intake" | "estimate_ready";
  reply_text: string;
  title: string | null;
  template_id: string | null;
  question_ids: string[];
  location: string | null;
  assumptions: string[];
  exclusions: string[];
  plan_sections: Array<{
    title: string;
    steps: string[];
  }>;
  line_items: Array<{
    assembly_id: string;
    quantity: number;
    finish_tier: FinishTier;
    difficulty: DifficultyTier;
  }>;
};

const assemblyByID = new Map<string, (typeof constructionCatalog.assemblies)[number]>(
  constructionCatalog.assemblies.map((assembly) => [assembly.id, assembly]),
);
const questionByID = new Map<string, (typeof constructionCatalog.questions)[number]>(
  constructionCatalog.questions.map((question) => [question.id, question]),
);
const templateByID = new Map<string, (typeof constructionCatalog.project_templates)[number]>(
  constructionCatalog.project_templates.map((template) => [template.id, template]),
);
const laborRoleByID = new Map<string, (typeof constructionCatalog.labor_roles)[number]>(
  constructionCatalog.labor_roles.map((role) => [role.id, role]),
);

const tradeLabels: Record<string, string> = {
  general_conditions: "General Conditions",
  demolition: "Demolition",
  framing: "Framing & Carpentry",
  insulation: "Insulation",
  drywall: "Drywall",
  painting: "Painting",
  flooring: "Flooring",
  tile: "Tile",
  cabinetry: "Cabinetry",
  countertops: "Countertops",
  plumbing: "Plumbing",
  electrical: "Electrical",
  hvac: "HVAC",
  roofing: "Roofing",
  siding: "Siding & Exterior",
  windows_doors: "Windows & Doors",
  concrete: "Concrete & Masonry",
  decking: "Decking",
  finish_carpentry: "Finish Carpentry",
  permits: "Permits & Allowances",
};

function roundMoney(value: number): number {
  return Math.round(value * 100) / 100;
}

function humanizeTrade(trade: string): string {
  return tradeLabels[trade] ?? trade
    .split("_")
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

function compactTemplateCatalog(): string {
  return constructionCatalog.project_templates.map((template) => [
    `${template.id} — ${template.name} [${template.category}; risk ${template.risk_level}]`,
    `required: ${template.required_assembly_ids.join(", ")}`,
    `optional: ${template.optional_assembly_ids.join(", ") || "none"}`,
    `intake: ${template.intake_question_ids.join(", ")}`,
  ].join("\n  ")).join("\n");
}

function compactAssemblyCatalog(): string {
  return constructionCatalog.assemblies.map((assembly) =>
    `${assembly.id} | ${assembly.trade} | ${assembly.name} | unit=${assembly.unit} | ${assembly.description}`
  ).join("\n");
}

function compactQuestionCatalog(): string {
  return constructionCatalog.questions.map((question) =>
    `${question.id} [${question.response_type}]: ${question.question}${question.options.length ? ` Options: ${question.options.join(" / ")}` : ""}`
  ).join("\n");
}

export function buildConstructionSystemPrompt(): string {
  return `You are EasyBid's residential construction estimator. You convert a contractor's description, photos, and conversation into a PRELIMINARY itemized estimate using only the supplied catalog. The catalog is provisional and the contractor must review every result before sending it to a customer.

Return exactly one JSON object matching the supplied schema. Never use markdown. Never state or invent prices: the server calculates every price deterministically.

BEHAVIOR
1. Match the work to the closest project template. For a custom or partial job, template_id may be null and you may select relevant assemblies directly.
2. Use stage="intake" when facts that materially change quantities or scope are missing. Put the IDs of every currently necessary unanswered catalog question in question_ids so the app can display one structured question form. For a matched template, use only relevant IDs from its intake list. Do not ask questions in reply_text and do not return an ID whose answer is already present in the conversation. Prefer one complete form over serial follow-ups.
3. Use stage="estimate_ready" only when you can produce a defensible preliminary takeoff. Provide a concise title, assumptions, exclusions, 1-${MAX_ESTIMATE_ITEMS} line_items, and an ordered job plan.
4. For a selected template, include its required assemblies unless the conversation clearly makes one irrelevant. If you omit a required assembly, explain why in assumptions or exclusions. Add optional assemblies only when supported by the request, media, or stated assumptions.
5. assembly_id must be copied exactly from the catalog. Use each assembly's exact unit. quantity must be the numeric amount in that unit. Do not duplicate an assembly; combine quantities.
6. Apply finish_tier to finish-sensitive work. Keep demolition, protection, permits, rough framing, and cleanup at standard unless the scope itself changes them.
7. Use difficulty="standard" unless access, height, occupied conditions, site constraints, or the contractor's description justify another tier.
8. A photo can support visible counts and scope, but it cannot prove dimensions, concealed conditions, code compliance, structural adequacy, hazardous materials, or utility capacity. Ask or exclude those items.
9. Never promise final accuracy, code compliance, permit approval, engineering, or completion time. Never automatically send an estimate.
10. If the request is commercial, industrial, heavy civil, or otherwise outside ordinary residential construction/remodeling, explain the limitation and keep stage="intake" with no line_items.
11. Build plan_sections from the same selected assemblies and stated scope. The plan is the customer-facing estimate: create a separate card for every distinct process, trade, or major part of the job and put the cards in execution order. Include supported preparation, protection, removal, installation, trade work, testing, cleanup, and disposal. Use ${MIN_PLAN_STEPS}-${MAX_PLAN_STEPS} specific contractor-facing steps per phase. Make each step concrete enough that the customer understands what will happen, while keeping all prices and internal line-item names out of the plan. Do not add work that is absent from line_items, assumptions, or clearly necessary sequencing. Do not promise code compliance, engineering approval, permit approval, concealed-condition outcomes, or a completion schedule.

OUTPUT RULES
- During intake: title/location may be null, line_items and plan_sections must be [], question_ids contains the relevant unanswered catalog IDs, and reply_text is a short instruction such as "Answer these project details to continue."
- Contractor answers may include catalog IDs in square brackets. Treat those answers as authoritative and do not request the same ID again unless the answer explicitly says it is unknown and the fact is essential.
- When ready: question_ids must be [], and reply_text is a short confirmation such as "I built a preliminary cost breakdown for your review." Do not include prices in reply_text.
- assumptions and exclusions contain plain-language contractor-facing notes, not hidden reasoning.
- plan_sections contains ${MIN_PLAN_SECTIONS}-${MAX_PLAN_SECTIONS} ordered process cards, each with a short title and ${MIN_PLAN_STEPS}-${MAX_PLAN_STEPS} detailed bullet steps. Do not combine unrelated trades or processes into one generic card. Do not use markdown bullets inside the step strings.

PROJECT TEMPLATES
${compactTemplateCatalog()}

INTAKE QUESTION LIBRARY
${compactQuestionCatalog()}

ASSEMBLY CATALOG
${compactAssemblyCatalog()}`;
}

export function buildConstructionSchema() {
  const templateIDs = constructionCatalog.project_templates.map((template) => template.id);
  const assemblyIDs = constructionCatalog.assemblies.map((assembly) => assembly.id);
  const questionIDs = constructionCatalog.questions.map((question) => question.id);
  return {
    type: "object",
    properties: {
      stage: { type: "string", enum: ["intake", "estimate_ready"] },
      reply_text: { type: "string" },
      title: { type: ["string", "null"] },
      template_id: {
        type: ["string", "null"],
        enum: [...templateIDs, null],
      },
      question_ids: {
        type: "array",
        maxItems: 16,
        items: { type: "string", enum: questionIDs },
      },
      location: { type: ["string", "null"] },
      assumptions: {
        type: "array",
        maxItems: 30,
        items: { type: "string" },
      },
      exclusions: {
        type: "array",
        maxItems: 30,
        items: { type: "string" },
      },
      plan_sections: {
        type: "array",
        maxItems: MAX_PLAN_SECTIONS,
        items: {
          type: "object",
          properties: {
            title: { type: "string" },
            steps: {
              type: "array",
              minItems: MIN_PLAN_STEPS,
              maxItems: MAX_PLAN_STEPS,
              items: { type: "string" },
            },
          },
          required: ["title", "steps"],
          additionalProperties: false,
        },
      },
      line_items: {
        type: "array",
        maxItems: MAX_ESTIMATE_ITEMS,
        items: {
          type: "object",
          properties: {
            assembly_id: { type: "string", enum: assemblyIDs },
            quantity: { type: "number" },
            finish_tier: {
              type: "string",
              enum: ["economy", "standard", "premium", "luxury"],
            },
            difficulty: {
              type: "string",
              enum: ["easy", "standard", "difficult", "extreme"],
            },
          },
          required: ["assembly_id", "quantity", "finish_tier", "difficulty"],
          additionalProperties: false,
        },
      },
    },
    required: [
      "stage",
      "reply_text",
      "title",
      "template_id",
      "question_ids",
      "location",
      "assumptions",
      "exclusions",
      "plan_sections",
      "line_items",
    ],
    additionalProperties: false,
  };
}

function validateShortText(value: string, label: string, max: number): string {
  if (typeof value !== "string") throw new Error(`${label} is invalid`);
  const trimmed = value.trim();
  if (!trimmed || trimmed.length > max) throw new Error(`${label} is invalid`);
  return trimmed;
}

export function parseConstructionTurn(value: unknown): ConstructionTurn {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Construction response is not an object");
  }
  const turn = value as ConstructionTurn;
  if (turn.stage !== "intake" && turn.stage !== "estimate_ready") {
    throw new Error("Construction response stage is invalid");
  }
  if (!Array.isArray(turn.question_ids) || turn.question_ids.length > 16) {
    throw new Error("Construction intake questions are invalid");
  }
  const questionIDs = new Set<string>();
  for (const questionID of turn.question_ids) {
    if (typeof questionID !== "string" || !questionByID.has(questionID) || questionIDs.has(questionID)) {
      throw new Error("Construction intake question ID is invalid or duplicated");
    }
    questionIDs.add(questionID);
  }
  turn.reply_text = validateShortText(turn.reply_text, "reply_text", 1_000);
  if (!Array.isArray(turn.assumptions) || turn.assumptions.length > 30) {
    throw new Error("Construction assumptions are invalid");
  }
  if (!Array.isArray(turn.exclusions) || turn.exclusions.length > 30) {
    throw new Error("Construction exclusions are invalid");
  }
  turn.assumptions = turn.assumptions.map((item) =>
    validateShortText(item, "assumption", 1_000)
  );
  turn.exclusions = turn.exclusions.map((item) =>
    validateShortText(item, "exclusion", 1_000)
  );
  if (!Array.isArray(turn.plan_sections) || turn.plan_sections.length > MAX_PLAN_SECTIONS) {
    throw new Error("Construction work plan is invalid");
  }
  if (!Array.isArray(turn.line_items) || turn.line_items.length > MAX_ESTIMATE_ITEMS) {
    throw new Error("Construction line items are invalid");
  }
  if (turn.stage === "intake") {
    if (turn.line_items.length !== 0 || turn.plan_sections.length !== 0) {
      throw new Error("Intake response cannot contain line items or a work plan");
    }
    return turn;
  }
  if (turn.question_ids.length !== 0) {
    throw new Error("Ready construction response cannot contain intake questions");
  }
  turn.title = validateShortText(turn.title ?? "", "title", 500);
  if (turn.template_id !== null && !constructionCatalog.project_templates.some(
    (template) => template.id === turn.template_id,
  )) {
    throw new Error("Construction template is invalid");
  }
  if (turn.line_items.length === 0) {
    throw new Error("Ready construction response has no line items");
  }
  if (turn.plan_sections.length < MIN_PLAN_SECTIONS) {
    throw new Error("Ready construction response needs a multi-phase work plan");
  }
  turn.plan_sections = turn.plan_sections.map((section) => {
    if (!section || typeof section !== "object" || !Array.isArray(section.steps) ||
      section.steps.length < MIN_PLAN_STEPS || section.steps.length > MAX_PLAN_STEPS) {
      throw new Error("Construction work plan section is invalid");
    }
    return {
      title: validateShortText(section.title, "plan section title", 160),
      steps: section.steps.map((step) => validateShortText(step, "plan step", 1_000)),
    };
  });
  const seen = new Set<string>();
  for (const item of turn.line_items) {
    if (!assemblyByID.has(item.assembly_id) || seen.has(item.assembly_id)) {
      throw new Error("Construction assembly selection is invalid or duplicated");
    }
    seen.add(item.assembly_id);
    if (!Number.isFinite(item.quantity) || item.quantity <= 0 || item.quantity > 1_000_000) {
      throw new Error("Construction quantity is invalid");
    }
    if (!["economy", "standard", "premium", "luxury"].includes(item.finish_tier)) {
      throw new Error("Construction finish tier is invalid");
    }
    if (!["easy", "standard", "difficult", "extreme"].includes(item.difficulty)) {
      throw new Error("Construction difficulty is invalid");
    }
  }
  return turn;
}

export function buildConstructionIntakeQuestions(questionIDs: string[]) {
  return questionIDs.flatMap((questionID) => {
    const question = questionByID.get(questionID);
    if (!question) return [];
    const labels = question.response_type === "boolean"
      ? ["Yes", "No"]
      : [...question.options];
    return [{
      id: question.id,
      question: question.question,
      response_type: question.response_type,
      help_text: question.rationale,
      options: labels.map((label, index) => ({
        id: `${question.id}:${index}`,
        label,
      })),
    }];
  });
}

export function constructionTemplateName(templateID: string | null): string {
  return templateID ? templateByID.get(templateID)?.name ?? "Project" : "Project";
}

export function buildConstructionEstimate(turn: ConstructionTurn) {
  if (turn.stage !== "estimate_ready" || !turn.title) {
    throw new Error("Construction estimate is not ready");
  }

  const billableSelections = turn.line_items.filter(
    (selection) => selection.assembly_id !== "daily_cleanup" &&
      selection.assembly_id !== "final_cleanup",
  );

  const pricedItems = billableSelections.map((selection) => {
    const assembly = assemblyByID.get(selection.assembly_id);
    if (!assembly) throw new Error(`Unknown construction assembly: ${selection.assembly_id}`);
    const role = laborRoleByID.get(assembly.labor_role_id);
    if (!role) throw new Error(`Unknown construction labor role: ${assembly.labor_role_id}`);

    const finishMultiplier = assembly.finish_tier_multipliers[selection.finish_tier];
    const difficultyMultiplier = assembly.difficulty_multipliers[selection.difficulty];
    const loadedLaborRate = NATIONAL_CONSTRUCTION_WAGE * LABOR_BURDEN_FACTOR *
      role.billing_rate_multiplier;
    const laborPerUnit = assembly.crew_hours_per_unit.base * loadedLaborRate *
      difficultyMultiplier;
    const materialPerUnit = assembly.national_seed_material_cost_per_unit.base *
      (1 + assembly.default_waste_percent / 100) * finishMultiplier;
    const equipmentPerUnit = assembly.equipment_cost_per_unit_base;
    const directPerUnit = laborPerUnit + materialPerUnit + equipmentPerUnit;
    const sellingPerUnit = roundMoney(directPerUnit / (1 - REMODELER_GROSS_MARGIN));
    const total = roundMoney(selection.quantity * sellingPerUnit);

    return {
      trade: humanizeTrade(assembly.trade),
      name: assembly.name,
      quantity: selection.quantity,
      unitLabel: assembly.unit,
      unitPrice: sellingPerUnit,
      total,
      source: `EasyBid provisional national seed ${constructionCatalog.metadata.version}`,
      url: null as string | null,
      description: `${assembly.included_scope} Provisional price includes modeled labor, materials, equipment, waste, and gross margin; contractor review required.`,
      onHand: false,
    };
  });

  const categoryOrder: string[] = [];
  for (const item of pricedItems) {
    if (!categoryOrder.includes(item.trade)) categoryOrder.push(item.trade);
  }
  const categories = categoryOrder.map((trade) => {
    const items = pricedItems
      .filter((item) => item.trade === trade)
      .map(({ trade: _trade, ...item }) => item);
    return {
      name: trade,
      items,
      subtotal: roundMoney(items.reduce((sum, item) => sum + item.total, 0)),
    };
  });
  const subtotal = roundMoney(categories.reduce((sum, category) => sum + category.subtotal, 0));
  const standardExclusions = [
    "Engineering, architectural design, and stamped plans unless explicitly listed",
    "Hazardous-material testing and remediation unless explicitly listed",
    "Hidden damage, concealed utility conflicts, and code upgrades discovered after work begins",
    "Permit and inspection fees unless a permit allowance is listed",
    "Final price requires contractor review and local supplier/trade confirmation",
  ];
  const exclusions = [...new Set([...turn.exclusions, ...standardExclusions])];
  const assumptions = turn.assumptions.length
    ? turn.assumptions.join(" | ")
    : "Quantities and finish selections are preliminary and require field verification.";

  return {
    title: turn.title,
    categories,
    subtotal,
    markupPercent: 0,
    markupAmount: 0,
    contingencyPercent: 0,
    contingencyAmount: 0,
    total: subtotal,
    workPlan: turn.plan_sections.map((section) => ({
      id: crypto.randomUUID(),
      title: section.title,
      steps: section.steps,
    })),
    notes: "",
    locationState: turn.location,
    localWageUsed: null,
    exclusions,
    paymentTerms: "50% deposit, progress payments as agreed, balance on completion",
    sanityCheck: `PRELIMINARY REVIEW REQUIRED. Catalog ${constructionCatalog.metadata.version}; pricing as of ${constructionCatalog.metadata.pricing_as_of}; national seed with no regional factor. ${billableSelections.length} priced assemblies. Cleanup is not priced as a separate line item. Assumptions: ${assumptions}`,
  };
}

export const constructionCatalogStats = {
  assemblies: constructionCatalog.assemblies.length,
  templates: constructionCatalog.project_templates.length,
  questions: constructionCatalog.questions.length,
  version: constructionCatalog.metadata.version,
};
