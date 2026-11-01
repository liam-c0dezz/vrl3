import type { WholeState } from './whole-project.ts';
import type { ProjectState } from './estimating-planner.ts';
import { pricePlan, type Plan } from './residential-estimator.ts';
export type AppQuestion = { id: string; question: string; response_type: 'text'; help_text: string; options: never[] };
export type SavedDraft = {
  id: string; title: string; scope_text: string; status: string; revision: number; chat_session_id?: string | null;
  plan: { wholeState?: WholeState; generator?: string; state?: ProjectState; checkpointInput?: string; engine?: string; residentialPlan?: Plan; report?: ReturnType<typeof pricePlan>; customerMessages?: string[]; response?: Record<string, unknown> };
  questions: AppQuestion[]; answers: Record<string, { question: string; text: string }>;
};
export function buildCustomerDescription(
  messages: { role: string; content: string }[],
  existing: SavedDraft | null,
  incoming: { question_id: string; text?: string; option_id?: string }[] = [],
  attachmentText = '',
) {
  const answers = { ...(existing?.answers ?? {}) };
  for (const answer of incoming) {
    const question = existing?.questions.find(q => q.id === answer.question_id);
    if (!question || answer.option_id || !answer.text?.trim()) throw new Error('Invalid or outdated draft answer');
    delete answers[answer.question_id]; // A correction must be last even when the question ID is reused.
    answers[answer.question_id] = { question: question.question, text: answer.text.trim() };
  }
  // Never promote assistant replies, generated scope, or catalog text to measured facts.
  const userText = messages.filter(m => m.role === 'user' && !m.content.startsWith('Project details for ')).map(m => m.content);
  let base = existing?.scope_text ?? '';
  for (const part of [...userText, attachmentText].filter(Boolean)) {
    if (!base.includes(part)) base = [base, part].filter(Boolean).join('\n\n');
  }
  const previous = existing?.plan.residentialPlan;
  const known = existing?.plan.customerMessages;
  let overlap = 0;
  if (known) for (let n = Math.min(known.length, userText.length); n > 0; n--) {
    if (known.slice(-n).every((text, i) => text === userText[i])) { overlap = n; break; }
  }
  const newMessages = known ? userText.slice(overlap) : userText.filter(part => !existing?.scope_text.includes(part));
  // Snapshot accepted facts, not the previous model's conflict narration. Evidence
  // remains verbatim customer text so deterministic takeoff validation still applies.
  const snapshot = previous?.items.length ? previous.items.map(item => [
    `Work: ${item.description}; location: ${item.location}; certainty: ${item.certainty}`,
    `Customer scope evidence: ${item.evidence}`,
    ...item.quantity.measurements.map(m => `Current accepted measurement: ${m.value} ${m.unit}. Customer evidence: ${m.evidence}`),
  ].join('\n')).join('\n\n') : '';
  const latestAnswers = incoming.map(a => answers[a.question_id]);
  const description = snapshot
    ? [`CURRENT PROJECT DETAILS (replace only details corrected below):\n${snapshot}`,
       `Existing exclusions: ${JSON.stringify(previous!.exclusions)}`,
       ...newMessages.map(t => `NEW CUSTOMER UPDATE: ${t}`),
       attachmentText ? `NEW CUSTOMER ATTACHMENT DETAILS: ${attachmentText}` : '',
       ...latestAnswers.map(a => `Question context (not a customer fact): ${a.question}\nLATEST CUSTOMER ANSWER: ${a.text}`)].filter(Boolean).join('\n\n')
    : [base, ...Object.values(answers).map(a => `Question context (not a customer fact): ${a.question}\nCUSTOMER ANSWER (oldest to newest): ${a.text}`)].filter(Boolean).join('\n\n');
  if (!description.trim() || description.length > 12000) throw new Error('Describe a smaller phase of the project (up to 12,000 characters).');
  return { description, scopeText: base, answers, customerMessages: userText, updates: [...newMessages, attachmentText, ...latestAnswers.map(a => `Question: ${a.question}\nLatest answer: ${a.text}`)].filter(Boolean).join('\n\n'), fullContext: [base, ...Object.values(answers).map(a => `Question: ${a.question}\nCustomer answer: ${a.text}`)].join('\n\n') };
}
export function appQuestions(report: ReturnType<typeof pricePlan>, draftID: string, revision: number): AppQuestion[] {
  const unresolved = report.lines.filter(line => line.amount === null);
  // Model questions are customer-facing; diagnostic match reasons and historical
  // conflict narratives must never be pasted into the form.
  const questions = [...new Set(report.questions)].slice(0, 3);
  return questions.map((question, i) => ({ id: `${draftID}:r${revision}:q${i + 1}`, question: question.slice(0, 1000), response_type: 'text',
    help_text: 'Use your own words. Your latest answer replaces any earlier answer for this detail.', options: [] as never[] }));
}
const round = (value: number) => Math.round((value + Number.EPSILON) * 100) / 100;
/** The legacy app requires a numeric total. Only build it when EVERY scope line
 * has a supported amount. It is explicitly a provisional priced-scope amount,
 * never a conversion of an incomplete worksheet into a complete project budget.
 */
