import test from 'node:test';import assert from 'node:assert/strict';
import {priceWholePlan,wholeAppEstimate,checkWholePlan,estimateWholeProject,families,residentialTakeoffDefaults,reconcilePlanPolicy,evaluateQuantityFormula} from './whole-project.ts';
const plan=()=>({title:'White Bedroom Paint',summary:'Paint walls',assumptions:[],exclusions:[],components:[{id:'paint',category:'Painting',name:'White Paint — Two Coats',location:'Bedroom walls',kind:'catalog',row:9034,quantity:100,quantityFormula:null,quantityUnit:'SF',unit:'SF',basis:'stated',rationale:'Two-coat assembly includes both coats'}],unpriced:[],coverage:[{requirement:'Paint walls',componentIds:['paint'],status:'priced',reason:'Two coats'}],review:{quantities:'100 SF',inclusions:'Both coats',productivity:'1 person-hour',completeness:'Covered'}});
test('whole assembly preserves source price without double labor',()=>assert.equal(priceWholePlan(plan()).catalogSubtotal,81));
test('business labor replaces source labor rather than adding twice',()=>{const r=priceWholePlan(plan(),{painter:60});assert.equal(r.catalogSubtotal,96);assert.equal(r.lines[0].personHours,1)});
test('material waste buys only source material without installation',()=>{const p=plan();p.components.push({...p.components[0],id:'waste',name:'Extra paint material',kind:'material',quantity:10});assert.equal(priceWholePlan(p,{painter:60}).catalogSubtotal,99.6)});
test('extra labor uses person-hours without crew multiplication',()=>{const p=plan();p.components=[{...p.components[0],kind:'labor',row:1637,quantityUnit:'person-hour',unit:'person-hour',quantity:2}];assert.equal(priceWholePlan(p).catalogSubtotal,74.8);assert.equal(priceWholePlan(p,{standard_labor:50}).catalogSubtotal,100)});
test('invalid source units and duplicate components rejected',()=>{const p=plan();p.components[0].unit='Ea';assert.throws(()=>checkWholePlan(p));p.components[0].unit='SF';p.components.push({...p.components[0],id:'duplicate'});assert.throws(()=>checkWholePlan(p))});
test('uninspected catalog row rejected',()=>assert.throws(()=>checkWholePlan(plan(),new Set([3]))));
test('missing material is explicitly excluded, never claimed in complete total',()=>{const p=plan();p.unpriced=[{name:'Protection supplies',reason:'No rate'}];const e=wholeAppEstimate(priceWholePlan(p));assert.match(e.exclusions.join(' '),/Not included in total/);assert.equal(e.pricing.projectTotal,null);assert.equal(e.total,81)});
test('markup applied once and saved arithmetic reconciles',()=>{const e=wholeAppEstimate(priceWholePlan(plan(),{painter:60}),20,10);assert.equal(e.total,124.8);assert.equal(e.categories[0].items[0].name,'White Paint — Two Coats')});
test('completed checkpoint resumes without a provider call',async()=>{const p=plan();const s={version:3,title:p.title,summary:p.summary,facts:[],assumptions:[],families:[families().findIndex(f=>f.rows.includes(9034))],workPackages:['Painting'],wholePlan:p,reviewed:true};const out=await estimateWholeProject('Paint',new AbortController().signal,{apiKey:'test',model:'test',previous:s,resume:true,transport:()=>{throw Error('must not call')}});assert.equal(out.report.catalogSubtotal,81)});

test('approved laminate plank approximation is visibly labeled even when model renames it',()=>{const p=plan();p.components=[{...p.components[0],row:9520,name:'Plank installation'}];p.coverage[0].requirement='Install standard laminate flooring';const r=priceWholePlan(p);assert.equal(r.catalogSubtotal,798);assert.equal(r.lines[0].approximation,true);const e=wholeAppEstimate(r);assert.match(e.categories[0].items[0].name,/Laminate flooring.*approximation using resilient plank pricing/);assert.match(e.sanityCheck,/installation methods differ/);assert.equal(r.lines[0].source.row,9520);});
test('laminate approximation approval does not permit resilient tile assemblies',()=>{const p=plan();p.components=[{...p.components[0],row:9500,name:'Laminate flooring'}];assert.throws(()=>checkWholePlan(p),/Only resilient plank/);});
test('unpriced laminate can preserve supported carpet removal without substituting materials',()=>{const p=plan();p.components=[{...p.components[0],row:1471,name:'Remove carpet',quantityUnit:'SF',unit:'SY'}];p.coverage=[{requirement:'Remove carpet',componentIds:['paint'],status:'priced',reason:'Source demolition'},{requirement:'Install laminate flooring',componentIds:[],status:'partial',reason:'No compatible material assembly'}];p.unpriced=[{name:'Laminate flooring materials and installation',reason:'No compatible catalog assembly'}];const r=priceWholePlan(p);assert.equal(r.catalogSubtotal,27.22);assert.equal(r.status,'partial_priced_scope');assert(r.exclusions.some(x=>x.includes('Laminate')));});
test('independent review preserves a missing contractor disposal requirement as unpriced',async()=>{
 const p=plan();const reviewed=structuredClone(p);reviewed.unpriced=[{name:'Contractor disposal',reason:'No supplied disposal fee'}];reviewed.coverage.push({requirement:'Contractor handles disposal',componentIds:[],status:'partial',reason:'Disposal fee unsupported'});
 const stages=[];const checkpoints=[];
 const out=await estimateWholeProject('Paint walls and contractor disposes of debris',new AbortController().signal,{apiKey:'test',model:'test',previous:{version:3,title:p.title,summary:p.summary,facts:['Contractor handles disposal'],assumptions:[],families:[families().findIndex(f=>f.rows.includes(9034))],workPackages:['Painting'],wholePlan:p},resume:true,onCheckpoint:async s=>checkpoints.push(structuredClone(s)),transport:async(url,init)=>{const body=JSON.parse(init.body);stages.push(body.text.format.name);const input=JSON.parse(body.input[0].content[0].text);assert.equal(input.customer,'Paint walls and contractor disposes of debris');assert.deepEqual(input.proposedPlan,p);assert(input.rows.some(r=>r[0]===9034));return new Response(JSON.stringify({status:'completed',output:[{content:[{type:'output_text',text:JSON.stringify(reviewed)}]}]}));}});
 assert.deepEqual(stages,['whole_review']);assert.equal(out.state.reviewed,true);assert.equal(out.report.status,'partial_priced_scope');assert.equal(out.report.catalogSubtotal,81);assert(out.report.exclusions.some(x=>x.includes('Contractor disposal')));assert.equal(checkpoints.at(-1).reviewed,true);
});

test('explicit scope requirements cannot disappear from final coverage',()=>{assert.throws(()=>checkWholePlan(plan(),undefined,['Paint walls','Contractor handles disposal']),/Missing scope coverage: Contractor handles disposal/);});

test('scope reference failure gives the reviewer valid final IDs for recovery',()=>{const p=plan();p.coverage[0].componentIds=['obsolete'];assert.throws(()=>checkWholePlan(p),/missing component IDs: obsolete.*Valid component IDs: paint/);p.coverage[0].componentIds=[];assert.throws(()=>checkWholePlan(p),/unsupported scope must be partial/);});

const bathroomInput='Estimate a remodel of a 5 ft × 8 ft bathroom. Keep the existing layout and plumbing locations. Remove the existing floor, vanity, toilet, and tub/shower surround. Install a new bathroom floor, vanity and countertop, toilet, and tub/shower surround. Repaint the walls';
test('bathroom request cannot acquire an unrequested laminate material',()=>{const p=plan();p.components[0].name='Laminate bathroom flooring';assert.throws(()=>checkWholePlan(p,undefined,[],bathroomInput),/did not request laminate/);});
test('surround-only work rejects whole tub removal or procurement regardless of line name',()=>{for(const row of [10294,10302]){const p=plan();p.components=[{...p.components[0],row,quantity:1,quantityUnit:'Ea',unit:'Ea',name:'Surround replacement'}];assert.throws(()=>checkWholePlan(p,undefined,[],bathroomInput),/Surround-only scope/);}});
test('repainting does not authorize full-wall gypsum repairs',()=>{const p=plan();p.components.push({...p.components[0],id:'finish'});p.components[0].row=8890;assert.throws(()=>checkWholePlan(p,undefined,[],bathroomInput),/Repainting alone/);assert.doesNotThrow(()=>checkWholePlan(p,undefined,[],bathroomInput+' Repair damaged drywall before painting.'));});
test('vanity installed assemblies cannot duplicate reconnect-and-replace labor',()=>{const p=plan();p.components=[{...p.components[0],row:2822,quantity:1,quantityUnit:'Ea',unit:'Ea',location:'Bathroom vanity'},{...p.components[0],id:'vanity',row:1351,quantity:1,quantityUnit:'Ea',unit:'Ea',location:'Bathroom vanity'}];assert.throws(()=>checkWholePlan(p),/overlaps/);p.components[0].row=2820;assert.doesNotThrow(()=>checkWholePlan(p));p.components[0].row=2822;p.components[1].kind='material';assert.doesNotThrow(()=>checkWholePlan(p));});

test('retained layout is a zero-work constraint, not a missing paid component',()=>{
 const p=plan();p.coverage.push({requirement:'Keep the existing layout.',componentIds:[],status:'priced',reason:'No relocation'});
 checkWholePlan(p);assert.equal(p.coverage.at(-1).status,'excluded');assert.equal(priceWholePlan(p).catalogSubtotal,81);
 p.coverage.push({requirement:'Install a new vanity.',componentIds:[],status:'priced',reason:'Included'});
 assert.throws(()=>checkWholePlan(p),/needs finalized component IDs/);
});
test('invalid labor billing gives component-specific recovery instructions',()=>{
 const p=plan();p.components[0].kind='labor';
 assert.throws(()=>checkWholePlan(p),/Component paint.*quantityUnit=person-hour.*kind=catalog/);
});

test('surround wall substrate demolition requires replacement backing at the same location',()=>{
 const p=plan();p.components=[{...p.components[0],row:3618,name:'Remove surround backing',location:'Bathroom surround',quantity:60}];
 assert.throws(()=>checkWholePlan(p),/Floor backer board does not cover surround walls/);
 p.components.push({...p.components[0],id:'backing',row:1677,name:'Wall backer board'});
 assert.doesNotThrow(()=>checkWholePlan(p));p.components[1].location='Bathroom floor';
 assert.throws(()=>checkWholePlan(p),/no replacement backing/);
});

test('vanity replacement labor cannot masquerade as supplied new cabinet and top',()=>{
 const p=plan();p.components=[{...p.components[0],row:1341,name:'Replace vanity',location:'Bathroom vanity',quantity:1,quantityUnit:'Ea',unit:'Ea'}];
 p.coverage=[{requirement:'Install new vanity and countertop',componentIds:['paint'],status:'priced',reason:'Replacement'}];
 assert.throws(()=>checkWholePlan(p),/does not supply the new fixture/);
 p.components.push({...p.components[0],id:'material',row:1359,kind:'material',name:'New vanity and sink top'});
 assert.doesNotThrow(()=>checkWholePlan(p));
 p.components[1].kind='catalog';assert.throws(()=>checkWholePlan(p),/overlaps/);
 p.components.pop();p.unpriced=[{name:'New vanity and sink top',reason:'No material rate'}];p.coverage[0].status='partial';
 assert.doesNotThrow(()=>checkWholePlan(p));assert.equal(priceWholePlan(p).status,'partial_priced_scope');
});

