import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const sourcePath = process.argv[2];
if (!sourcePath) {
  throw new Error("Usage: node generate-construction-catalog.mjs /absolute/path/to/catalog.json");
}

const source = JSON.parse(await fs.readFile(sourcePath, "utf8"));
const roles = source.labor_roles.map((role) => ({
  id: role.id,
  name: role.name,
  billing_rate_multiplier: role.billing_rate_multiplier,
}));
const assemblies = source.assemblies.map((assembly) => ({
  id: assembly.id,
  trade: assembly.trade,
  name: assembly.name,
  description: assembly.description,
  unit: assembly.unit,
  labor_role_id: assembly.labor_role_id,
  crew_hours_per_unit: { base: assembly.crew_hours_per_unit.base },
  national_seed_material_cost_per_unit: {
    base: assembly.national_seed_material_cost_per_unit.base,
  },
  equipment_cost_per_unit_base: assembly.equipment_cost_per_unit_base,
  default_waste_percent: assembly.default_waste_percent,
  finish_tier_multipliers: assembly.finish_tier_multipliers,
  difficulty_multipliers: assembly.difficulty_multipliers,
  included_scope: assembly.included_scope,
  default_exclusions: assembly.default_exclusions,
  confidence: assembly.confidence,
}));
const templates = source.project_templates.map((template) => ({
  id: template.id,
  name: template.name,
  category: template.category,
  description: template.description,
  risk_level: template.risk_level,
  required_assembly_ids: template.required_assembly_ids,
  optional_assembly_ids: template.optional_assembly_ids,
  intake_question_ids: template.intake_question_ids,
  estimate_policy: template.estimate_policy,
}));
const questions = source.questions.map((question) => ({
  id: question.id,
  question: question.question,
  response_type: question.response_type,
  options: question.options,
  rationale: question.rationale,
}));

for (const [label, values] of [
  ["labor role", roles],
  ["assembly", assemblies],
  ["template", templates],
  ["question", questions],
]) {
  const ids = values.map((value) => value.id);
  if (new Set(ids).size !== ids.length) {
    throw new Error(`Duplicate ${label} ID in source catalog`);
  }
}

const assemblyIDs = new Set(assemblies.map((assembly) => assembly.id));
const roleIDs = new Set(roles.map((role) => role.id));
for (const assembly of assemblies) {
  if (!roleIDs.has(assembly.labor_role_id)) {
    throw new Error(`Assembly ${assembly.id} references missing labor role ${assembly.labor_role_id}`);
  }
}
for (const template of templates) {
  for (const assemblyID of [
    ...template.required_assembly_ids,
    ...template.optional_assembly_ids,
  ]) {
    if (!assemblyIDs.has(assemblyID)) {
      throw new Error(`Template ${template.id} references missing assembly ${assemblyID}`);
    }
  }
}

const payload = {
  metadata: {
    name: source.metadata.name,
    version: source.metadata.version,
    pricing_as_of: source.metadata.pricing_as_of,
    status: source.metadata.status,
    currency: source.metadata.currency,
  },
  labor_roles: roles,
  assemblies,
  project_templates: templates,
  questions,
};

const output = `// GENERATED FILE — do not hand edit.\n// Source: EasyBid construction template review catalog.\nexport const constructionCatalog = ${JSON.stringify(payload, null, 2)} as const;\n`;
const outputPath = path.join(path.dirname(fileURLToPath(import.meta.url)), "construction_catalog.ts");
await fs.writeFile(outputPath, output);
console.log(`Generated ${outputPath}`);
console.log(`${assemblies.length} assemblies, ${templates.length} templates, ${questions.length} questions`);
