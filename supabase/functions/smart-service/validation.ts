export const REQUEST_LIMITS = {
  maxMessages: 50,
  maxMessageCharacters: 5_000,
  maxTotalMessageCharacters: 50_000,
  maxImageBase64Characters: 10_666_668, // 8 MB decoded
  maxAudioBase64Characters: 33_333_336, // 25 MB decoded
  maxVideoFrames: 6,
  maxVideoFrameBase64Characters: 2_666_668, // 2 MB decoded per frame
  maxVideoFramesBase64Characters: 10_666_668, // 8 MB decoded total
  maxImageCaptionCharacters: 2_000,
  maxEditInstructionCharacters: 2_000,
  maxScreeningAnswers: 50,
  maxMarkupPercent: 300,
  maxContingencyPercent: 100,
  maxScale: 10_000,
} as const;

export type ValidatedMessage = {
  role: "user" | "assistant";
  content: string;
};

export type ValidatedSmartServiceRequest = {
  request_id: string;
  operation: "generate" | "edit_estimate" | "generate_plan";
  messages?: ValidatedMessage[];
  project_id: string;
  estimate_id?: string;
  edit_instruction?: string;
  image_base64?: string | null;
  image_caption?: string | null;
  attachment_kind?: "photo" | "audio" | "video" | null;
  attachment_mime_type?: string | null;
  attachment_base64?: string | null;
  video_frames_base64?: string[];
  video_audio_base64?: string | null;
  screening_answers?: number[];
  job_id?: string | null;
  markup_percent?: number | null;
  contingency_percent?: number | null;
};

export class RequestValidationError extends Error {
  readonly status = 400;

  constructor(message: string) {
    super(message);
    this.name = "RequestValidationError";
  }
}

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const JOB_ID_PATTERN = /^[a-z0-9][a-z0-9_:-]{0,99}$/i;
const AUDIO_MIME_TYPES = new Set([
  "audio/mpeg",
  "audio/mp4",
  "audio/x-m4a",
  "audio/wav",
  "audio/webm",
]);

function requireRecord(value: unknown): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new RequestValidationError("Request body must be a JSON object");
  }
  return value as Record<string, unknown>;
}

function optionalString(
  value: unknown,
  field: string,
  maxCharacters: number,
): string | null | undefined {
  if (value === undefined) return undefined;
  if (value === null) return null;
  if (typeof value !== "string") {
    throw new RequestValidationError(`${field} must be a string`);
  }
  if (value.length > maxCharacters) {
    throw new RequestValidationError(`${field} is too long`);
  }
  return value;
}

function optionalPercentage(
  value: unknown,
  field: string,
  maximum: number,
): number | null | undefined {
  if (value === undefined) return undefined;
  if (value === null) return null;
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new RequestValidationError(`${field} must be a finite number`);
  }
  if (value < 0 || value > maximum) {
    throw new RequestValidationError(
      `${field} must be between 0 and ${maximum}`,
    );
  }
  return value;
}

function validateMessages(value: unknown): ValidatedMessage[] | undefined {
  if (value === undefined) return undefined;
  if (!Array.isArray(value)) {
    throw new RequestValidationError("messages must be an array");
  }
  if (value.length > REQUEST_LIMITS.maxMessages) {
    throw new RequestValidationError(
      `messages cannot contain more than ${REQUEST_LIMITS.maxMessages} entries`,
    );
  }

  let totalCharacters = 0;
  const messages = value.map((entry, index) => {
    const message = requireRecord(entry);
    if (message.role !== "user" && message.role !== "assistant") {
      throw new RequestValidationError(
        `messages[${index}].role must be user or assistant`,
      );
    }
    if (typeof message.content !== "string") {
      throw new RequestValidationError(
        `messages[${index}].content must be a string`,
      );
    }
    const role: ValidatedMessage["role"] = message.role;
    const content = message.content;
    if (content.length > REQUEST_LIMITS.maxMessageCharacters) {
      throw new RequestValidationError(
        `messages[${index}].content is too long`,
      );
    }
    totalCharacters += content.length;
    return {
      role,
      content,
    };
  });

  if (totalCharacters > REQUEST_LIMITS.maxTotalMessageCharacters) {
    throw new RequestValidationError("Combined message history is too long");
  }
  return messages;
}

