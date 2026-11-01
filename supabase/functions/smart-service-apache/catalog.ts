// Adapter only: user's existing catalog -> DDC rate payload. No DDC pricing data.
export const CATALOG = 'repair-2026-q3';
export const EMBEDDING_MODEL = 'text-embedding-3-large';
export const DIMENSIONS = 3072;
export type Row = { id: number; catalog_version: string; source_row: number; description: string; category: string; unit: string; direct_cost: number | string; material_cost: number | string; labor_cost: number | string; equipment_cost: number | string; action: string };
// Metric SI base magnitude per catalog unit. DDC's original parser uses metric.
const units: Record<string,[string,number]> = {
  sf:['area',0.09290304],sy:['area',0.83612736],sq:['area',9.290304],csf:['area',9.290304],
  'm²':['area',1],m2:['area',1],sqm:['area',1],lf:['length',0.3048],vlf:['length',0.3048],m:['length',1],
  cy:['volume',0.764554857984],'m³':['volume',1],m3:['volume',1],bf:['volume',0.002359737216],
  ea:['count',1],each:['count',1],pcs:['count',1],stk:['count',1],unit:['count',1],
  set:['set',1],pair:['pair',1],pr:['pair',1],lb:['mass',0.45359237],kg:['mass',1],
  ls:['job',1],job:['job',1],roll:['roll',1],min:['time',1],mi:['length',1609.344],
};
export function conversion(from: string,to: string): number | null {
  const a=from.toLowerCase().trim(),b=to.toLowerCase().trim();
  if(a===b)return 1;
  const x=units[a],y=units[b];return x&&y&&x[0]===y[0]?x[1]/y[1]:null;
}
export function payload(row: Row) {
  if (row.catalog_version!==CATALOG || !Number.isSafeInteger(row.id) || !Number.isFinite(Number(row.direct_cost)) || Number(row.direct_cost)<0) throw new Error('Invalid catalog record');
  return {rate_code:String(row.id),rate_name:row.description,rate_unit:row.unit,
    cost_summary:{total_cost_position:Number(row.direct_cost)},work_steps:[{text:row.category},{text:row.description}],
    resources:[['MAT_','Material',row.material_cost],['ME_','Labor',row.labor_cost],['DXME','Equipment',row.equipment_cost]].map(([code,name,cost])=>({resource_code:code,resource_name:name,resource_unit:row.unit,resource_quantity:null,resource_cost_eur:Number(cost)}))};
}
export function checkedQuantity(quantity: unknown): number {
  if(typeof quantity!=='number'||!Number.isFinite(quantity)||quantity<=0||quantity>1e8)throw new Error('Invalid quantity from upstream parser');return quantity;
}
export function money(n:number) { if(!Number.isFinite(n)||n<0||n>1e12)throw new Error('Invalid calculated amount');return Math.round((n+Number.EPSILON)*100)/100; }
