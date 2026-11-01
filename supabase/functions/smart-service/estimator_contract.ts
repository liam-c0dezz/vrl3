export type StructuredGenerator = (request: {
  instructions: string;
  input: unknown;
  schemaName: string;
  schema: Record<string, unknown>;
  maxOutputTokens: number;
}) => Promise<unknown>;

export type EstimatorPipelineStage =
  | "fact_generation"
  | "fact_validation"
  | "catalog_search"
  | "question_generation"
  | "selection_generation"
  | "selection_validation"
  | "estimate_building";

export class EstimatorPipelineError extends Error {
  readonly stage: EstimatorPipelineStage;

  constructor(stage: EstimatorPipelineStage, message: string) {
    super(message);
    this.name = "EstimatorPipelineError";
    this.stage = stage;
  }
}

export type ProductionEstimate = {
  title: string;
  location: string | null;
  summary: string;
  categories: Array<{
    name: string;
    items: Array<{
      name: string;
      quantity: number;
      unitLabel: string;
      unitPrice: number;
      total: number;
      source: string;
      url: string | null;
      description: string;
      onHand: boolean;
    }>;
  }>;
  subtotal: number;
  markupPercent: number;
  markupAmount: number;
  contingencyPercent: number;
  contingencyAmount: number;
  total: number;
  exclusions: string[];
  paymentTerms: string;
  sanityCheck: string;
  workPlan: Array<{ id: string; title: string; steps: string[] }>;
  notes: string;
};