function validateScreeningAnswers(value: unknown): number[] | undefined {
  if (value === undefined) return undefined;
  if (!Array.isArray(value)) {
    throw new RequestValidationError("screening_answers must be an array");
  }
  if (value.length > REQUEST_LIMITS.maxScreeningAnswers) {
    throw new RequestValidationError(
      `screening_answers cannot contain more than ${REQUEST_LIMITS.maxScreeningAnswers} entries`,
    );
  }
  if (
    value.some(
      (answer) =>
        typeof answer !== "number" ||
        !Number.isSafeInteger(answer) ||
        answer <= 0,
    )
  ) {
    throw new RequestValidationError(
      "screening_answers must contain positive integer option IDs",
    );
  }
  if (new Set(value).size !== value.length) {
    throw new RequestValidationError(
      "screening_answers cannot contain duplicate option IDs",
    );
  }
  return value as number[];
}

function validateVideoFrames(value: unknown): string[] | undefined {
  if (value === undefined) return undefined;
  if (!Array.isArray(value) || value.length === 0) {
    throw new RequestValidationError("video_frames_base64 must be a non-empty array");
  }
  if (value.length > REQUEST_LIMITS.maxVideoFrames) {
    throw new RequestValidationError(
      `A video cannot include more than ${REQUEST_LIMITS.maxVideoFrames} frames`,
    );
  }
  let totalCharacters = 0;
  for (const [index, frame] of value.entries()) {
    if (typeof frame !== "string") {
      throw new RequestValidationError(
        `video_frames_base64[${index}] must be a string`,
      );
    }
    if (frame.length > REQUEST_LIMITS.maxVideoFrameBase64Characters) {
      throw new RequestValidationError(`Video frame ${index + 1} is too large`);
    }
    totalCharacters += frame.length;
  }
  if (totalCharacters > REQUEST_LIMITS.maxVideoFramesBase64Characters) {
    throw new RequestValidationError("Combined video frames are too large");
  }
  return value as string[];
}

