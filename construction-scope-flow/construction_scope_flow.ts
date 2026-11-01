// Standalone construction scope engine prototype.
//
// This file has no Supabase, OpenAI, or application dependencies. Those
// systems plug in later through ScopeFlowAdapters. The deterministic core owns
// obligations, question derivation, completeness checks, and pricing math.

export const constructionOntology = {
  actions: [
    "diagnose",
    "maintain",
    "repair",
    "replace",
    "install",
    "remodel",
    "demolish",
  ],
  processRoles: [
    "scope_verification",
    "protection",
    "design_and_approval",
    "hazard_screening",
    "utility_isolation",
    "demolition",
    "removal",
    "disposal",
    "concealed_condition_review",
    "preparation",
    "rough_in",
    "moisture_control",
    "weatherproofing",
    "primary_work",
    "connection_and_startup",
    "finish_restoration",
    "testing",
    "cleanup",
  ],
  connectedSystems: [
    "water",
    "drain",
    "gas",
    "electrical",
    "hvac",
    "low_voltage",
  ],
  searchableAttributes: [
    "material",
    "grade",
    "size",
    "thickness",
    "installation_method",
    "finish_level",
    "fixture_type",
    "customer_supply",
    "volume_tier",
  ],
} as const;

export type WorkAction = typeof constructionOntology.actions[number];
export type ProcessRole = typeof constructionOntology.processRoles[number];
export type ConnectedSystem = typeof constructionOntology.connectedSystems[number];
export type SearchableAttribute = typeof constructionOntology.searchableAttributes[number];

export type ScopeQuantity = {
  value: number;
  unit: string;
};

export type ScopeObject = {
  id: string;
  name: string;
  action?: WorkAction;
  trade?: string;
  location?: string;
  quantity?: ScopeQuantity;
  attributes?: Partial<Record<SearchableAttribute, string | number | boolean>>;
};

export type ScopeConditions = {
  occupiedWorkArea?: boolean;
  intrusiveWork?: boolean;
  wetArea?: boolean;
  exteriorEnvelope?: boolean;
  disturbsExistingFinish?: boolean;
  structuralImpact?: boolean;
  hazardousMaterialsPossible?: boolean;
  layoutChange?: boolean;
};

// This is the only free-form AI interpretation that enters the deterministic
// engine. Production integration should validate it against a strict schema.
export type StructuredScopeFacts = {
  summary: string;
  action: WorkAction;
  objects: ScopeObject[];
  connectedSystems: ConnectedSystem[];
  conditions: ScopeConditions;
  assumptions: string[];
};

// Layer 1: the 12,000 source rows after automatic tagging.
export type TaggedCostItem = {
  id: string;
  sourceVersion: string;
  sourceRow: number;
  category: string;
  description: string;
  trade: string;
  action: WorkAction;
  object: string;
  processRole: ProcessRole;
  unit: string;
  directCostPerUnit: number;
  attributes: Partial<Record<SearchableAttribute, string | number | boolean>>;
  residentialEligible: boolean;
  confidence: number;
};

export type ScopeObligation = {
  id: string;
  objectID: string | null;
  processRole: ProcessRole;
  reason: string;
  catalogItemExpected: boolean;
  allowExplicitExclusion: boolean;
  searchTerms: string[];
};

type RuleContext = {
  facts: StructuredScopeFacts;
  object: ScopeObject | null;
};

function actionFor({ facts, object }: RuleContext): WorkAction {
  return object?.action ?? facts.action;
}

export type DependencyRule = {
  id: string;
  description: string;
  applies: (context: RuleContext) => boolean;
  obligations: (context: RuleContext) => Array<Omit<ScopeObligation, "id" | "objectID">>;
};

function obligation(
  processRole: ProcessRole,
  reason: string,
  options: {
    catalogItemExpected?: boolean;
    allowExplicitExclusion?: boolean;
    searchTerms?: string[];
  } = {},
): Omit<ScopeObligation, "id" | "objectID"> {
  return {
    processRole,
    reason,
    catalogItemExpected: options.catalogItemExpected ?? false,
    allowExplicitExclusion: options.allowExplicitExclusion ?? true,
    searchTerms: options.searchTerms ?? [],
  };
}