test('owner-handled disposal cannot create an unpriced contractor gap',()=>{
 const p=plan();p.unpriced=[{name:'Separate disposal allowance',reason:'Owner handles disposal and no fee is supplied'}];
 assert.throws(()=>checkWholePlan(p,undefined,[],'Paint walls. Owner handles debris disposal.'),/explicit exclusion/);
 assert.doesNotThrow(()=>checkWholePlan(p,undefined,[],'Paint walls. Contractor handles disposal.'));
 p.unpriced=[];p.exclusions=['Owner handles disposal'];assert.doesNotThrow(()=>checkWholePlan(p,undefined,[],'Paint walls. Owner handles disposal.'));
});

test('plumbing disconnection cannot cover complete vanity cabinet demolition',()=>{
 const p=plan();p.components=[{...p.components[0],row:1339,quantity:1,quantityUnit:'Ea',unit:'Ea'}];
 p.coverage=[{requirement:'Disconnect and remove one existing vanity and sink top',componentIds:['paint'],status:'priced',reason:'Closest removal'}];
 assert.throws(()=>checkWholePlan(p),/plumbing-disconnection family/);
 p.components[0].row=2820;assert.doesNotThrow(()=>checkWholePlan(p));
 p.components[0].row=1339;p.coverage[0].requirement='Disconnect plumbing under vanity';assert.doesNotThrow(()=>checkWholePlan(p));
});

test('overlap recovery names the supplied compatible demolition row',()=>{
 const p=plan();p.components=[{...p.components[0],row:1341,quantity:1,quantityUnit:'Ea',unit:'Ea',location:'Vanity'}, {...p.components[0],id:'new',row:1359,quantity:1,quantityUnit:'Ea',unit:'Ea',location:'Vanity'}];
 assert.throws(()=>checkWholePlan(p,new Set([1341,1359,2820])),/component paint row 1341.*component new row 1359.*2820/);
 assert.throws(()=>checkWholePlan(p,new Set([1341,1359])),/none inspected/);
});

test('vanity scope supplies the missing demolition family before model planning',async()=>{
 const p=plan();p.components=[{...p.components[0],id:'demo',row:2820,name:'Remove old vanity',location:'Vanity',quantity:1,quantityUnit:'Ea',unit:'Ea'},{...p.components[0],id:'new',row:1359,name:'Install new vanity and top',location:'Vanity',quantity:1,quantityUnit:'Ea',unit:'Ea'}];
 p.coverage=[{requirement:'Remove existing vanity',componentIds:['demo'],status:'priced',reason:'Cabinet demolition'},{requirement:'Install new vanity',componentIds:['new'],status:'priced',reason:'Installed cabinet and top'}];
 let calls=0;
 const out=await estimateWholeProject('Remove existing vanity and install new vanity. Owner handles disposal.',new AbortController().signal,{apiKey:'test',model:'test',previous:{version:3,title:p.title,summary:p.summary,facts:[],requirements:p.coverage.map(c=>c.requirement),assumptions:[],families:[families().findIndex(f=>f.rows.includes(1359))],workPackages:['Vanity']},resume:true,transport:async(url,init)=>{
  const body=JSON.parse(init.body),input=JSON.parse(body.input[0].content[0].text);assert(input.rows.some(row=>row[0]===2820));assert(input.rows.some(row=>row[0]===1359));calls++;
  return new Response(JSON.stringify({status:'completed',output:[{content:[{type:'output_text',text:JSON.stringify(p)}]}]}));
 }});
 assert.equal(calls,2);assert.equal(out.state.reviewed,true);assert(out.report.lines.some(line=>line.source.row===2820));
});

test('owner disposal gap detection uses its name as well as rationale',()=>{
 const p=plan();p.unpriced=[{name:'Owner-handled disposal/hauling',reason:'No separate non-disposal removal row is available.'}];
 assert.throws(()=>checkWholePlan(p,undefined,[],'Owner handles disposal after removal.'),/explicit exclusion/);
});

// Regression: a mixed job omitted toilet removal even though the complete family exists.
test('toilet removal family repairs discovery omissions and invalidates an incomplete resumed plan',async()=>{
 const p=plan();p.components=[{...p.components[0],id:'demo',row:11366,name:'Remove existing toilet',location:'Bathroom',quantity:1,quantityUnit:'Ea',unit:'Ea'},{...p.components[0],id:'new',row:11386,name:'Install standard toilet',location:'Bathroom',quantity:1,quantityUnit:'Ea',unit:'Ea'}];
 p.coverage=[{requirement:'Remove existing toilet',componentIds:['demo'],status:'priced',reason:'Removal assembly'},{requirement:'Install standard toilet',componentIds:['new'],status:'priced',reason:'Installed fixture'}];
 let calls=0;
 const out=await estimateWholeProject('In one bathroom, remove one existing toilet and install one standard toilet. Owner handles disposal.',new AbortController().signal,{apiKey:'test',model:'test',previous:{version:3,title:p.title,summary:p.summary,facts:[],requirements:p.coverage.map(c=>c.requirement),assumptions:[],families:[families().findIndex(f=>f.rows.includes(11386))],workPackages:['Toilet'],wholePlan:{...p,components:p.components.slice(1)},reviewed:true},resume:true,transport:async(url,init)=>{
  const body=JSON.parse(init.body),input=JSON.parse(body.input[0].content[0].text);const removal=families().find(f=>f.rows.includes(11366));for(const row of removal.rows)assert(input.rows.some(r=>r[0]===row));calls++;
  return new Response(JSON.stringify({status:'completed',output:[{content:[{type:'output_text',text:JSON.stringify(p)}]}]}));
 }});
 assert.equal(calls,2);assert.equal(out.state.reviewed,true);assert(out.report.lines.some(line=>line.source.row===11366));
});

test('supplied ceramic floor assemblies cannot be declared absent under a ceramic assumption',()=>{
 const p=plan();p.assumptions=['Assume new bathroom floor is ceramic tile.'];p.unpriced=[{name:'Install a new bathroom floor',reason:'No compatible installed bathroom floor assembly was supplied.'}];
 assert.throws(()=>checkWholePlan(p,new Set([9034,1651]),[],bathroomInput),/incorrectly says.*supplied/);
 p.unpriced[0].reason='Specified marble material is unavailable; ceramic is not a compatible supplied material.';assert.doesNotThrow(()=>checkWholePlan(p,new Set([9034,1651]),[],bathroomInput));
});
test('estimator policies cannot become customer exclusions and owner disposal cannot be invented',()=>{
 const p=plan();p.exclusions=['No questions for estimable work.'];assert.throws(()=>checkWholePlan(p,undefined,[],bathroomInput),/Estimator policy/);
 p.exclusions=['Owner handles disposal after removal.'];assert.throws(()=>checkWholePlan(p,undefined,[],bathroomInput),/was not requested/);assert.doesNotThrow(()=>checkWholePlan(p,undefined,[],bathroomInput+' Owner handles disposal.'));
});
test('surround discovery omissions supply wall finish, demolition and backing families to both stages',async()=>{
 const p=plan();p.components=[{...p.components[0],row:1673,name:'Install ceramic wall surround',location:'Tub surround',quantity:60}];p.coverage=[{requirement:'Install tub/shower surround',componentIds:['paint'],status:'priced',reason:'Wall finish assembly'}];let calls=0;
 const out=await estimateWholeProject('Install a new tub/shower surround.',new AbortController().signal,{apiKey:'test',model:'test',previous:{version:3,title:p.title,summary:p.summary,facts:[],requirements:p.coverage.map(c=>c.requirement),assumptions:[],families:[families().findIndex(f=>f.rows.includes(9034))],workPackages:['Surround']},resume:true,transport:async(url,init)=>{
  const input=JSON.parse(JSON.parse(init.body).input[0].content[0].text);for(const row of [1673,1677,3618])assert(input.rows.some(r=>r[0]===row));calls++;
  return new Response(JSON.stringify({status:'completed',output:[{content:[{type:'output_text',text:JSON.stringify(p)}]}]}));
 }});assert.equal(calls,2);assert.equal(out.state.reviewed,true);
});

test('vanity replacement cannot repeat demolition already included in that operation',()=>{
 const p=plan();p.components=[{...p.components[0],id:'demo',row:2820,quantity:1,quantityUnit:'Ea',unit:'Ea',location:'Vanity'},{...p.components[0],id:'replace',row:1341,quantity:1,quantityUnit:'Ea',unit:'Ea',location:'Vanity'}];p.unpriced=[{name:'Vanity procurement',reason:'Specific unsupported custom top'}];p.coverage=[{requirement:'Replace vanity',componentIds:['demo','replace'],status:'partial',reason:'Missing custom material'}];assert.throws(()=>checkWholePlan(p),/Vanity removal is duplicated/);
});
test('provided new vanity material rows cannot be declared unavailable',()=>{
 const p=plan();p.unpriced=[{name:'Vanity cabinet and countertop procurement',reason:'No supplied catalog row provides new material.'}];assert.throws(()=>checkWholePlan(p,new Set([9034,1359]),[],bathroomInput),/procurement rows are supplied/);
 p.unpriced[0].reason='Custom concrete top has no compatible specification.';assert.doesNotThrow(()=>checkWholePlan(p,new Set([9034,1359]),[],bathroomInput));
});

test('missing wet-area waterproofing makes surround installation coverage partial',()=>{
 const p=plan();p.unpriced=[{name:'Tub/shower waterproofing membrane procurement',reason:'No suitable source'}];p.coverage=[{requirement:'Install new tub/shower surround',componentIds:['paint'],status:'priced',reason:'Finish priced'}];assert.throws(()=>checkWholePlan(p),/coverage.*must be partial/);p.coverage[0].status='partial';p.coverage[0].reason='Finish supported, waterproofing procurement missing';assert.doesNotThrow(()=>checkWholePlan(p));
});

test('unspecified standard tub geometry uses one disclosed takeoff; explicit geometry and images override it',()=>{
 assert.equal(residentialTakeoffDefaults(bathroomInput).surround.areaSF,50);
 for(const suffix of [' Surround is 90 SF.',' Tile the surround to the ceiling.',' The shower walls are 8 feet high.'])assert.equal(residentialTakeoffDefaults(bathroomInput+suffix),null);
 assert.equal(residentialTakeoffDefaults(bathroomInput,true),null);assert.equal(residentialTakeoffDefaults('Install a bathroom shower stall surround.'),null);
 const p=plan();p.components=[{...p.components[0],row:1673,name:'Install tub surround',location:'Tub surround',quantity:90}];assert.throws(()=>checkWholePlan(p,undefined,[],bathroomInput),/disclosed standard.*50 SF/);p.components[0].quantity=50;assert.doesNotThrow(()=>checkWholePlan(p,undefined,[],bathroomInput));p.components[0].quantity=90;assert.doesNotThrow(()=>checkWholePlan(p,undefined,[],bathroomInput+' Surround is 90 SF.'));
});

