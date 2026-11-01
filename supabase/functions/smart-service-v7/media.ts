import { RequestValidationError } from "./validation.ts";

const BASE64_PATTERN = /^[A-Za-z0-9+/]*={0,2}$/;

export function decodeBoundedBase64(
  encodedValue: string,
  maximumBytes: number,
  fieldName: string,
): Uint8Array {
  const encoded = encodedValue.startsWith("data:")
    ? (encodedValue.split(",", 2)[1] ?? "")
    : encodedValue;
  if (
    encoded.length === 0 ||
    encoded.length % 4 === 1 ||
    !BASE64_PATTERN.test(encoded)
  ) {
    throw new RequestValidationError(`${fieldName} is not valid base64`);
  }

  let binary: string;
  try {
    binary = atob(encoded);
  } catch {
    throw new RequestValidationError(`${fieldName} is not valid base64`);
  }
  if (binary.length > maximumBytes) {
    throw new RequestValidationError(`${fieldName} is too large`);
  }
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

export function verifyImageBytes(bytes: Uint8Array, mimeType: string): void {
  const isJPEG =
    bytes.length >= 3 &&
    bytes[0] === 0xff &&
    bytes[1] === 0xd8 &&
    bytes[2] === 0xff;
  const isPNG =
    bytes.length >= 8 &&
    bytes[0] === 0x89 &&
    bytes[1] === 0x50 &&
    bytes[2] === 0x4e &&
    bytes[3] === 0x47 &&
    bytes[4] === 0x0d &&
    bytes[5] === 0x0a &&
    bytes[6] === 0x1a &&
    bytes[7] === 0x0a;

  if (
    (mimeType === "image/jpeg" && !isJPEG) ||
    (mimeType === "image/png" && !isPNG)
  ) {
    throw new RequestValidationError("Photo data does not match its declared type");
  }
}

export function verifyAudioBytes(bytes: Uint8Array, mimeType: string): void {
  const ascii = (start: number, length: number) =>
    String.fromCharCode(...bytes.slice(start, start + length));
  const isMP3 =
    (bytes.length >= 3 && ascii(0, 3) === "ID3") ||
    (bytes.length >= 2 && bytes[0] === 0xff && (bytes[1] & 0xe0) === 0xe0);
  const isMP4 = bytes.length >= 12 && ascii(4, 4) === "ftyp";
  const isWAV =
    bytes.length >= 12 && ascii(0, 4) === "RIFF" && ascii(8, 4) === "WAVE";
  const isWebM =
    bytes.length >= 4 &&
    bytes[0] === 0x1a &&
    bytes[1] === 0x45 &&
    bytes[2] === 0xdf &&
    bytes[3] === 0xa3;

  const matches =
    (mimeType === "audio/mpeg" && isMP3) ||
    ((mimeType === "audio/mp4" || mimeType === "audio/x-m4a") && isMP4) ||
    (mimeType === "audio/wav" && isWAV) ||
    (mimeType === "audio/webm" && isWebM);
  if (!matches) {
    throw new RequestValidationError("Audio data does not match its declared type");
  }
}

export function audioFilename(mimeType: string): string {
  switch (mimeType) {
    case "audio/mpeg":
      return "attachment.mp3";
    case "audio/wav":
      return "attachment.wav";
    case "audio/webm":
      return "attachment.webm";
    default:
      return "attachment.m4a";
  }
}