// Layer 3: a small set of rules applies across every tagged cost item.
export const universalDependencyRules: DependencyRule[] = [
  {
    id: "project_lifecycle",
    description: "Every scope is verified and closed out.",
    applies: ({ object }) => object === null,
    obligations: () => [
      obligation("scope_verification", "Confirm quantities, selections, and scope boundaries.", {
        allowExplicitExclusion: false,
      }),
      obligation("cleanup", "Remove debris and temporary protection and hand over the work.", {
        catalogItemExpected: true,
      }),
    ],
  },
  {
    id: "primary_work_per_object",
    description: "Every requested object has a principal operation.",
    applies: ({ object }) => object !== null,
    obligations: (context) => [
      obligation("primary_work", `Complete the requested ${actionFor(context)} work for ${context.object!.name}.`, {
        catalogItemExpected: true,
        allowExplicitExclusion: false,
        searchTerms: [actionFor(context), context.object!.name],
      }),
    ],
  },
  {
    id: "occupied_area_protection",
    description: "Occupied work requires access and finish protection.",
    applies: ({ facts, object }) => object === null && facts.conditions.occupiedWorkArea === true,
    obligations: () => [
      obligation("protection", "Protect occupied areas, access paths, and adjacent finishes.", {
        catalogItemExpected: true,
        searchTerms: ["site protection", "occupied area protection"],
      }),
    ],
  },
  {
    id: "replacement_lifecycle",
    description: "Replacement includes removal, disposition, preparation, and new work.",
    applies: (context) => context.object !== null && actionFor(context) === "replace",
    obligations: ({ object }) => [
      obligation("removal", `Remove the existing ${object!.name}.`, {
        catalogItemExpected: true,
        searchTerms: ["remove", object!.name],
      }),
      obligation("disposal", `Account for disposal, salvage, or owner retention of ${object!.name}.`, {
        catalogItemExpected: true,
        searchTerms: ["disposal", object!.name],
      }),
      obligation("concealed_condition_review", `Review conditions exposed by removing ${object!.name}.`),
      obligation("preparation", `Prepare the supporting work for ${object!.name}.`, {
        catalogItemExpected: true,
        searchTerms: ["prepare", object!.name],
      }),
    ],
  },
  {
    id: "repair_lifecycle",
    description: "Repair includes diagnosis of the existing condition and preparation.",
    applies: (context) => context.object !== null && actionFor(context) === "repair",
    obligations: ({ object }) => [
      obligation("concealed_condition_review", `Confirm the repairable condition of ${object!.name}.`),
      obligation("preparation", `Prepare ${object!.name} for the repair.`, {
        catalogItemExpected: true,
        searchTerms: ["repair preparation", object!.name],
      }),
    ],
  },
  {
    id: "installation_preparation",
    description: "New installations require preparation of the supporting work.",
    applies: (context) => context.object !== null && actionFor(context) === "install",
    obligations: ({ object }) => [
      obligation("preparation", `Prepare the location and supports for ${object!.name}.`, {
        catalogItemExpected: true,
        searchTerms: ["installation preparation", object!.name],
      }),
    ],
  },
  {
    id: "demolition_lifecycle",
    description: "Demolition and remodeling include controlled demolition and disposal.",
    applies: (context) => context.object !== null &&
      (actionFor(context) === "demolish" || actionFor(context) === "remodel"),
    obligations: ({ object }) => [
      obligation("demolition", `Demolish the included portions of ${object!.name}.`, {
        catalogItemExpected: true,
        searchTerms: ["demolition", object!.name],
      }),
      obligation("disposal", `Account for debris from ${object!.name}.`, {
        catalogItemExpected: true,
        searchTerms: ["disposal", object!.name],
      }),
      obligation("concealed_condition_review", `Review conditions exposed around ${object!.name}.`),
      obligation("preparation", `Prepare the remaining work around ${object!.name}.`, {
        catalogItemExpected: true,
        searchTerms: ["preparation", object!.name],
      }),
    ],
  },
  {
    id: "connected_system_lifecycle",
    description: "Connected systems are isolated, reconnected, and tested.",
    applies: ({ facts, object }) => object === null && facts.connectedSystems.length > 0,
    obligations: ({ facts }) => [
      obligation("utility_isolation", "Safely isolate affected connected systems.", {
        searchTerms: ["isolate", ...facts.connectedSystems],
      }),
      ...(facts.conditions.layoutChange
        ? [obligation("rough_in", "Install or relocate required concealed systems.", {
            catalogItemExpected: true,
            searchTerms: ["rough in", ...facts.connectedSystems],
          })]
        : []),
      obligation("connection_and_startup", "Reconnect and start affected systems.", {
        catalogItemExpected: true,
        searchTerms: ["connect", ...facts.connectedSystems],
      }),
      obligation("testing", "Perform functional checks on affected systems.", {
        searchTerms: ["test", ...facts.connectedSystems],
        allowExplicitExclusion: false,
      }),
    ],
  },
  {
    id: "intrusive_work_review",
    description: "Intrusive work controls opening and concealed-condition review.",
    applies: ({ facts, object }) => object === null && facts.conditions.intrusiveWork === true,
    obligations: () => [
      obligation("protection", "Protect adjacent finishes before opening concealed work.", {
        catalogItemExpected: true,
        searchTerms: ["protection", "selective demolition"],
      }),
      obligation("demolition", "Open only the area needed to reach the concealed work.", {
        catalogItemExpected: true,
        searchTerms: ["selective demolition", "access opening"],
      }),
      obligation("concealed_condition_review", "Review exposed concealed conditions before closeup."),
    ],
  },
  {
    id: "wet_area_control",
    description: "Wet-area work requires a moisture-control decision.",
    applies: ({ facts, object }) => object === null && facts.conditions.wetArea === true,
    obligations: () => [
      obligation("moisture_control", "Provide the required waterproofing or drainage layer.", {
        catalogItemExpected: true,
        allowExplicitExclusion: false,
        searchTerms: ["waterproofing", "wet area", "drainage"],
      }),
    ],
  },
  {
    id: "exterior_weatherproofing",
    description: "Exterior-envelope work requires weatherproofing.",
    applies: ({ facts, object }) => object === null && facts.conditions.exteriorEnvelope === true,
    obligations: () => [
      obligation("weatherproofing", "Provide required flashing, sealing, drainage, and weather barriers.", {
        catalogItemExpected: true,
        allowExplicitExclusion: false,
        searchTerms: ["flashing", "weather barrier", "exterior sealing"],
      }),
    ],
  },
  {
    id: "finish_restoration",
    description: "Disturbed finishes are restored or explicitly excluded.",
    applies: ({ facts, object }) => object === null && facts.conditions.disturbsExistingFinish === true,
    obligations: () => [
      obligation("finish_restoration", "Patch and restore disturbed finishes.", {
        catalogItemExpected: true,
        searchTerms: ["patch", "finish restoration", "paint"],
      }),
    ],
  },
  {
    id: "structural_gate",
    description: "Structurally consequential work resolves design and approval responsibility.",
    applies: ({ facts, object }) => object === null && facts.conditions.structuralImpact === true,
    obligations: () => [
      obligation("design_and_approval", "Resolve structural design, engineering, permits, and inspections.", {
        allowExplicitExclusion: false,
        searchTerms: ["engineering", "permit", "structural"],
      }),
    ],
  },
  {
    id: "hazardous_material_gate",
    description: "Suspected hazardous material is addressed before disturbance.",
    applies: ({ facts, object }) => object === null && facts.conditions.hazardousMaterialsPossible === true,
    obligations: () => [
      obligation("hazard_screening", "Resolve testing or specialist handling before disturbance.", {
        allowExplicitExclusion: false,
        searchTerms: ["hazardous material testing", "abatement"],
      }),
    ],
  },
];