test('floor installation cannot be covered by demolition or another installed trade',()=>{
 const p=plan();p.components[0]={...p.components[0],row:3030,quantity:40};p.coverage=[{requirement:'Install a new bathroom floor',componentIds:['paint'],status:'priced',reason:'Covered'}];assert.throws(()=>checkWholePlan(p),/only demolition/);
 p.components[0].row=1673;assert.throws(()=>checkWholePlan(p),/no compatible floor installation/);p.components[0].row=1651;assert.doesNotThrow(()=>checkWholePlan(p));
});
test('unrequested hidden repairs are not an unpriced job requirement',()=>{
 const p=plan();p.unpriced=[{name:'Hidden substrate repairs',reason:'Not stated and cannot be assumed.'}];assert.throws(()=>checkWholePlan(p),/Unrequested hidden repairs/);p.unpriced=[];p.exclusions=['Hidden repairs excluded unless discovered'];assert.doesNotThrow(()=>checkWholePlan(p));
});

test('a reviewed cached demolition-only installation plan must be regenerated before pricing',async()=>{
 const p=plan();p.components=[{...p.components[0],row:1651,quantity:40,name:'Install ceramic floor',location:'Floor'}];p.coverage=[{requirement:'Install ceramic floor',componentIds:['paint'],status:'priced',reason:'Installed floor'}];const old=structuredClone(p);old.components[0].row=3030;let calls=0;
 const out=await estimateWholeProject('Install ceramic floor.',new AbortController().signal,{apiKey:'test',model:'test',previous:{version:3,title:p.title,summary:p.summary,facts:[],requirements:p.coverage.map(c=>c.requirement),assumptions:[],families:[families().findIndex(f=>f.rows.includes(1651)),families().findIndex(f=>f.rows.includes(3030))],workPackages:['Floor'],wholePlan:old,reviewed:true},resume:true,transport:async()=>{calls++;return new Response(JSON.stringify({status:'completed',output:[{content:[{type:'output_text',text:JSON.stringify(p)}]}]}));}});assert.equal(calls,2);assert.equal(out.report.lines[0].source.row,1651);
});

test('single-unit bathroom fixture selection cannot use a bulk-volume discount',()=>{
 const p=plan();p.components=[{...p.components[0],row:2819,name:'Remove vanity',location:'Vanity',quantity:1,quantityUnit:'Ea',unit:'Ea'}];p.coverage=[{requirement:'Remove vanity',componentIds:['paint'],status:'priced',reason:'Demo'}];assert.throws(()=>checkWholePlan(p,new Set([2819,2820]),[],bathroomInput),/small-volume rows 2820/);p.components[0].row=2820;assert.doesNotThrow(()=>checkWholePlan(p,new Set([2819,2820]),[],bathroomInput));p.components[0].row=2819;assert.doesNotThrow(()=>checkWholePlan(p,undefined,[],bathroomInput+' Use large-volume pricing.'));
});
test('contractor disposal coverage requires an actual fee-inclusive disposal assembly or a gap',()=>{
 const p=plan();p.components=[{...p.components[0],row:2820,quantity:1,quantityUnit:'Ea',unit:'Ea'}];p.coverage=[{requirement:'Contractor hauling and disposal of demolition debris.',componentIds:['paint'],status:'priced',reason:'Demo to dumpster'}];assert.throws(()=>checkWholePlan(p),/does not establish off-site/);p.components[0].row=2566;assert.doesNotThrow(()=>checkWholePlan(p));p.coverage[0].status='excluded';assert.throws(()=>checkWholePlan(p),/silently excluded/);
});

test('policy reconciliation preserves exact specification and quantity while correcting volume',()=>{
 const p=plan();p.components=[{...p.components[0],row:1358,name:'Composition vanity',quantity:1,quantityUnit:'Ea',unit:'Ea'}];
 reconcilePlanPolicy(p,new Set([1358,1359]),'Install a vanity in one bathroom.');assert.equal(p.components[0].row,1359);assert.equal(p.components[0].quantity,1);
 const q=plan();q.components=[{...p.components[0],row:1358}];reconcilePlanPolicy(q,new Set([1358]),'Install a vanity in one bathroom.');assert.equal(q.components[0].row,1358);
 const r=plan();r.components=[{...p.components[0],row:1358,quantity:8}];reconcilePlanPolicy(r,new Set([1358,1359]),'Install vanities in multiple bathrooms.');assert.equal(r.components[0].row,1358);
});
test('policy reconciliation preserves missing costs and makes wet-area coverage partial',()=>{
 const p=plan();p.unpriced=[{name:'Waterproofing membrane',reason:'No compatible catalog procurement row'}];p.coverage=[{requirement:'Install tub/shower surround',componentIds:['paint'],status:'priced',reason:'Finish is priced'},{requirement:'Paint walls',componentIds:['paint'],status:'priced',reason:'Paint'}];
 const before=JSON.stringify(p.components);reconcilePlanPolicy(p,undefined,'Bathroom remodel');assert.equal(p.coverage[0].status,'partial');assert.equal(p.coverage[1].status,'priced');assert.equal(p.unpriced.length,1);assert.equal(JSON.stringify(p.components),before);assert.equal(priceWholePlan(p).status,'partial_priced_scope');
});

test('floor-mounted toilet coverage does not require floor finish installation',()=>{
 const p=plan();p.components=[{...p.components[0],row:11386,quantity:1,quantityUnit:'Ea',unit:'Ea',name:'Standard toilet',location:'Bathroom'}];
 for(const requirement of ['Install one standard floor-mounted toilet','Install a floor mounted toilet','Install a floor-standing toilet']){p.coverage=[{requirement,componentIds:['paint'],status:'priced',reason:'Installed toilet assembly'}];assert.doesNotThrow(()=>checkWholePlan(p));}
 p.coverage=[{requirement:'Install a floor-mounted toilet and a new ceramic floor',componentIds:['paint'],status:'priced',reason:'Toilet only'}];assert.throws(()=>checkWholePlan(p),/floor installation/);
});


test('owner disposal after vanity removal does not invalidate on-site demolition',()=>{
 const p=plan();p.components=[{...p.components[0],id:'demo',row:2820,quantity:1,quantityUnit:'Ea',unit:'Ea'}];p.coverage=[{requirement:'Disconnect and remove one existing vanity and sink top',componentIds:['demo'],status:'partial',reason:'The removal row covers demolition, but its dumpster language exceeds the owner-handled disposal scope.'}];
 const before=JSON.stringify(p.components);reconcilePlanPolicy(p,undefined,'Remove vanity. Owner handles disposal after removal.');assert.equal(p.coverage[0].status,'priced');assert.equal(JSON.stringify(p.components),before);
 p.coverage[0].status='partial';p.coverage[0].reason='Owner dumpster disposal differs and damaged cabinet repairs are unsupported.';reconcilePlanPolicy(p,undefined,'Remove vanity. Owner handles disposal after removal.');assert.equal(p.coverage[0].status,'partial');
 p.coverage[0].reason='Owner dumpster disposal mismatch.';reconcilePlanPolicy(p,undefined,'Remove vanity. Contractor handles disposal.');assert.equal(p.coverage[0].status,'partial');
});
test('missing incidental vanity caulk measurements require coherent review, preserving explicit sealing and real rate gaps',()=>{
 const p=plan();p.components=[{...p.components[0],row:1359,quantity:1,quantityUnit:'Ea',unit:'Ea',name:'Installed vanity'}];p.coverage=[{requirement:'Install vanity',componentIds:['paint'],status:'priced',reason:'Installed assembly'}];p.unpriced=[{name:'Seal/caulk vanity installation as needed',reason:'No measurable linear footage or separate catalog quantity was provided.'}];
 assert.throws(()=>checkWholePlan(p,undefined,[],'Install a vanity.'),/incidental vanity sealing/);assert.doesNotThrow(()=>checkWholePlan(p,undefined,[],'Install a vanity and caulk its edges.'));
 p.unpriced[0].reason='No compatible sealant procurement rate is supplied.';assert.doesNotThrow(()=>checkWholePlan(p,undefined,[],'Install a vanity.'));assert.equal(p.unpriced.length,1);
});


test('quantity calculator retains mixed-unit opening deductions and waste without code evaluation',()=>{
 assert(Math.abs(evaluateQuantityFormula('2*(10+12)*8-(30*80/144)-2*(3*4)')-311.3333333333333)<1e-10);
 assert.equal(evaluateQuantityFormula('120 * .10'),12);assert.equal(evaluateQuantityFormula('(3+4)*2/7'),2);
 for(const formula of ['1/0','1-2','0','2**3','Math.random()','1;globalThis.x=1','1e3','1+','(1+2','1  + 2)'])assert.throws(()=>evaluateQuantityFormula(formula));
 assert.throws(()=>evaluateQuantityFormula('('.repeat(22)+'1'+')'.repeat(22)));
});
test('derived quantities are computed from formulas without changing stated quantities or prices',()=>{
 const p=plan();p.components[0].basis='derived';p.components[0].quantity=311;p.components[0].quantityFormula='2*(10+12)*8-(30*80/144)-2*(3*4)';
 reconcilePlanPolicy(p,undefined,'Paint bedroom walls');assert(Math.abs(p.components[0].quantity-311.3333333333333)<1e-10);assert.equal(priceWholePlan(p,{painter:60}).catalogSubtotal,298.88);
 p.components[0].quantity=311;assert.throws(()=>checkWholePlan(p),/arithmetic takeoff/);
 p.components[0].quantityFormula=null;assert.throws(()=>reconcilePlanPolicy(p,undefined,'Paint walls'),/needs its arithmetic takeoff/);
 p.components[0].basis='stated';p.components[0].quantity=100;assert.doesNotThrow(()=>reconcilePlanPolicy(p,undefined,'Paint 100 SF'));assert.equal(p.components[0].quantity,100);
});
test('standard laminate cannot silently use a supplied higher-grade plank proxy including waste',()=>{
 const p=plan();p.components=[{...p.components[0],row:9522,name:'Laminate flooring',quantity:120}];p.coverage=[{requirement:'Install laminate flooring',componentIds:['paint'],status:'priced',reason:'Approved proxy'}];
 assert.throws(()=>checkWholePlan(p,new Set([9520,9522]),[],'Install standard laminate flooring.'),/different resilient-plank grade/);
 p.components[0].kind='material';assert.throws(()=>checkWholePlan(p,new Set([9520,9522]),[],'Install standard laminate flooring.'),/different resilient-plank grade/);
 p.components[0].kind='catalog';p.components[0].row=9520;assert.doesNotThrow(()=>checkWholePlan(p,new Set([9520,9522]),[],'Install standard laminate flooring.'));
 p.components[0].row=9522;assert.doesNotThrow(()=>checkWholePlan(p,new Set([9520,9522]),[],'Install average-grade laminate flooring.'));
 assert.doesNotThrow(()=>checkWholePlan(p,new Set([9520,9522]),[],'Install standard laminate flooring. Correction: use average-grade laminate flooring.'));
 assert.doesNotThrow(()=>checkWholePlan(p,new Set([9520,9522]),[],'Install laminate flooring and a standard vanity.'));
 assert.throws(()=>checkWholePlan(p,new Set([9520,9522]),[],'Install laminate flooring in standard grade.'),/different resilient-plank grade/);
});


