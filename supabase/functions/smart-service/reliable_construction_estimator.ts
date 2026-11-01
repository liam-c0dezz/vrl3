import {
  buildConstructionEstimate,
  buildConstructionSchema,
  buildConstructionSystemPrompt,
  parseConstructionTurn,
  type ConstructionTurn,
} from "./construction_estimator.ts";
import {
  EstimatorPipelineError,
  type ProductionEstimate,
  type StructuredGenerator,
} from "./estimator_contract.ts";

const DRAFT_MODE_INSTRUCTIONS = `

RELIABLE PRELIMINARY-DRAFT MODE — THESE RULES TAKE PRECEDENCE
- For ordinary residential work, return stage="estimate_ready" on this turn. Do not return intake questions.
- The contractor wants a fast, editable starting quote, not a final fixed bid. Infer ordinary residential quantities and selections when the request is incomplete, and disclose every meaningful inference in assumptions.
- Never require the contractor to know demolition volume, cleanup volume, product thickness, catalog volume tiers, or an exact square footage that can reasonably be inferred.
- A singular fixture is quantity 1. A standard full bathroom with no dimensions may use an editable 5 ft by 8 ft room assumption, approximately 40 SF of flooring, and approximately 80 SF of tub/shower wall tile when those components are in scope.
- Use standard finish tier and standard difficulty unless the contractor clearly requests another level or describes an access/site constraint.
- Include a sensible complete preliminary scope for the requested job, but do not invent structural changes, hazardous-material work, engineering, or major utility relocation.
- Missing precision belongs in assumptions or exclusions. It must not prevent generation of an editable estimate.
- Do not select daily_cleanup or final_cleanup. Ordinary cleanup may appear in the work plan, but it must never be priced as a separate line item.
- Only keep stage="intake" for a request that is not an identifiable residential construction job at all.
`;

function asProductionEstimate(turn: ConstructionTurn): ProductionEstimate {
  const estimate = buildConstructionEstimate(turn);
  return {
    ...estimate,
    location: turn.location,
    summary: turn.assumptions.length > 0
      ? turn.assumptions.join(" ")
      : "Preliminary contractor-editable construction estimate.",
  };
}

function parseReadyTurn(value: unknown): ConstructionTurn {
  const turn = parseConstructionTurn(value);
  if (turn.stage !== "estimate_ready") {
    throw new Error("The preliminary draft returned intake instead of an estimate");
  }
  return turn;
}

export async function runReliableConstructionEstimator(input: {
  modelInput: unknown;
  generateStructured: StructuredGenerator;
  maxOutputTokens: number;
}): Promise<{
  stage: "estimate_ready";
  reply: string;
  estimate: ProductionEstimate;
}> {
  const generate = (instructions: string) => input.generateStructured({
    instructions,
    input: input.modelInput,
    schemaName: "construction_preliminary_draft",
    schema: buildConstructionSchema(),
    maxOutputTokens: Math.max(4_000, Math.min(input.maxOutputTokens, 6_000)),
  });

  let firstResult: unknown;
  try {
    firstResult = await generate(buildConstructionSystemPrompt() + DRAFT_MODE_INSTRUCTIONS);
  } catch (error) {
    if (error instanceof EstimatorPipelineError) throw error;
    throw new EstimatorPipelineError(
      "selection_generation",
      error instanceof Error ? error.message : "The preliminary draft could not be generated",
    );
  }

  try {
    const turn = parseReadyTurn(firstResult);
    return {
      stage: "estimate_ready",
      reply: turn.reply_text,
      estimate: asProductionEstimate(turn),
    };
  } catch (firstError) {
    let correctedResult: unknown;
    try {
      correctedResult = await generate(
        buildConstructionSystemPrompt() + DRAFT_MODE_INSTRUCTIONS +
          `\nYour prior draft was rejected: ${
            firstError instanceof Error ? firstError.message : "invalid draft"
          }. Return a complete estimate_ready draft now. Infer missing ordinary quantities and state them as editable assumptions.`,
      );
    } catch (error) {
      throw new EstimatorPipelineError(
        "selection_generation",
        error instanceof Error ? error.message : "The corrected preliminary draft could not be generated",
      );
    }

    try {
      const turn = parseReadyTurn(correctedResult);
      return {
        stage: "estimate_ready",
        reply: turn.reply_text,
        estimate: asProductionEstimate(turn),
      };
    } catch (error) {
      throw new EstimatorPipelineError(
        "selection_validation",
        error instanceof Error ? error.message : "The preliminary draft was invalid",
      );
    }
  }
}