const roleOrder = new Map<ProcessRole, number>(
  constructionOntology.processRoles.map((role, index) => [role, index]),
);

function uniqueNonempty(values: string[]): string[] {
  return [...new Set(values.map((value) => value.trim()).filter(Boolean))];
}

function addObligations(
  output: Map<string, ScopeObligation>,
  context: RuleContext,
  rule: DependencyRule,
) {
  if (!rule.applies(context)) return;
  for (const proposed of rule.obligations(context)) {
    const objectID = context.object?.id ?? null;
    const id = `${objectID ?? "project"}:${proposed.processRole}`;
    const existing = output.get(id);
    if (existing) {
      existing.catalogItemExpected ||= proposed.catalogItemExpected;
      existing.allowExplicitExclusion &&= proposed.allowExplicitExclusion;
      existing.searchTerms = uniqueNonempty([...existing.searchTerms, ...proposed.searchTerms]);
      existing.reason = uniqueNonempty([...existing.reason.split(" | "), proposed.reason]).join(" | ");
      continue;
    }
    output.set(id, { id, objectID, ...proposed });
  }
}

// Universal rules create stable obligations. AI never authors this list.
export function produceScopeObligations(facts: StructuredScopeFacts): ScopeObligation[] {
  if (facts.objects.length === 0) {
    throw new Error("Structured scope must contain at least one work object");
  }
  const obligations = new Map<string, ScopeObligation>();
  const projectContext = { facts, object: null };
  for (const rule of universalDependencyRules) {
    addObligations(obligations, projectContext, rule);
  }
  for (const object of facts.objects) {
    const context = { facts, object };
    for (const rule of universalDependencyRules) {
      addObligations(obligations, context, rule);
    }
  }
  return [...obligations.values()].sort((left, right) => {
    const byRole = roleOrder.get(left.processRole)! - roleOrder.get(right.processRole)!;
    return byRole || (left.objectID ?? "").localeCompare(right.objectID ?? "");
  });
}