export function appEstimate(report: ReturnType<typeof pricePlan>, markupPercent = 0, contingencyPercent = 0, title = 'Residential Project') {
  if (!report.pricedLineCount || report.unpricedLineCount || report.conflicts.length) throw new Error('Unresolved scope cannot become a saved priced estimate');
  if (![markupPercent, contingencyPercent].every(Number.isFinite) || markupPercent < 0 || markupPercent > 300 || contingencyPercent < 0 || contingencyPercent > 100) throw new Error('Invalid explicit pricing adjustment');
  const groups = new Map<string, Array<{ name: string; quantity: number; unitLabel: string; unitPrice: number; total: number; source: string; url: null; description: string; onHand: boolean }>>();
  for (const line of report.lines) {
    if (line.amount === null || line.catalogQuantity === null || line.catalogQuantity > 1000000 || !line.source || typeof line.unitRate !== 'number' || !line.catalogUnit) throw new Error('Unsupported persisted quantity or rate');
    const items = groups.get(line.category) ?? [];
    items.push({ name: line.description, quantity: line.catalogQuantity, unitLabel: line.catalogUnit,
      unitPrice: line.unitRate, total: line.amount, source: `${line.source.id}; SHA256 ${line.source.sha256}`, url: null,
      description: [line.description, line.location ? `Location: ${line.location}` : ''].filter(Boolean).join('\n').slice(0, 4000), onHand: false });
    groups.set(line.category, items);
  }
  const subtotal = report.catalogSubtotal!, markupAmount = round(subtotal * markupPercent / 100), contingencyAmount = round(subtotal * contingencyPercent / 100);
  const notes = [report.disclaimer, report.currencyNote,
    'Amounts use unadjusted workbook unit rates. Business hourly-rate overrides, overhead and gross-margin multipliers are not applied.',
    `Explicit additional markup: ${markupPercent}%; contingency: ${contingencyPercent}%.`,
    ...report.assumptions.map(s => `Assumption: ${s}`), ...report.reviewItems.map(s => `Review: ${s}`)].join('\n');
  if (notes.length > 12000) throw new Error('Estimate review notes exceed the supported limit; split the scope.');
  return {
    title: title.trim().slice(0, 60) || 'Residential Project', location: null, summary: report.summary,
    categories: [...groups].map(([name, items]) => ({ name, items, subtotal: round(items.reduce((a, i) => a + i.total, 0)) })),
    subtotal, markupPercent, markupAmount, contingencyPercent, contingencyAmount,
    total: round(subtotal + markupAmount + contingencyAmount),
    exclusions: report.exclusions, paymentTerms: '',
    sanityCheck: 'Provisional priced scope only. Confirm source currency, locality, inclusions, quantities and catalog selections before quoting.',
    workPlan: [] as { id: string; title: string; steps: string[] }[], notes,
    pricing: { mode: 'residential_catalog_direct_v1', projectTotal: null, currency: null },
  };
}

