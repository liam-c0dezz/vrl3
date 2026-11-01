// Keep every estimating and planning call on the user-approved Luna model.
// Responses max_output_tokens includes both reasoning and visible JSON.
export const ESTIMATE_MODEL = "gpt-6-luna";
export const ESTIMATE_REASONING = "low" as const;
export const SCOPE_REASONING = "low" as const;
export const PLAN_REASONING = "low" as const;
export const AI_DEADLINE_MS = 180_000;
export function reasoningOutputBudget(answerBudget = 2000): number {
  const visible = Number.isFinite(answerBudget) ? Math.min(Math.max(answerBudget, 2000), 7000) : 2000;
  return Math.min(25000 + visible, 32000);
}