export type CandidateSet = {
  obligationID: string;
  items: TaggedCostItem[];
};

export type ScopeQuestion = {
  id: string;
  objectID: string | null;
  attribute: SearchableAttribute | "quantity";
  prompt: string;
  responseType: "number" | "single_choice";
  options: Array<string | number | boolean>;
  priceImpact: number;
  candidateItemIDs: string[];
};

const attributePrompts: Record<SearchableAttribute, string> = {
  material: "Which material should be used?",
  grade: "Which quality or grade should be used?",
  size: "Which size applies?",
  thickness: "Which thickness applies?",
  installation_method: "Which installation method applies?",
  finish_level: "Which finish level applies?",
  fixture_type: "Which fixture or product type applies?",
  customer_supply: "Who supplies the fixture or finish material?",
  volume_tier: "Does this qualify as small-volume or large-volume work?",
};

function stableValue(value: string | number | boolean): string {
  return `${typeof value}:${String(value)}`;
}

function priceSpread(items: TaggedCostItem[]): number {
  const prices = items.map((item) => item.directCostPerUnit);
  return prices.length ? Math.max(...prices) - Math.min(...prices) : 0;
}

// Questions come only from missing quantities and meaningful differences among
// actual retrieved candidates. They are stable for a fixed candidate set.
export function produceCandidateQuestions(
  facts: StructuredScopeFacts,
  obligations: ScopeObligation[],
  candidateSets: CandidateSet[],
  answers: Record<string, string | number | boolean> = {},
  limit = 8,
): ScopeQuestion[] {
  const questions = new Map<string, ScopeQuestion>();
  const objectByID = new Map(facts.objects.map((object) => [object.id, object]));
  const candidatesByObligation = new Map(
    candidateSets.map((candidateSet) => [candidateSet.obligationID, candidateSet.items]),
  );

  for (const object of facts.objects) {
    const questionID = `${object.id}:quantity`;
    if (!object.quantity && !(questionID in answers)) {
      questions.set(questionID, {
        id: questionID,
        objectID: object.id,
        attribute: "quantity",
        prompt: `What quantity of ${object.name} is included?`,
        responseType: "number",
        options: [],
        priceImpact: Number.MAX_SAFE_INTEGER,
        candidateItemIDs: [],
      });
    }
  }

  for (const obligation of obligations) {
    const items = candidatesByObligation.get(obligation.id) ?? [];
    if (items.length < 2) continue;
    const object = obligation.objectID ? objectByID.get(obligation.objectID) : undefined;
    for (const attribute of constructionOntology.searchableAttributes) {
      const questionID = `${obligation.objectID ?? "project"}:${attribute}`;
      if (questionID in answers || object?.attributes?.[attribute] !== undefined) continue;
      const values = new Map<string, string | number | boolean>();
      const relevantItems: TaggedCostItem[] = [];
      for (const item of items) {
        const value = item.attributes[attribute];
        if (value === undefined) continue;
        values.set(stableValue(value), value);
        relevantItems.push(item);
      }
      if (values.size < 2 || values.size > 8) continue;
      const existing = questions.get(questionID);
      const itemIDs = uniqueNonempty([
        ...(existing?.candidateItemIDs ?? []),
        ...relevantItems.map((item) => item.id),
      ]);
      questions.set(questionID, {
        id: questionID,
        objectID: obligation.objectID,
        attribute,
        prompt: attributePrompts[attribute],
        responseType: "single_choice",
        options: [...values.values()].sort((left, right) => String(left).localeCompare(String(right))),
        priceImpact: Math.max(existing?.priceImpact ?? 0, priceSpread(relevantItems)),
        candidateItemIDs: itemIDs,
      });
    }
  }

  return [...questions.values()]
    .sort((left, right) => right.priceImpact - left.priceImpact || left.id.localeCompare(right.id))
    .slice(0, limit);
}