export function validateSmartServiceRequest(
  value: unknown,
): ValidatedSmartServiceRequest {
  const body = requireRecord(value);

  if (typeof body.request_id !== "string" || !UUID_PATTERN.test(body.request_id)) {
    throw new RequestValidationError("A valid request_id is required");
  }

  if (
    typeof body.project_id !== "string" ||
    !UUID_PATTERN.test(body.project_id)
  ) {
    throw new RequestValidationError("A valid project_id is required");
  }

  const operation = body.operation === undefined || body.operation === "generate"
    ? "generate"
    : body.operation === "edit_estimate"
    ? "edit_estimate"
    : body.operation === "generate_plan"
    ? "generate_plan"
    : null;
  if (!operation) {
    throw new RequestValidationError("operation is invalid");
  }

  let estimateID: string | undefined;
  if (body.estimate_id !== undefined) {
    if (typeof body.estimate_id !== "string" || !UUID_PATTERN.test(body.estimate_id)) {
      throw new RequestValidationError("A valid estimate_id is required");
    }
    estimateID = body.estimate_id;
  }
  const editInstruction = optionalString(
    body.edit_instruction,
    "edit_instruction",
    REQUEST_LIMITS.maxEditInstructionCharacters,
  ) ?? undefined;

  const messages = validateMessages(body.messages);
  const imageBase64 = optionalString(
    body.image_base64,
    "image_base64",
    REQUEST_LIMITS.maxImageBase64Characters,
  );
  const imageCaption = optionalString(
    body.image_caption,
    "image_caption",
    REQUEST_LIMITS.maxImageCaptionCharacters,
  );
  const attachmentBase64 = optionalString(
    body.attachment_base64,
    "attachment_base64",
    REQUEST_LIMITS.maxAudioBase64Characters,
  );
  const videoAudioBase64 = optionalString(
    body.video_audio_base64,
    "video_audio_base64",
    REQUEST_LIMITS.maxAudioBase64Characters,
  );
  const videoFramesBase64 = validateVideoFrames(body.video_frames_base64);
  const screeningAnswers = validateScreeningAnswers(body.screening_answers);
  const markupPercent = optionalPercentage(
    body.markup_percent,
    "markup_percent",
    REQUEST_LIMITS.maxMarkupPercent,
  );
  const contingencyPercent = optionalPercentage(
    body.contingency_percent,
    "contingency_percent",
    REQUEST_LIMITS.maxContingencyPercent,
  );

  let jobID: string | null | undefined;
  if (body.job_id === undefined) {
    jobID = undefined;
  } else if (body.job_id === null) {
    jobID = null;
  } else if (
    typeof body.job_id === "string" &&
    JOB_ID_PATTERN.test(body.job_id)
  ) {
    jobID = body.job_id;
  } else {
    throw new RequestValidationError("job_id has an invalid format");
  }

  let attachmentKind: "photo" | "audio" | "video" | null | undefined;
  if (body.attachment_kind === undefined) {
    attachmentKind = imageBase64 ? "photo" : undefined;
  } else if (body.attachment_kind === null) {
    attachmentKind = null;
  } else if (
    body.attachment_kind === "photo" ||
    body.attachment_kind === "audio" ||
    body.attachment_kind === "video"
  ) {
    attachmentKind = body.attachment_kind;
  } else {
    throw new RequestValidationError("attachment_kind is invalid");
  }

  let attachmentMimeType: string | null | undefined;
  if (body.attachment_mime_type === undefined) {
    attachmentMimeType = attachmentKind === "photo" ? "image/jpeg" : undefined;
  } else {
    attachmentMimeType = optionalString(
      body.attachment_mime_type,
      "attachment_mime_type",
      100,
    );
  }

  if (attachmentKind === "photo") {
    const photoData = attachmentBase64 ?? imageBase64;
    if (!photoData) {
      throw new RequestValidationError("A photo attachment is missing its data");
    }
    if (photoData.length > REQUEST_LIMITS.maxImageBase64Characters) {
      throw new RequestValidationError("Photo attachment is too large");
    }
    if (attachmentMimeType !== "image/jpeg" && attachmentMimeType !== "image/png") {
      throw new RequestValidationError("Photo attachment type is not supported");
    }
    if (videoFramesBase64 || videoAudioBase64) {
      throw new RequestValidationError("Photo attachment contains unexpected media data");
    }
  } else if (attachmentKind === "audio") {
    if (!attachmentBase64) {
      throw new RequestValidationError("An audio attachment is missing its data");
    }
    if (!attachmentMimeType || !AUDIO_MIME_TYPES.has(attachmentMimeType)) {
      throw new RequestValidationError("Audio attachment type is not supported");
    }
    if (imageBase64 || videoFramesBase64 || videoAudioBase64) {
      throw new RequestValidationError("Audio attachment contains unexpected media data");
    }
  } else if (attachmentKind === "video") {
    if (!videoFramesBase64 && !videoAudioBase64) {
      throw new RequestValidationError("A video attachment has no usable frames or audio");
    }
    if (attachmentBase64 || imageBase64) {
      throw new RequestValidationError("Raw video uploads are not accepted");
    }
    if (videoAudioBase64 && attachmentMimeType && !AUDIO_MIME_TYPES.has(attachmentMimeType)) {
      throw new RequestValidationError("Video audio type is not supported");
    }
  } else if (
    attachmentBase64 || imageBase64 || videoFramesBase64 || videoAudioBase64
  ) {
    throw new RequestValidationError("Attachment data requires an attachment_kind");
  }

  if (operation === "edit_estimate") {
    if (!estimateID) {
      throw new RequestValidationError("A valid estimate_id is required for AI editing");
    }
    if (!editInstruction?.trim()) {
      throw new RequestValidationError("An edit_instruction is required for AI editing");
    }
    if (
      messages !== undefined || screeningAnswers !== undefined || jobID !== undefined ||
      attachmentKind !== undefined || imageBase64 !== undefined || imageCaption !== undefined ||
      attachmentBase64 !== undefined || videoFramesBase64 !== undefined ||
      videoAudioBase64 !== undefined || markupPercent !== undefined ||
      contingencyPercent !== undefined
    ) {
      throw new RequestValidationError("AI estimate edits contain unexpected generation fields");
    }
    return {
      request_id: body.request_id,
      operation,
      project_id: body.project_id,
      estimate_id: estimateID,
      edit_instruction: editInstruction.trim(),
    };
  }

  if (operation === "generate_plan") {
    if (!estimateID) {
      throw new RequestValidationError("A valid estimate_id is required for plan generation");
    }
    if (
      editInstruction !== undefined || messages !== undefined ||
      screeningAnswers !== undefined || jobID !== undefined ||
      attachmentKind !== undefined || imageBase64 !== undefined ||
      imageCaption !== undefined || attachmentBase64 !== undefined ||
      videoFramesBase64 !== undefined || videoAudioBase64 !== undefined ||
      markupPercent !== undefined || contingencyPercent !== undefined
    ) {
      throw new RequestValidationError("Plan generation contains unexpected fields");
    }
    return {
      request_id: body.request_id,
      operation,
      project_id: body.project_id,
      estimate_id: estimateID,
    };
  }

  if (estimateID !== undefined || editInstruction !== undefined) {
    throw new RequestValidationError("Estimate edit fields require edit_estimate operation");
  }

  const hasScreeningAnswers = screeningAnswers !== undefined;
  const hasDirectJob = jobID !== undefined && jobID !== null;
  if (hasScreeningAnswers !== hasDirectJob) {
    throw new RequestValidationError(
      "job_id and screening_answers must be submitted together",
    );
  }
  if (!hasScreeningAnswers && messages === undefined) {
    throw new RequestValidationError(
      "messages are required when screening answers are not submitted",
    );
  }
  if (
    !hasScreeningAnswers &&
    messages?.length === 0 &&
    !attachmentKind &&
    !imageBase64
  ) {
    throw new RequestValidationError(
      "At least one message or image is required",
    );
  }

  return {
    request_id: body.request_id,
    operation,
    messages,
    project_id: body.project_id,
    image_base64: imageBase64,
    image_caption: imageCaption,
    attachment_kind: attachmentKind,
    attachment_mime_type: attachmentMimeType,
    attachment_base64: attachmentBase64,
    video_frames_base64: videoFramesBase64,
    video_audio_base64: videoAudioBase64,
    screening_answers: screeningAnswers,
    job_id: jobID,
    markup_percent: markupPercent,
    contingency_percent: contingencyPercent,
  };
}

