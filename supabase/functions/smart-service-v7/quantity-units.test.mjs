import test from 'node:test';
import assert from 'node:assert/strict';
import { convertQuantity } from './quantity-units.ts';
import { priceWholePlan } from './whole-project.ts';
test('area and volume conversions preserve source dimensions', () => {
  assert.equal(convertQuantity(100,'SF','SY'),100/9);
  assert.equal(convertQuantity(10,'SY','SF'),90);
  assert.equal(convertQuantity(100,'SF','CSF'),1);
  assert.equal(convertQuantity(27,'CF','CY'),1);
});
test('reject incompatible units and invalid quantities', () => {
  for (const pair of [['SF','LF'],['SF','Ea'],['person-hour','SF'],['Job','SY']]) assert.throws(()=>convertQuantity(100,...pair));
  for (const q of [0,-1,NaN,Infinity]) assert.throws(()=>convertQuantity(q,'SF','SY'));
});
test('100 SF carpet and pad are extended at 100/9 SY, not 100 SY', () => {
  const components=[{id:'carpet',row:1470},{id:'pad',row:1472}].map(c=>({...c,category:'Demolition',name:c.id,location:'Bedroom',kind:'catalog',quantity:100,quantityUnit:'SF',unit:'SY',basis:'stated',rationale:'Same 100 SF floor area'}));
  const report=priceWholePlan({title:'Flooring',summary:'Remove carpet',assumptions:[],exclusions:[],components,unpriced:[],coverage:[{requirement:'Remove carpet and pad',componentIds:['carpet','pad'],status:'priced',reason:'Covered'}],review:{quantities:'100 SF'}});
  assert.equal(report.lines[0].catalogQuantity,100/9);
  assert.equal(report.lines[0].amount,16.44);
  assert.equal(report.lines[1].amount,8.44);
  assert.equal(report.catalogSubtotal,24.88);
  assert.ok(Math.abs(report.lines[0].personHours-(100/9*.035))<1e-12);
});
