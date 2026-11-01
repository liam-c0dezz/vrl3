/** Convert source measurements to catalog billing units before extending rates.
 * Preserve precision until money rounding; never round 100/9 SY to 11 first.
 */
const units: Record<string, [string, number]> = {
  sf: ['area', 1], sqft: ['area', 1], 'square feet': ['area', 1], 'sq ft': ['area', 1],
  sy: ['area', 9], sqyd: ['area', 9], 'square yards': ['area', 9],
  csf: ['area', 100], msf: ['area', 1000], m2: ['area', 10.763910416709722],
  lf: ['length', 1], ft: ['length', 1], feet: ['length', 1],
  in: ['length', 1 / 12], m: ['length', 3.280839895013123],
  cf: ['volume', 1], cy: ['volume', 27], m3: ['volume', 35.31466672148859],
};
export function convertQuantity(quantity: number, from: string, to: string): number {
  if (!Number.isFinite(quantity) || quantity <= 0 || quantity > 1_000_000) throw Error('Invalid measurement quantity');
  if (typeof from !== 'string' || typeof to !== 'string' || !from.trim() || !to.trim()) throw Error('Measurement and catalog units are required');
  const a = from.trim().toLowerCase(), b = to.trim().toLowerCase();
  if (a === b) return quantity;
  const source = units[a], target = units[b];
  if (!source || !target || source[0] !== target[0]) throw Error(`Cannot convert ${from} to ${to}`);
  const converted = quantity * source[1] / target[1];
  if (!Number.isFinite(converted) || converted <= 0 || converted > 1_000_000) throw Error('Converted quantity exceeds supported bounds');
  return converted;
}