export function validatePricingPercentages(
  markupPercent: number,
  contingencyPercent: number,
): void {
  optionalPercentage(
    markupPercent,
    "markup_percent",
    REQUEST_LIMITS.maxMarkupPercent,
  );
  optionalPercentage(
    contingencyPercent,
    "contingency_percent",
    REQUEST_LIMITS.maxContingencyPercent,
  );
}

export function validateScale(scale: number): void {
  if (
    typeof scale !== "number" ||
    !Number.isFinite(scale) ||
    scale <= 0 ||
    scale > REQUEST_LIMITS.maxScale
  ) {
    throw new RequestValidationError(
      `scale must be greater than 0 and no more than ${REQUEST_LIMITS.maxScale}`,
    );
  }
}

export function validateScreeningSelection(
  questionIDs: number[],
  selectedOptions: Array<{ id: number; question_id: number }>,
  submittedOptionIDs: number[],
): void {
  if (selectedOptions.length !== submittedOptionIDs.length) {
    throw new RequestValidationError(
      "One or more screening answers are invalid",
    );
  }

  const allowedQuestionIDs = new Set(questionIDs);
  const answeredQuestionIDs = new Set<number>();
  for (const option of selectedOptions) {
    if (!allowedQuestionIDs.has(option.question_id)) {
      throw new RequestValidationError(
        "A screening answer does not belong to the selected job",
      );
    }
    if (answeredQuestionIDs.has(option.question_id)) {
      throw new RequestValidationError(
        "Choose exactly one answer for each screening question",
      );
    }
    answeredQuestionIDs.add(option.question_id);
  }

  if (
    answeredQuestionIDs.size !== questionIDs.length ||
    questionIDs.some((id) => !answeredQuestionIDs.has(id))
  ) {
    throw new RequestValidationError(
      "Answer every screening question before creating the estimate",
    );
  }
}