test('installed assembly and material-only waste may share a source row, never a component ID',()=>{
 const p=plan();p.components=[{...p.components[0],id:'component-1',row:9520,name:'Laminate installation',quantity:120},{...p.components[0],id:'component-2',row:9520,name:'Laminate cutting waste',kind:'material',quantity:12}];p.coverage=[{requirement:'Install laminate',componentIds:['component-1'],status:'priced',reason:'Approved installed proxy'},{requirement:'Purchase cutting waste',componentIds:['component-2'],status:'priced',reason:'Material only'}];
 assert.doesNotThrow(()=>checkWholePlan(p));assert.equal(priceWholePlan(p).catalogSubtotal,989.4);
 p.components[1].id='component-1';assert.throws(()=>checkWholePlan(p),/Duplicate component ID component-1.*material-only waste/);
});


test('split vanity disconnection coverage is supported despite excluded subsequent disposal',()=>{
 const p=plan();p.components=[{...p.components[0],id:'demo',row:2820,quantity:1,quantityUnit:'Ea',unit:'Ea'},{...p.components[0],id:'installed',row:1359,quantity:1,quantityUnit:'Ea',unit:'Ea'}];
 p.coverage=[{requirement:'Disconnect plumbing under vanity cabinet.',componentIds:['demo'],status:'partial',reason:'The demolition line covers disconnecting and removal, but the row also includes dumpster disposal language that is not required here.'},{requirement:'Remove one existing vanity cabinet and sink top.',componentIds:['demo'],status:'priced',reason:'Source demolition'},{requirement:'Install a new vanity and sink top.',componentIds:['installed'],status:'priced',reason:'Installed assembly'},{requirement:'Keep plumbing locations.',componentIds:['installed'],status:'priced',reason:'Same-location reconnection'}];
 const original=JSON.stringify(p.components);reconcilePlanPolicy(p,undefined,'Replace vanity. Owner handles disposal after removal.');assert.equal(p.coverage[0].status,'priced');assert.equal(p.coverage[3].status,'excluded');assert.deepEqual(p.coverage[3].componentIds,[]);assert.equal(JSON.stringify(p.components),original);assert.equal(priceWholePlan(p,{plumber:95,standard_labor:50}).catalogSubtotal,899.93);
 p.coverage[0].status='partial';p.coverage[0].reason='Disconnect is priced, but damaged plumbing repairs are unsupported despite the dumpster row.';reconcilePlanPolicy(p,undefined,'Replace vanity. Owner handles disposal after removal.');assert.equal(p.coverage[0].status,'partial');
});

test('separate vanity disconnect cannot duplicate demolition included disconnect',()=>{
 const p=plan();p.components=[{...p.components[0],id:'disconnect',row:1339,quantity:1,quantityUnit:'Ea',unit:'Ea',location:'Bathroom'},{...p.components[0],id:'demo',row:2820,quantity:1,quantityUnit:'Ea',unit:'Ea',location:'Bathroom'}];
 p.coverage=[];assert.throws(()=>checkWholePlan(p),/disconnection is duplicated/);
 p.components[0].location='Other bathroom';assert.doesNotThrow(()=>checkWholePlan(p));
 p.components[0].location='Bathroom';p.components[0].quantity=2;assert.doesNotThrow(()=>checkWholePlan(p));
});
test('explicit standard toilet must not use generic average material replacement row',()=>{
 const p=plan();p.components=[{...p.components[0],row:11380,quantity:1,quantityUnit:'Ea',unit:'Ea'}];
 assert.throws(()=>checkWholePlan(p,new Set([11380,11386]),[],'Install one standard two-piece floor-mounted toilet.'),/average-grade material/);
 assert.doesNotThrow(()=>checkWholePlan(p,new Set([11380]),[],'Install one standard two-piece floor-mounted toilet.'));
 assert.doesNotThrow(()=>checkWholePlan(p,undefined,[],'Install one average two-piece toilet.'));
 p.components[0].row=11386;assert.doesNotThrow(()=>checkWholePlan(p,undefined,[],'Install one standard toilet.'));
});

test('stated waste percentage charges incremental material, not total purchase',()=>{
 const p=plan();p.components=[{...p.components[0],id:'installed',row:9520,name:'Laminate floor',location:'Bedroom',quantity:120,quantityUnit:'SF',unit:'SF'},{...p.components[0],id:'waste',row:9520,name:'Laminate cutting waste',location:'Bedroom',kind:'material',quantity:132,quantityUnit:'SF',unit:'SF',basis:'derived',quantityFormula:'120*1.1'}];p.coverage=[];
 for(const customer of ['Install laminate with 10% cutting waste.','Purchase 10% additional material for cutting waste, but install only 120 SF.','Purchase 10% additional cutting waste.'])assert.throws(()=>checkWholePlan(p,undefined,[],customer),/base material twice/);
 p.components[1].quantity=12;p.components[1].quantityFormula='120*0.1';assert.doesNotThrow(()=>checkWholePlan(p,undefined,[],'Install laminate with 10% cutting waste.'));
 p.components[1].quantity=120;p.components[1].quantityFormula='120*1';assert.doesNotThrow(()=>checkWholePlan(p,undefined,[],'Install laminate with 100% cutting waste.'));
 p.components[1].row=9034;p.components[1].quantity=132;p.components[1].quantityFormula='120*1.1';assert.doesNotThrow(()=>checkWholePlan(p,undefined,[],'Install laminate with 10% cutting waste.'));
});

test('ready-for-painting surfaces do not acquire unrequested cleaning',()=>{
 const p=plan();p.components.push({...p.components[0],id:'clean',row:8862,name:'Clean walls'});
 assert.throws(()=>checkWholePlan(p,undefined,[],'Drywall is sound and ready for painting.'),/adds cleaning/);
 assert.doesNotThrow(()=>checkWholePlan(p,undefined,[],'Clean the walls, which are ready for painting.'));
 assert.doesNotThrow(()=>checkWholePlan(p,undefined,[],'Wash dirty walls before painting.'));
});
test('supplied vanity demolition assembly is not recast as labor hours',()=>{
 const p=plan();p.components=[{...p.components[0],row:2820,name:'Disconnect and remove vanity',kind:'labor',quantity:1.54,quantityUnit:'person-hour',unit:'person-hour'}];p.coverage=[{requirement:'Remove vanity',componentIds:['paint'],status:'priced',reason:'Removal'}];
 assert.throws(()=>checkWholePlan(p),/recast assembly/);
 p.components[0].kind='catalog';p.components[0].quantity=1;p.components[0].quantityUnit='Ea';p.components[0].unit='Ea';assert.doesNotThrow(()=>checkWholePlan(p));
});

test('explicit owner disposal responsibility is an exclusion even when removal row mentions dumpster',()=>{
 const p=plan();p.components=[{...p.components[0],row:2820,quantity:1,quantityUnit:'Ea',unit:'Ea'}];p.coverage=[{requirement:'Owner handles disposal after removal.',componentIds:['paint'],status:'partial',reason:'The removal row references a dumpster.'}];
 const components=JSON.stringify(p.components);reconcilePlanPolicy(p,undefined,'Replace vanity. Owner handles disposal after removal.');assert.equal(p.coverage[0].status,'excluded');assert.deepEqual(p.coverage[0].componentIds,[]);assert.equal(JSON.stringify(p.components),components);
 p.coverage[0].status='partial';reconcilePlanPolicy(p,undefined,'Contractor handles disposal.');assert.equal(p.coverage[0].status,'partial');
});

test('toilet installation scope supplies standard grade family even if discovery selected only generic replacement',async()=>{
 const p=plan();p.components=[{...p.components[0],row:11386,name:'Standard toilet',quantity:1,quantityUnit:'Ea',unit:'Ea'}];p.coverage=[{requirement:'Install standard toilet',componentIds:['paint'],status:'priced',reason:'Installed assembly'}];
 let calls=0;
 const out=await estimateWholeProject('Install one standard two-piece floor-mounted toilet. Use small-volume pricing.',new AbortController().signal,{apiKey:'test',model:'test',previous:{version:3,title:p.title,summary:p.summary,facts:[],requirements:['Install standard toilet'],assumptions:[],families:[families().findIndex(f=>f.rows.includes(11380))],workPackages:['Plumbing']},resume:true,transport:async(url,init)=>{
 const body=JSON.parse(init.body),input=JSON.parse(body.input[0].content[0].text);assert(input.rows.some(row=>row[0]===11386));calls++;return new Response(JSON.stringify({status:'completed',output:[{content:[{type:'output_text',text:JSON.stringify(p)}]}]}),{status:200});
 }});assert.equal(calls,2);assert.equal(out.report.lines[0].source.row,11386);
});

test('supplied vanity removal cannot become a missing task solely because owner handles later disposal',()=>{
 const p=plan();p.unpriced=[{name:'Disconnect and remove existing vanity and sink top',reason:'Available removal rows include dumpster disposal and do not fit owner-handled disposal.'}];
 assert.throws(()=>checkWholePlan(p,new Set([9034,2820]),[],'Remove vanity. Owner handles disposal after removal.'),/does not invalidate/);
 assert.doesNotThrow(()=>checkWholePlan(p,new Set([9034]),[],'Remove vanity. Owner handles disposal after removal.'));
 p.unpriced[0].reason='Owner disposal is excluded, but damaged plumbing repairs are unsupported.';assert.doesNotThrow(()=>checkWholePlan(p,new Set([9034,2820]),[],'Remove vanity. Owner handles disposal after removal.'));
});
test('routine vanity finish sealing does not duplicate a full installed fixture assembly',()=>{
 const p=plan();p.components=[{...p.components[0],id:'vanity',row:1359,name:'Install new vanity and sink top',location:'Bathroom vanity',quantity:1,quantityUnit:'Ea',unit:'Ea'},{...p.components[0],id:'caulk',row:1591,name:'Caulk vanity-top perimeter',location:'Bathroom vanity',quantity:100/12,quantityUnit:'LF',unit:'LF'}];p.coverage=[{requirement:'Install vanity',status:'priced',reason:'Installed fixture',componentIds:['vanity','caulk']}];
 assert.throws(()=>checkWholePlan(p,undefined,[],'Install a new vanity and sink top.'),/routine vanity finishing/);
 p.components[1].kind='labor';p.components[1].unit='person-hour';p.components[1].quantityUnit='person-hour';p.components[1].quantity=.2;
 assert.throws(()=>checkWholePlan(p,undefined,[],'Install a new vanity and sink top.'),/routine vanity finishing/);
 assert.doesNotThrow(()=>checkWholePlan(p,undefined,[],'Install a new vanity and separately reseal the existing adjacent backsplash.'));
 p.components[1].name='Caulk tub surround joints';p.components[1].location='Tub surround';p.coverage[0].componentIds=['vanity'];
 assert.doesNotThrow(()=>checkWholePlan(p,undefined,[],'Install vanity and caulk tub surround.'));
 p.components=p.components.slice(1);p.components[0].name='Reseal existing vanity';p.coverage=[];
 assert.doesNotThrow(()=>checkWholePlan(p,undefined,[],'Reseal existing vanity.'));
});