export type ObligationResolution = {
  obligationID: string;
  resolution: "priced_items" | "included_elsewhere" | "plan_only" | "explicit_exclusion";
  explanation: string;
  selections: Array<{
    costItemID: string;
    quantity: number;
  }>;
};

export type CompletenessAudit = {
  valid: boolean;
  unresolvedObligationIDs: string[];
  invalidExclusionIDs: string[];
  unknownObligationIDs: string[];
  invalidSelectionIDs: string[];
  invalidQuantities: string[];
};

export function checkScopeCompleteness(
  obligations: ScopeObligation[],
  candidateSets: CandidateSet[],
  resolutions: ObligationResolution[],
): CompletenessAudit {
  const obligationByID = new Map(obligations.map((item) => [item.id, item]));
  const candidatesByObligation = new Map(candidateSets.map((set) => [
    set.obligationID,
    new Set(set.items.map((item) => item.id)),
  ]));
  const resolutionsByObligation = new Map<string, ObligationResolution[]>();
  for (const resolution of resolutions) {
    const existing = resolutionsByObligation.get(resolution.obligationID) ?? [];
    existing.push(resolution);
    resolutionsByObligation.set(resolution.obligationID, existing);
  }

  const unresolvedObligationIDs = obligations
    .filter((item) => (resolutionsByObligation.get(item.id)?.length ?? 0) !== 1)
    .map((item) => item.id);
  const unknownObligationIDs = resolutions
    .filter((resolution) => !obligationByID.has(resolution.obligationID))
    .map((resolution) => resolution.obligationID);
  const invalidExclusionIDs: string[] = [];
  const invalidSelectionIDs: string[] = [];
  const invalidQuantities: string[] = [];

  for (const resolution of resolutions) {
    const obligation = obligationByID.get(resolution.obligationID);
    if (!obligation) continue;
    if (resolution.resolution === "explicit_exclusion" && !obligation.allowExplicitExclusion) {
      invalidExclusionIDs.push(obligation.id);
    }
    if (resolution.resolution === "priced_items" && resolution.selections.length === 0) {
      invalidSelectionIDs.push(obligation.id);
    }
    if (resolution.resolution !== "priced_items" && resolution.selections.length > 0) {
      invalidSelectionIDs.push(obligation.id);
    }
    const allowedIDs = candidatesByObligation.get(obligation.id) ?? new Set<string>();
    for (const selection of resolution.selections) {
      if (!allowedIDs.has(selection.costItemID)) {
        invalidSelectionIDs.push(`${obligation.id}:${selection.costItemID}`);
      }
      if (!Number.isFinite(selection.quantity) || selection.quantity <= 0) {
        invalidQuantities.push(`${obligation.id}:${selection.costItemID}`);
      }
    }
  }

  const unique = (values: string[]) => [...new Set(values)];
  const audit = {
    unresolvedObligationIDs: unique(unresolvedObligationIDs),
    invalidExclusionIDs: unique(invalidExclusionIDs),
    unknownObligationIDs: unique(unknownObligationIDs),
    invalidSelectionIDs: unique(invalidSelectionIDs),
    invalidQuantities: unique(invalidQuantities),
  };
  return {
    valid: Object.values(audit).every((values) => values.length === 0),
    ...audit,
  };
}

export type PricedScopeItem = {
  obligationID: string;
  costItemID: string;
  description: string;
  quantity: number;
  unit: string;
  directUnitCost: number;
  sellingUnitPrice: number;
  total: number;
};

export type PricingPolicy = {
  regionalFactor: number;
  sellingPriceMultiplier: number;
};

function roundMoney(value: number): number {
  return Math.round(value * 100) / 100;
}

export function priceScopeSelections(
  candidateSets: CandidateSet[],
  resolutions: ObligationResolution[],
  policy: PricingPolicy,
): { items: PricedScopeItem[]; total: number } {
  if (!Number.isFinite(policy.regionalFactor) || policy.regionalFactor <= 0 ||
    !Number.isFinite(policy.sellingPriceMultiplier) || policy.sellingPriceMultiplier <= 0) {
    throw new Error("Pricing policy factors must be positive finite numbers");
  }
  const itemsByID = new Map(
    candidateSets.flatMap((set) => set.items).map((item) => [item.id, item]),
  );
  const items = resolutions.flatMap((resolution) =>
    resolution.selections.map((selection) => {
      const item = itemsByID.get(selection.costItemID);
      if (!item) throw new Error(`Unknown selected cost item: ${selection.costItemID}`);
      const sellingUnitPrice = roundMoney(
        item.directCostPerUnit * policy.regionalFactor * policy.sellingPriceMultiplier,
      );
      return {
        obligationID: resolution.obligationID,
        costItemID: item.id,
        description: item.description,
        quantity: selection.quantity,
        unit: item.unit,
        directUnitCost: item.directCostPerUnit,
        sellingUnitPrice,
        total: roundMoney(selection.quantity * sellingUnitPrice),
      };
    })
  );
  return {
    items,
    total: roundMoney(items.reduce((sum, item) => sum + item.total, 0)),
  };
}