const waterproofMaterialPlan=()=>{const p=plan();p.components=[{...p.components[0],id:'membrane',row:1000001,kind:'material',name:'RedGard wall waterproofing material',location:'Tub surround',quantity:1,quantityUnit:'pail',unit:'pail',basis:'assumed'}];p.coverage=[{requirement:'Purchase waterproofing material only',componentIds:['membrane'],status:'priced',reason:'Material only'}];return p;};
test('supplier procurement retains separate provenance, dated price and actual app product link',()=>{const p=waterproofMaterialPlan();const r=priceWholePlan(p,{painter:999});assert.equal(r.catalogSubtotal,77.53);assert.equal(r.lines[0].personHours,0);assert.equal(r.lines[0].businessRateApplied,false);assert.equal(r.lines[0].source.type,'supplier_material');assert.equal(r.lines[0].source.workbook,null);assert.match(r.lines[0].source.id,/supplier:homedepot/);const e=wholeAppEstimate(r);assert.equal(e.categories[0].items[0].url,r.lines[0].source.url);assert.match(e.notes,/observed 2026-10-04/);assert.match(e.categories[0].items[0].description,/Milwaukee store price.*not verified/);});
test('supplier material cannot masquerade as installation or fractional purchased packages',()=>{for(const kind of ['catalog','labor']){const p=waterproofMaterialPlan();p.components[0].kind=kind;assert.throws(()=>checkWholePlan(p),/procurement only/);}const p=waterproofMaterialPlan();p.components[0].quantity=50/55;assert.throws(()=>checkWholePlan(p),/whole-pail/);});
test('waterproof coverage enforces whole pails, not crack-prevention coverage',()=>{const p=waterproofMaterialPlan();p.components.push({...plan().components[0],id:'tile',row:1673,name:'Install wall tile',location:'Tub surround',quantity:56});assert.throws(()=>checkWholePlan(p),/at least 2 pail/);p.components[0].quantity=2;assert.equal(priceWholePlan(p).lines[0].amount,155.06);p.components[1].quantity=55;p.components[0].quantity=1;assert.doesNotThrow(()=>checkWholePlan(p));});
test('wall membrane procurement does not imply roofing or pan-liner system coverage',()=>{for(const name of ['Roof waterproofing','Shower pan liner']){const p=waterproofMaterialPlan();p.components[0].name=name;assert.throws(()=>checkWholePlan(p),/different shower-pan-liner takeoff/);}const p=waterproofMaterialPlan();p.unpriced=[{name:'Waterproofing application labor',reason:'No justified labor takeoff yet'}];assert.equal(priceWholePlan(p).status,'partial_priced_scope');assert.equal(wholeAppEstimate(priceWholePlan(p)).pricing.projectTotal,null);});

test('redundant literal or mislabelled arithmetic normalizes provenance without changing stated quantities',()=>{
 const literal=plan();literal.components[0].quantityFormula='100';reconcilePlanPolicy(literal);assert.equal(literal.components[0].quantity,100);assert.equal(literal.components[0].basis,'stated');assert.equal(literal.components[0].quantityFormula,null);
 const calculated=plan();calculated.components[0].quantityFormula='10*10';reconcilePlanPolicy(calculated);assert.equal(calculated.components[0].quantity,100);assert.equal(calculated.components[0].basis,'derived');assert.equal(calculated.components[0].quantityFormula,'10*10');
 const changed=plan();changed.components[0].quantityFormula='10*9';assert.throws(()=>reconcilePlanPolicy(changed),/changes its stated quantity/);assert.equal(changed.components[0].quantity,100);
});

test('same-location complete vanity replacement preserves material and removes duplicate operations',()=>{
 const p=plan();const base={...p.components[0],quantity:1,quantityUnit:'Ea',unit:'Ea',location:'Bathroom vanity'};
 p.components=[{...base,id:'replace',row:2822},{...base,id:'new',row:1359},{...base,id:'demo',row:2820}];
 p.coverage=[{requirement:'Remove existing vanity',componentIds:['demo'],status:'priced',reason:'Removal'},{requirement:'Install new vanity',componentIds:['replace','new'],status:'priced',reason:'Replacement'}];
 reconcilePlanPolicy(p,undefined,'Keep the existing layout and plumbing locations. Replace the vanity.');
 assert.deepEqual(p.components.map(c=>[c.id,c.kind]),[['replace','catalog'],['new','material']]);
 assert.deepEqual(p.coverage[0].componentIds,['replace']);assert.doesNotThrow(()=>checkWholePlan(p));
 assert.equal(priceWholePlan(p,{plumber:95,standard_labor:50}).lines.find(l=>l.id==='new')?.personHours,0);
 const q=plan();q.components=[{...base,id:'replace',row:2822},{...base,id:'new',row:1359,location:'Other bathroom'}];
 reconcilePlanPolicy(q,undefined,'Keep the existing plumbing locations.');assert.equal(q.components[1].kind,'catalog');
});
test('coverage tolerates articles and punctuation but preserves distinct operations',()=>{
 const p=plan();p.coverage[0].requirement='Paint the walls.';assert.doesNotThrow(()=>checkWholePlan(p,undefined,['Paint walls']));assert.equal(p.coverage[0].requirement,'Paint walls');
 assert.throws(()=>checkWholePlan(p,undefined,['Remove walls']),/Missing scope coverage/);
});

test('retained bathtub geometry excludes its footprint and the paint door opening',()=>{
 const input=bathroomInput+'. Retain the existing bathtub.';const d=residentialTakeoffDefaults(input);assert.equal(d.geometry.floorAreaSF,27.5);assert(Math.abs(d.geometry.paintAreaSF-141.33333333333334)<1e-8);
 const p=plan();p.components[0]={...p.components[0],row:1651,name:'Bathroom floor',location:'Bathroom floor',quantity:40};p.coverage[0]={requirement:'Install floor',componentIds:['paint'],status:'priced',reason:'Tile'};
 assert.throws(()=>checkWholePlan(p,undefined,[],input),/retained 12.5 SF/);p.components[0].quantity=27.5;assert.doesNotThrow(()=>checkWholePlan(p,undefined,[],input));
 assert.equal(residentialTakeoffDefaults(bathroomInput).geometry,null);
});
test('membrane procurement alone cannot cover installed waterproofing',()=>{
 const p=waterproofMaterialPlan();p.coverage=[{requirement:'Install new tub surround',componentIds:[p.components[0].id],status:'priced',reason:'Waterproofing supplied'}];assert.throws(()=>checkWholePlan(p),/material only.*application person-hours/);
 p.coverage[0].status='partial';p.unpriced=[{name:'Membrane application',reason:'Missing application takeoff'}];assert.doesNotThrow(()=>checkWholePlan(p));
});

test('additional membrane activity can use installed tile row as hourly crew source without charging tile',()=>{
 const p=plan();p.components=[{...p.components[0],id:'membrane-labor',category:'Waterproofing',name:'Apply membrane at surround',location:'Tub surround',kind:'labor',row:1673,quantity:2,quantityFormula:'2',quantityUnit:'person-hour',unit:'person-hour',basis:'assumed',rationale:'Two active person-hours to apply two membrane coats at 50 SF, additional to tile setting; drying time is not labor.'}];p.coverage=[{requirement:'Apply waterproofing membrane',componentIds:['membrane-labor'],status:'priced',reason:'Separate application labor only'}];
 const r=priceWholePlan(p);assert.equal(r.lines[0].personHours,2);assert.equal(r.lines[0].unitRate,36.97);assert.equal(r.catalogSubtotal,73.94);assert.equal(r.lines[0].source.raw[7],'SF');assert.equal(r.lines[0].catalogUnit,'person-hour');
});

// Reproduces the client's $118.31 unrequested preparation charge on sound ready drywall.
test('ready-for-normal-painting also rejects renamed wet-cleaning family',()=>{
 const p=plan();p.components.push({...p.components[0],id:'generic-prep',row:8880,name:'Prepare existing smooth drywall surface'});
 assert.throws(()=>checkWholePlan(p,undefined,[],'Existing smooth drywall is sound and ready for normal painting. Exclude repairs.'),/adds cleaning/);
 assert.doesNotThrow(()=>checkWholePlan(p,undefined,[],'Wash dirty drywall walls before painting.'));
});
test('verified disposable protection is procurement only with separate supplier provenance',()=>{
 const p=plan();p.components=[{...p.components[0],row:1000002,name:'Masking tape',kind:'material',quantity:1,quantityUnit:'roll',unit:'roll'}];
 const r=priceWholePlan(p,{painter:60});assert.equal(r.catalogSubtotal,5.8);assert.equal(r.lines[0].personHours,0);assert.equal(r.lines[0].source.type,'supplier_material');
 p.components[0]={...p.components[0],row:1000003,name:'Drop cloth',quantityUnit:'each',unit:'each'};assert.equal(priceWholePlan(p).catalogSubtotal,3.48);
});

const readyPaint='Apply two coats of flat latex with a roller to exactly 100 SF of smooth interior bedroom drywall walls. Surfaces are sound and ready for normal painting. Do not paint ceiling or trim. No repairs or debris disposal are required. Use small-volume pricing.';
const paintAllowed=new Set([9034,1000002,1000003]);
test('individually labelled measured image openings receive edge work once',async()=>{
 const {completeReadyPaintingPackage}=await import('./whole-project.ts');const p=plan();p.components[0].quantity=452;
 completeReadyPaintingPackage(p,readyPaint,paintAllowed,['Window 1: 4 ft x 4 ft.','Window 2: 4 ft x 4 ft.','Door: 36 in x 80 in.','Window 1: 4 ft x 4 ft.']);
 assert.equal(p.components.find(c=>/Cut in wall boundaries/.test(c.name)).quantity,3.76);
 assert.equal(p.components.find(c=>c.kind==='catalog').quantity,452);
});
test('incomplete repaint wording still completes the selected roller operation without removing repairs',async()=>{
 const {completeReadyPaintingPackage}=await import('./whole-project.ts');
 const sparse=plan(),explicit=plan();
 sparse.unpriced=[{name:'Repair damaged drywall',reason:'Damage extent is unspecified'}];
 completeReadyPaintingPackage(sparse,'Repaint bedroom walls.',paintAllowed);
 completeReadyPaintingPackage(explicit,readyPaint,paintAllowed);
 assert.equal(priceWholePlan(sparse,{painter:60}).catalogSubtotal,priceWholePlan(explicit,{painter:60}).catalogSubtotal);
 assert.deepEqual(sparse.unpriced,[{name:'Repair damaged drywall',reason:'Damage extent is unspecified'}]);
 const before=priceWholePlan(sparse,{painter:60}).catalogSubtotal;
 completeReadyPaintingPackage(sparse,'Repaint bedroom walls.',paintAllowed);
 assert.equal(priceWholePlan(sparse,{painter:60}).catalogSubtotal,before);
});
test('ready painting template purchases whole gallons, adds actual job activities once and preserves unsupported scope',async()=>{
 const {completeReadyPaintingPackage}=await import('./whole-project.ts');const p=plan();p.unpriced=[{name:'Painter labor for edge cutting, setup, and cleanup',reason:'No geometry'},{name:'Masking/protection supplies',reason:'No geometry'},{name:'Customer requested mural',reason:'No suitable supplied catalog row'}];
 completeReadyPaintingPackage(p,readyPaint,paintAllowed);checkWholePlan(p,paintAllowed,[],readyPaint);
 assert.equal(p.components.filter(c=>c.kind==='labor').reduce((s,c)=>s+c.quantity,0),3);
 assert.equal(p.components.filter(c=>c.row===9034&&c.kind==='material').reduce((s,c)=>s+c.quantity,0),60);
 assert.equal(p.components.find(c=>c.row===1000003).quantity,1);
 assert.deepEqual(p.unpriced,[{name:'Customer requested mural',reason:'No suitable supplied catalog row'}]);
 const before=priceWholePlan(p,{painter:60}).catalogSubtotal;completeReadyPaintingPackage(p,readyPaint,paintAllowed);assert.equal(priceWholePlan(p,{painter:60}).catalogSubtotal,before);checkWholePlan(p,paintAllowed,[],readyPaint);
});
test('painting template preserves owner-supplied protection and cleanup exclusions',async()=>{
 const {completeReadyPaintingPackage}=await import('./whole-project.ts');const p=plan();p.coverage.push({requirement:'Exclude painting cleanup',componentIds:[],status:'excluded',reason:'Owner handles cleanup'});
 completeReadyPaintingPackage(p,readyPaint+' Owner supplies masking and protection. Owner handles cleanup.',paintAllowed);
 assert(!p.components.some(c=>c.row===1000002||c.row===1000003));assert(!p.components.some(c=>/Clean and pack/.test(c.name)));assert.equal(p.coverage.at(-1).status,'excluded');checkWholePlan(p,paintAllowed);
});
test('painting template does not invent extra work for multiple painting packages',async()=>{
 const {completeReadyPaintingPackage}=await import('./whole-project.ts');const p=plan();p.components.push({...p.components[0],id:'second',location:'Second bedroom'});const before=structuredClone(p);completeReadyPaintingPackage(p,readyPaint,paintAllowed);assert.deepEqual(p,before);
});
test('stated door and window counts add edge work without painting excluded trim',async()=>{
 const {completeReadyPaintingPackage}=await import('./whole-project.ts');const p=plan();p.components[0].quantity=311+1/3;
 const customer='Repaint the walls of a 10 ft x 12 ft bedroom with an 8 ft ceiling. There is one 30-inch x 80-inch door and two 3 ft x 4 ft windows. Apply two coats of flat latex with a roller. Existing smooth drywall is sound and ready for painting. Exclude ceiling, trim, repairs and disposal. Use small-volume pricing.';
 completeReadyPaintingPackage(p,customer,paintAllowed);
 const edge=p.components.find(c=>/^Cut in/.test(c.name));assert(Math.abs(edge.quantity-6.453333333333333)<1e-10);assert.match(edge.rationale,/161\.33 LF/);assert(!p.components.some(c=>/Paint trim/.test(c.name)));assert.equal(p.components.find(c=>c.row===1000003).quantity,2);checkWholePlan(p,paintAllowed,[],customer);
});

test('measured cut-in takeoff follows edge lengths and coats, not net wall area alone',async()=>{
 const {measuredPaintingEdges}=await import('./whole-project.ts');
 const facts=['Wall height: 9 ft.','Window 1: 4 ft x 5 ft.','Door: 36 in x 84 in.'];
 const one=measuredPaintingEdges('Repaint walls shown in the measured plan.',facts,535,1);
 // Perimeter 64 ft; top/base 125 ft after door gap, corners 36 ft,
 // window 18 ft and door sides/top 17 ft = 196 ft per coat.
 assert(Math.abs(one.edges-196)<1e-10);assert(Math.abs(one.hours-3.92)<1e-10);
 const two=measuredPaintingEdges('Repaint walls shown in the measured plan.',facts,535,2);
 assert.equal(two.hours,one.hours*2);
 assert.equal(measuredPaintingEdges('Paint exactly 100 SF of bedroom walls.',facts,100,2),null);
 assert.equal(measuredPaintingEdges('Repaint bathroom walls around the retained tiled surround.',facts,100,2),null);
});
test('natural-language image labels preserve the same measured takeoff as colon labels',async()=>{
 const {measuredPaintingEdges}=await import('./whole-project.ts');
 const prompt='Repaint only the bedroom walls shown in the attached measured plan.';
 const colon=['Room dimensions: 15 ft by 13 ft.','Wall height: 9 ft.','Window 1: 4 ft x 4 ft.','Window 2: 4 ft x 4 ft.','Door: 36 in x 80 in.'];
 const natural=['Room dimensions shown are 15 ft by 13 ft.','Wall height shown is 9 ft.','Window 1 is labeled 4 ft x 4 ft.','Window 2 is labelled 4 ft x 4 ft.','Door is labeled 36 in x 80 in.'];
 assert.deepEqual(measuredPaintingEdges(prompt,natural,452,2),measuredPaintingEdges(prompt,colon,452,2));
 assert(measuredPaintingEdges(prompt,natural,452,2).hours>0);
});

test('single painting package replaces overlapping painter labor despite location aliases',async()=>{
 const {completeReadyPaintingPackage}=await import('./whole-project.ts');const p=plan();
 p.components.push({...p.components[0],id:'overlap',kind:'labor',location:'Bedroom',name:'Painter labor for masking, edge cutting, and cleanup',quantity:1.5,quantityUnit:'person-hour',unit:'person-hour'});
 p.components.push({...p.components[0],id:'other-trade',row:1637,kind:'labor',location:'Bedroom',name:'Other trade cleanup',quantity:1,quantityUnit:'person-hour',unit:'person-hour'});
 completeReadyPaintingPackage(p,readyPaint,paintAllowed);
 assert(!p.components.some(c=>c.id==='overlap'));assert(p.components.some(c=>c.id==='other-trade'));
 assert.equal(p.components.filter(c=>c.kind==='labor'&&c.row===9034).reduce((s,c)=>s+c.quantity,0),3);
});

const standardToiletPrompt='Remove one existing toilet and install one standard two-piece floor-mounted toilet, including seat and supply, at the same plumbing location. Use small-volume pricing. Owner handles debris disposal. No plumbing relocation, floor repair or other fixtures.';
const toiletPlan=()=>{const p=plan();p.components=[{...p.components[0],id:'remove',name:'Remove existing toilet',row:11366,quantity:1,quantityUnit:'Ea',unit:'Ea'},{...p.components[0],id:'install',name:'Install standard toilet',row:11386,quantity:1,quantityUnit:'Ea',unit:'Ea'}];p.coverage=[{requirement:'Remove and replace toilet',componentIds:['remove','install'],status:'priced',reason:'Replacement'}];return p;};
test('approved toilet refresh replaces installed catalog charges once and preserves complete coverage',async()=>{
 const {refreshStandardToiletPackage}=await import('./whole-project.ts');const p=toiletPlan(),allowed=new Set([11366,11386,1000004,1000005,1000006]);
 refreshStandardToiletPackage(p,standardToiletPrompt,allowed);assert.equal(p.components.length,4);assert.equal(p.components.filter(c=>c.kind==='labor').reduce((n,c)=>n+c.quantity,0),3);assert(!p.components.some(c=>c.kind==='catalog'));checkWholePlan(p,allowed,[],standardToiletPrompt);
 const r=priceWholePlan(p,{plumber:95});assert.equal(r.catalogSubtotal,393.28);assert.equal(r.lines.filter(l=>l.source.type==='supplier_material').length,3);
 const before=structuredClone(p);refreshStandardToiletPackage(p,standardToiletPrompt,allowed);assert.deepEqual(p,before);
});
test('toilet refresh does not override premium fixtures, owner procurement or multiple toilets',async()=>{
 const {refreshStandardToiletPackage}=await import('./whole-project.ts');for(const extra of [' Premium Kohler toilet.',' Owner supplies the toilet.',' Elongated bowl required.']){const p=toiletPlan(),before=structuredClone(p);refreshStandardToiletPackage(p,standardToiletPrompt+extra,new Set([11366,11386,1000004,1000005,1000006]));assert.deepEqual(p,before);}
 const p=toiletPlan();p.components[1].quantity=2;const before=structuredClone(p);refreshStandardToiletPackage(p,standardToiletPrompt,new Set([11366,11386,1000004,1000005,1000006]));assert.deepEqual(p,before);
});

const standardVanityPrompt='Disconnect and remove one existing vanity and sink top, and install one new 31-inch by 19-inch two-door composition vanity and sink top. Keep plumbing locations. Owner handles disposal. No other fixtures.';
const vanityPlan=()=>{const p=plan();p.components=[{...p.components[0],id:'replace',name:'Vanity replacement',row:2822,quantity:1,quantityUnit:'Ea',unit:'Ea'},{...p.components[0],id:'material',name:'New vanity and top',kind:'material',row:1359,quantity:1,quantityUnit:'Ea',unit:'Ea'}];p.coverage=[{requirement:'Replace vanity and top',componentIds:['replace','material'],status:'priced',reason:'Complete replacement'}];return p;};
const vanityAllowed=new Set([2822,1359,1000006,1000007,1000008,1000009]);
test('sourced vanity refresh preserves catalog person-hours, complete coverage and single purchases',async()=>{
 const {refreshStandardVanityProcurement}=await import('./whole-project.ts');const p=vanityPlan();refreshStandardVanityProcurement(p,standardVanityPrompt,vanityAllowed);checkWholePlan(p,vanityAllowed,[],standardVanityPrompt);
 const report=priceWholePlan(p,{plumber:95,standard_labor:50});assert.equal(report.catalogSubtotal,670.93);assert.equal(report.lines.find(l=>l.source.row===2822).personHours,3.52);
 assert.equal(p.components.filter(c=>c.kind==='catalog').length,1);assert.equal(p.components.filter(c=>c.row===1000006).length,1);assert(!p.components.some(c=>/new faucet/i.test(c.name)));assert(p.coverage[0].componentIds.length===5);
 const before=structuredClone(p);refreshStandardVanityProcurement(p,standardVanityPrompt,vanityAllowed);assert.deepEqual(p,before);
});
test('vanity refresh respects owner procurement and does not substitute other sizes or duplicate shared sealant',async()=>{
 const {refreshStandardVanityProcurement}=await import('./whole-project.ts');const p=vanityPlan(),before=structuredClone(p);refreshStandardVanityProcurement(p,standardVanityPrompt+' Owner supplies the vanity.',vanityAllowed);assert.deepEqual(p,before);
 p.components[1].row=1351;const different=structuredClone(p);refreshStandardVanityProcurement(p,standardVanityPrompt,vanityAllowed);assert.deepEqual(p,different);
 const shared=vanityPlan();shared.components.push({...shared.components[1],id:'shared-sealant',row:1000006,unit:'tube',quantityUnit:'tube'});refreshStandardVanityProcurement(shared,standardVanityPrompt,vanityAllowed);assert.equal(shared.components.filter(c=>c.row===1000006).length,1);
});