export type ScopeFlowAdapters = {
  extractStructuredFacts: (initialRequest: string) => Promise<StructuredScopeFacts>;
  searchCostItems: (
    obligation: ScopeObligation,
    facts: StructuredScopeFacts,
  ) => Promise<TaggedCostItem[]>;
  selectItemsAndQuantities: (input: {
    facts: StructuredScopeFacts;
    obligations: ScopeObligation[];
    candidateSets: CandidateSet[];
    answers: Record<string, string | number | boolean>;
  }) => Promise<ObligationResolution[]>;
};

export type ScopeFlowResult =
  | {
      stage: "questions";
      facts: StructuredScopeFacts;
      obligations: ScopeObligation[];
      candidateSets: CandidateSet[];
      questions: ScopeQuestion[];
    }
  | {
      stage: "blocked";
      facts: StructuredScopeFacts;
      obligations: ScopeObligation[];
      candidateSets: CandidateSet[];
      reason: "missing_catalog_candidates" | "incomplete_scope";
      missingCandidateObligationIDs: string[];
      audit: CompletenessAudit | null;
    }
  | {
      stage: "priced";
      facts: StructuredScopeFacts;
      obligations: ScopeObligation[];
      candidateSets: CandidateSet[];
      resolutions: ObligationResolution[];
      audit: CompletenessAudit;
      pricing: ReturnType<typeof priceScopeSelections>;
    };

// Complete standalone flow. AI and search are adapters; scope obligations,
// questions, completeness, and pricing behavior remain deterministic.
export async function runConstructionScopeFlow(input: {
  initialRequest: string;
  answers?: Record<string, string | number | boolean>;
  pricingPolicy: PricingPolicy;
  adapters: ScopeFlowAdapters;
}): Promise<ScopeFlowResult> {
  const facts = await input.adapters.extractStructuredFacts(input.initialRequest);
  const obligations = produceScopeObligations(facts);
  const candidateSets = await Promise.all(obligations.map(async (scopeObligation) => ({
    obligationID: scopeObligation.id,
    items: (await input.adapters.searchCostItems(scopeObligation, facts))
      .filter((item) => item.residentialEligible)
      .sort((left, right) => right.confidence - left.confidence || left.id.localeCompare(right.id)),
  })));
  const answers = input.answers ?? {};
  const questions = produceCandidateQuestions(facts, obligations, candidateSets, answers);
  if (questions.length > 0) {
    return { stage: "questions", facts, obligations, candidateSets, questions };
  }

  const missingCandidateObligationIDs = obligations
    .filter((item) => item.catalogItemExpected)
    // An obligation that permits an explicit exclusion may also be resolved as
    // included_elsewhere or plan_only. Do not block before the resolver gets
    // that chance. Non-excludable obligations still require a real candidate.
    .filter((item) => !item.allowExplicitExclusion)
    .filter((item) => (candidateSets.find((set) => set.obligationID === item.id)?.items.length ?? 0) === 0)
    .map((item) => item.id);
  if (missingCandidateObligationIDs.length > 0) {
    return {
      stage: "blocked",
      facts,
      obligations,
      candidateSets,
      reason: "missing_catalog_candidates",
      missingCandidateObligationIDs,
      audit: null,
    };
  }

  const resolutions = await input.adapters.selectItemsAndQuantities({
    facts,
    obligations,
    candidateSets,
    answers,
  });
  const audit = checkScopeCompleteness(obligations, candidateSets, resolutions);
  if (!audit.valid) {
    return {
      stage: "blocked",
      facts,
      obligations,
      candidateSets,
      reason: "incomplete_scope",
      missingCandidateObligationIDs: [],
      audit,
    };
  }

  return {
    stage: "priced",
    facts,
    obligations,
    candidateSets,
    resolutions,
    audit,
    pricing: priceScopeSelections(candidateSets, resolutions, input.pricingPolicy),
  };
}