test('ready bathroom wall painting completes protection alongside fixtures without duplicating other trades',async()=>{
 const {completeReadyPaintingPackage}=await import('./whole-project.ts');const p=plan();p.components[0].location='Bathroom walls';p.components.push({...p.components[0],id:'vanity-replace',name:'Vanity replacement',row:2822,quantity:1,quantityUnit:'Ea',unit:'Ea'},{...p.components[0],id:'vanity-material',name:'Vanity and top',row:1359,kind:'material',quantity:1,quantityUnit:'Ea',unit:'Ea'});
 p.unpriced=[{name:'Painting protection consumables',reason:'No stated edge length'}];p.coverage[0].status='partial';const originals=structuredClone(p.components.slice(1));
 const customer='In one bathroom, replace vanity and apply two coats of flat latex with a roller to exactly 100 SF of smooth drywall walls; surfaces are sound and ready for normal painting.';
 completeReadyPaintingPackage(p,customer,new Set([9034,2822,1359,1000002,1000003]));assert.equal(p.unpriced.length,0);assert.equal(p.coverage[0].status,'priced');assert.deepEqual(p.components.filter(c=>c.id.startsWith('vanity-')),originals);assert.equal(p.components.filter(c=>c.row===1000002).length,1);assert.equal(p.components.filter(c=>c.row===1000003).length,1);assert.equal(p.components.filter(c=>c.kind==='labor').reduce((n,c)=>n+c.quantity,0),3);
});

test('material purchase tied to install area is not itself an installation requirement',()=>{
 const p=plan();p.components=[{...p.components[0],id:'floor',row:9520,name:'Laminate flooring approximation',quantity:120},{...p.components[0],id:'waste',row:9520,name:'Additional laminate flooring material',kind:'material',quantity:12}];
 p.coverage=[{requirement:'Install 120 SF of laminate-approximate resilient plank flooring.',componentIds:['floor'],status:'priced',reason:'Installed assembly.'},{requirement:'Purchase 10% extra flooring material for waste, sized to the 120 SF install area.',componentIds:['waste'],status:'priced',reason:'Material only.'}];
 assert.doesNotThrow(()=>checkWholePlan(p,new Set([9520]),[],'Install standard laminate flooring.'));
 p.coverage[0].componentIds=['waste'];assert.throws(()=>checkWholePlan(p,new Set([9520])),/compatible floor installation/);
 p.coverage[0].requirement='Purchase and install laminate flooring';assert.throws(()=>checkWholePlan(p,new Set([9520])),/compatible floor installation/);
});

test('interior baseboard paint has shared job activities, material-only whole purchases and no duplicate caulking',async()=>{
 const {completeReadyPaintingPackage}=await import('./whole-project.ts');
 const p=plan();p.components=[{...p.components[0],id:'trim',name:'Supply and install baseboard',row:8426,quantity:30,quantityUnit:'LF',unit:'LF'},{...p.components[0],id:'caulk',name:'Caulk baseboard',row:1527,quantity:30,quantityUnit:'LF',unit:'LF'},{...p.components[0],id:'paint',name:'Paint baseboard two coats',row:9052,quantity:8.125,quantityUnit:'SF',unit:'SF'}];
 p.coverage=[{requirement:'Supply, install, caulk and paint baseboard.',componentIds:['trim','caulk','paint'],status:'priced',reason:'Assemblies'}];
 const input='Supply and install 30 LF of paint-grade wood baseboard in one bedroom. Include caulking and two coats of white paint.';
 const allowed=new Set([8426,1527,9052,1000002,1000003]);const original=structuredClone(p.components.slice(0,2));
 completeReadyPaintingPackage(p,input,allowed);checkWholePlan(p,allowed,[],input);
 assert.deepEqual(p.components.slice(0,2),original);
 assert.equal(p.components.filter(c=>c.kind==='labor').reduce((n,c)=>n+c.quantity,0),2);
 assert(!p.components.some(c=>c.kind==='labor'&&/cut in/i.test(c.name)));
 assert.equal(p.components.filter(c=>c.row===9052&&c.kind==='catalog').length,1);
 assert.equal(p.components.filter(c=>c.row===9052&&c.kind==='material').reduce((n,c)=>n+c.quantity,0),510-8.125);
 const before=priceWholePlan(p,{painter:60,carpenter_framing:90}).catalogSubtotal;
 completeReadyPaintingPackage(p,input,allowed);assert.equal(priceWholePlan(p,{painter:60,carpenter_framing:90}).catalogSubtotal,before);
});

test('new painted baseboard includes compatible catalog wood-trim preparation once',async()=>{
 const {completeReadyPaintingPackage}=await import('./whole-project.ts');const p=plan();
 p.components=[{...p.components[0],id:'base',row:8426,quantity:60,quantityUnit:'LF',unit:'LF'},{...p.components[0],id:'paint',row:9052,quantity:16.25,quantityUnit:'SF',unit:'SF'}];
 p.coverage=[{requirement:'Install and paint new baseboard',componentIds:['base','paint'],status:'priced',reason:'Catalog'}];
 const input='Install new paint-grade baseboard in one bedroom and apply two coats of white paint.';const allowed=new Set([8426,9052,9072,1000002,1000003]);
 completeReadyPaintingPackage(p,input,allowed);assert.equal(p.components.filter(c=>c.row===9072).length,1);assert.equal(p.components.find(c=>c.row===9072).quantity,16.25);assert.match(p.components.find(c=>c.row===9072).rationale,/proxy/);
 completeReadyPaintingPackage(p,input,allowed);assert.equal(p.components.filter(c=>c.row===9072).length,1);checkWholePlan(p,allowed,[],input);
 const excluded=plan();excluded.components=structuredClone(p.components.filter(c=>c.row===8426||c.row===9052));excluded.coverage=p.coverage.map(c=>({...c,componentIds:['base','paint']}));completeReadyPaintingPackage(excluded,input+' Owner handles filling and sanding.',allowed);assert(!excluded.components.some(c=>c.row===9072));
});

test('single-room painting completion scales above 400 SF and uses measured-image geometry',async()=>{
 const {completeReadyPaintingPackage}=await import('./whole-project.ts');const p=plan();p.components[0].quantity=500;
 const input='Repaint bedroom walls shown in the measured image. Apply two coats with a roller; smooth drywall is sound and ready for painting. Exclude ceiling, trim and repairs.';
 completeReadyPaintingPackage(p,input,paintAllowed,['Room measures 17 ft by 19 ft.','There is one door and two windows.']);
 assert.equal(p.components.filter(c=>c.kind==='labor').reduce((n,c)=>n+c.quantity,0),6);
 assert.equal(p.components.find(c=>c.row===1000003).quantity,3);
 assert.equal(p.components[0].quantity,500);assert.equal(p.components.filter(c=>c.row===9034&&c.kind==='material').reduce((n,c)=>n+c.quantity,0),140);
 checkWholePlan(p,paintAllowed);
 const explicit=plan();completeReadyPaintingPackage(explicit,readyPaint+' Room measures 10 ft x 12 ft. One door.',paintAllowed,['Room measures 17 ft by 19 ft.','There are four windows.']);assert.equal(explicit.components.find(c=>c.row===1000003).quantity,2);assert.equal(explicit.components.filter(c=>c.kind==='labor').reduce((n,c)=>n+c.quantity,0),3.5);
});

test('ceramic bullnose replaces field material while preserving installed area labor once',()=>{
 const p=plan();const base={...p.components[0],category:'Tile',location:'Kitchen backsplash',row:1665,name:'Ceramic backsplash field tile'};
 p.components=[{...base,quantity:29.25},{...base,id:'trim-setting',name:'Set ceramic bullnose within installed tile area',kind:'labor',quantity:0.75*0.242,quantityUnit:'person-hour',unit:'person-hour'},{...base,id:'bullnose',name:'Ceramic bullnose procurement',kind:'material',row:1000010,quantity:6,quantityUnit:'piece',unit:'piece'}];
 p.coverage=[{requirement:'Install ceramic backsplash and edge finishing',componentIds:p.components.map(c=>c.id),status:'priced',reason:'Bullnose replaces field tile at exposed ends'}];
 const r=priceWholePlan(p);assert.equal(r.catalogSubtotal,547.71);assert.equal(Math.round(r.lines.reduce((s,l)=>s+l.personHours,0)*100),726);
 assert.equal(r.lines.at(-1).source.type,'supplier_material');assert.equal(r.lines.at(-1).personHours,0);
 assert.ok(families().some(f=>f.rows.includes(1000010)));p.components.at(-1).kind='catalog';assert.throws(()=>checkWholePlan(p),/procurement only/);
});

test('supplier retry guidance uses each source unit, never pail for tape or bullnose',()=>{
 for(const [row,unit] of [[1000001,'pail'],[1000002,'roll'],[1000003,'each'],[1000010,'piece']]){
  const p=plan();p.components=[{...p.components[0],row,kind:'catalog',quantity:1,quantityUnit:unit,unit}];
  assert.throws(()=>checkWholePlan(p),e=>e.message.includes(`quantityUnit=${unit} and unit=${unit}`)&&e.message.includes(`row ${row}`)&&!e.message.includes(unit==='pail'?'whole-roll':'whole-pail'));
 }
});

test('complete ceramic edge cap conserves backsplash area and cannot repeat supplier bullnose',()=>{
 const p=plan();const base={...p.components[0],category:'Tile',location:'Kitchen backsplash',row:1623,name:'Ceramic backsplash field tile',quantity:29.5};
 p.components=[base,{...base,id:'edge',name:'Ceramic bullnose edge using complete cap proxy',row:1653,quantity:3,quantityUnit:'LF',unit:'LF'}];
 p.coverage=[{requirement:'Install ceramic backsplash with edge finishing',componentIds:p.components.map(c=>c.id),status:'priced',reason:'Compatible ceramic edge assembly replaces field face area'}];
 const customer='Supply and install 30 SF of ceramic kitchen backsplash with edge finishing.';
 assert.doesNotThrow(()=>checkWholePlan(p,undefined,[],customer));
 p.components[0].quantity=30;assert.throws(()=>checkWholePlan(p,undefined,[],customer),/conserve/);
 p.components[0].quantity=29.5;p.components.push({...base,id:'duplicate-bullnose',row:1000010,kind:'material',quantity:6,quantityUnit:'piece',unit:'piece'});
 assert.throws(()=>checkWholePlan(p,undefined,[],customer),/also procure/);
});
test('tile sealer and flexible joint supplies retain sourced package units and zero labor',()=>{
 for(const [row,unit,price] of [[1000011,'bottle',9.97],[1000012,'tube',18.41]]){
  const p=plan();p.components=[{...p.components[0],row,kind:'material',quantity:1,quantityUnit:unit,unit}];
  const result=priceWholePlan(p);assert.equal(result.catalogSubtotal,price);assert.equal(result.lines[0].personHours,0);
  p.components[0].quantity=0.5;assert.throws(()=>checkWholePlan(p),/whole/);
 }
});


test('surround cap replaces field face while backing keeps the full standard surface',()=>{
 const p=plan();const base={...p.components[0],location:'Tub surround',name:'Install ceramic tub surround',row:1673,quantity:48};
 p.components=[base,{...base,id:'cap',name:'Ceramic surround edge cap',row:1657,quantity:12,quantityUnit:'LF',unit:'LF'},{...base,id:'backer',name:'Surround cement backer',row:1677,quantity:50}];
 assert.doesNotThrow(()=>checkWholePlan(p,undefined,[],bathroomInput));
 p.components[0].quantity=50;assert.throws(()=>checkWholePlan(p,undefined,[],bathroomInput),/field tile plus ceramic cap/);
 p.components[0].quantity=48;p.components.at(-1).quantity=48;assert.throws(()=>checkWholePlan(p,undefined,[],bathroomInput),/demolition and backing/);
});


test('waterproof procurement includes installed cap face across whole-pail boundary',()=>{
 const p=waterproofMaterialPlan();const base={...plan().components[0],location:'Tub surround',name:'Surround ceramic field',row:1673,quantity:54};
 p.components.push(base,{...base,id:'cap',row:1657,name:'Ceramic edge cap',quantity:12,quantityUnit:'LF',unit:'LF'});
 assert.throws(()=>checkWholePlan(p),/at least 2 pail/);p.components[0].quantity=2;assert.doesNotThrow(()=>checkWholePlan(p));
});
test('round supplier kit cannot be labeled elongated and whole fixture stops remain material only',()=>{
 const p=plan();p.components=[{...p.components[0],name:'Elongated toilet kit',kind:'material',row:1000004,quantity:1,quantityUnit:'each',unit:'each'}];assert.throws(()=>checkWholePlan(p),/round.*elongated/);
 p.components[0].row=1000013;assert.doesNotThrow(()=>checkWholePlan(p));assert.equal(priceWholePlan(p).catalogSubtotal,189);
 p.components=[{...p.components[0],name:'Three new fixture stops',row:1000014,quantity:3}];assert.equal(priceWholePlan(p).catalogSubtotal,29.19);p.components[0].kind='catalog';assert.throws(()=>checkWholePlan(p),/procurement only/);
});

test('missing backsplash layout produces the same takeoff and price across inferred shapes',()=>{
 const make=(edge)=>{const p=plan();p.components=[{...p.components[0],id:'field',row:2370,name:'Kitchen backsplash',location:'Kitchen backsplash',quantity:30-edge*2/12,quantityFormula:`30 - ${edge} * 2 / 12`,basis:'derived'},{...p.components[0],id:'cap',row:1653,name:'Backsplash cap',location:'Kitchen backsplash',quantity:edge,quantityFormula:String(edge),quantityUnit:'LF',unit:'LF',basis:'derived'}];p.coverage=[{requirement:'Install kitchen backsplash',componentIds:['field','cap'],status:'priced',reason:'Complete finish'}];return p;};
 const customer='Install 30 SF standard ceramic kitchen backsplash.';
 const a=reconcilePlanPolicy(make(3),undefined,customer),b=reconcilePlanPolicy(make(6),undefined,customer);
 assert.deepEqual(a.components,b.components);assert.equal(priceWholePlan(a).catalogSubtotal,priceWholePlan(b).catalogSubtotal);
 assert.equal(a.components[0].quantity+a.components[1].quantity*2/12,30);
 const measured=reconcilePlanPolicy(make(6),undefined,customer+' Height is 3 feet.');assert.equal(measured.components[1].quantity,6);
 const photo=reconcilePlanPolicy(make(6),undefined,customer,true);assert.equal(photo.components[1].quantity,6);
 assert.deepEqual(reconcilePlanPolicy(a,undefined,customer).components,b.components);
});


test('source-defined supplier packages normalize billing without guessing area or person-hours',()=>{
 const p=plan();p.components=[{...p.components[0],row:1000011,kind:'catalog',quantity:.5,quantityUnit:'bottle',unit:'bottle'}];
 reconcilePlanPolicy(p);assert.equal(p.components[0].kind,'material');assert.equal(p.components[0].quantity,1);assert.equal(priceWholePlan(p).catalogSubtotal,9.97);assert.equal(priceWholePlan(p).lines[0].personHours,0);
 const copy=structuredClone(p);reconcilePlanPolicy(p);assert.deepEqual(p,copy);
 p.components[0].quantityUnit='SF';assert.throws(()=>checkWholePlan(reconcilePlanPolicy(p)),/procurement only/);
 p.components[0].quantityUnit='person-hour';p.components[0].unit='person-hour';p.components[0].kind='labor';assert.throws(()=>checkWholePlan(reconcilePlanPolicy(p)),/procurement only/);
});
test('included ceramic cap removes duplicate procurement and retains coverage links',()=>{
 const p=plan();const b={...p.components[0],location:'Kitchen backsplash',category:'Tile'};
 p.components=[{...b,id:'cap',row:1653,quantity:3,quantityUnit:'LF',unit:'LF'},{...b,id:'supply',row:1000010,kind:'material',quantity:6,quantityUnit:'piece',unit:'piece'}];
 p.coverage=[{requirement:'Edge finishing',componentIds:['supply'],status:'priced',reason:'Edge material'}];
 reconcilePlanPolicy(p);assert.deepEqual(p.components.map(c=>c.id),['cap']);assert.deepEqual(p.coverage[0].componentIds,['cap']);assert.doesNotThrow(()=>checkWholePlan(p));
});

test('catalog IDs validate as bounded integers rather than arbitrary numbers',async()=>{const {validate}=await import('./residential-estimator.ts');const s={type:'integer',minimum:0,maximum:families().length-1};assert.doesNotThrow(()=>validate(0,s));assert.doesNotThrow(()=>validate(families().length-1,s));for(const n of [-1,.5,families().length])assert.throws(()=>validate(n,s));});


test('single residential backsplash retains small-job pricing and included standard grout',()=>{
 const p=plan();p.components=[{...p.components[0],row:2369,location:'Kitchen backsplash',quantity:30}];
 p.unpriced=[{name:'Standard cementitious grout material',reason:'No separate source'},{name:'Unsupported repair',reason:'No source'}];
 p.coverage=[{requirement:'Supply and install ceramic tile backsplash',componentIds:['paint'],status:'priced',reason:'Assembly'},{requirement:'Standard cementitious grout',componentIds:[],status:'partial',reason:'No separate grout row'}];
 const customer='Supply and install 30 SF ceramic kitchen backsplash with standard cementitious grout.';
 reconcilePlanPolicy(p,undefined,customer);assert.equal(p.components[0].row,2370);assert.equal(p.coverage[1].status,'priced');assert(p.coverage[1].componentIds.includes('paint'));assert.equal(p.unpriced.length,1);assert.equal(p.unpriced[0].name,'Unsupported repair');
 const waste=p.components.find(c=>c.id==='backsplash-cutting-waste');assert.equal(waste.kind,'material');assert.equal(waste.quantity,3);assert.equal(priceWholePlan(p).lines.find(l=>l.id===waste.id).personHours,0);
 const once=structuredClone(p);reconcilePlanPolicy(p,undefined,customer);assert.deepEqual(p,once);
 const explicit=plan();explicit.components=[{...explicit.components[0],row:2369,quantity:30}];reconcilePlanPolicy(explicit,undefined,customer+' Use large-volume pricing.');assert.equal(explicit.components[0].row,2369);assert.equal(explicit.components.length,1);
});


test('backsplash reconciliation retains explicit sealing labor and respects owner exclusions',()=>{
 const make=()=>{const p=plan();p.components=[{...p.components[0],row:2370,location:'Kitchen backsplash',quantity:30},{...p.components[0],id:'sealer',row:1000011,kind:'material',quantity:1,quantityUnit:'bottle',unit:'bottle'}];p.coverage=[{requirement:'Seal grout joints',componentIds:['sealer'],status:'priced',reason:'Sealer'},{requirement:'Ceramic subway installation',componentIds:['paint'],status:'partial',reason:'Dimensional proxy: no exact subway row'}];return p;};
 const customer='Supply and install 30 SF ceramic kitchen backsplash. Seal grout joints.';
 const p=make();p.unpriced=[{name:'Install ceramic subway tile',reason:'Dimensional proxy: no exact subway row'}];reconcilePlanPolicy(p,undefined,customer);assert.equal(p.unpriced.length,0);assert.equal(p.coverage[1].status,'priced');assert.equal(p.components.find(c=>c.kind==='labor').quantity,.5);const once=structuredClone(p);reconcilePlanPolicy(p,undefined,customer);assert.deepEqual(p,once);
 const explicit=make();explicit.components.push({...explicit.components[0],id:'explicit-seal',kind:'labor',name:'Seal grout joints',quantity:1.25,quantityUnit:'person-hour',unit:'person-hour',basis:'provided'});reconcilePlanPolicy(explicit,undefined,customer);assert.equal(explicit.components.find(c=>c.kind==='labor').quantity,1.25);
 const excluded=make();reconcilePlanPolicy(excluded,undefined,customer+' Owner performs grout sealing.');assert.equal(excluded.components.filter(c=>c.kind==='labor').length,0);
});


test('supplier package aliases and missing quantityUnit normalize without AI repair',()=>{
 for(const row of [1000007,1000014])for(const unit of ['EA','Each','units','each']){const p=plan();p.components=[{...p.components[0],row,kind:'catalog',quantity:row===1000007?1:3,unit,quantityUnit:undefined}];reconcilePlanPolicy(p);assert.equal(p.components[0].kind,'material');assert.equal(p.components[0].unit,'each');assert.equal(p.components[0].quantityUnit,'each');assert.doesNotThrow(()=>checkWholePlan(p));assert.equal(priceWholePlan(p).lines[0].personHours,0);const copy=structuredClone(p);reconcilePlanPolicy(p);assert.deepEqual(p,copy);}
 const p=plan();p.components=[{...p.components[0],row:1000014,kind:'material',quantity:1.2,basis:'derived',quantityFormula:'3/2.5',unit:'EA',quantityUnit:'each'}];reconcilePlanPolicy(p);assert.equal(p.components[0].quantity,2);assert.equal(p.components[0].basis,'assumed');assert.doesNotThrow(()=>checkWholePlan(reconcilePlanPolicy(p)));
 for(const kind of ['catalog','labor']){const p=plan();p.components=[{...p.components[0],row:1000007,kind,quantity:1,unit:kind==='labor'?'person-hour':'SF',quantityUnit:kind==='labor'?'person-hour':'SF'}];assert.throws(()=>checkWholePlan(reconcilePlanPolicy(p)),/procurement only/);}
});


test('required coverage schema preserves exact discovery requirements',async()=>{const {wholeSchemaForRequirements}=await import('./whole-project.ts');const {validate}=await import('./residential-estimator.ts');const p=plan();const requirements=['Install new ceramic bathroom floor.'];p.coverage=[{requirement:requirements[0],componentIds:['paint'],status:'priced',reason:'Covered'}];const schema=wholeSchemaForRequirements(requirements);assert.doesNotThrow(()=>validate(p,schema));p.coverage[0].requirement='Install tile';assert.throws(()=>validate(p,schema));p.coverage=[];assert.throws(()=>validate(p,schema));});
test('missing membrane application returns an explicit unpriced gap after reconciliation',()=>{const p=waterproofMaterialPlan();p.coverage=[{requirement:'Install new tub shower surround',componentIds:['membrane'],status:'priced',reason:'Material'}];reconcilePlanPolicy(p);assert.equal(p.coverage[0].status,'partial');assert(p.unpriced.some(g=>/application labor/.test(g.name)));assert.doesNotThrow(()=>checkWholePlan(p));assert.equal(priceWholePlan(p).status,'partial_priced_scope');});
test('ordinary supplier sealer does not masquerade as waterproofing membrane',()=>{const p=plan();p.components=[{...p.components[0],row:1000011,kind:'material',unit:'bottle',quantityUnit:'bottle',quantity:1}];p.coverage=[{requirement:'Install new shower surround finish and seal grout',componentIds:['paint'],status:'priced',reason:'Grout finish only'}];assert.doesNotThrow(()=>checkWholePlan(p));});
