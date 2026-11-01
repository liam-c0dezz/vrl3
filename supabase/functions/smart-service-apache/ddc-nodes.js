// SPDX-License-Identifier: Apache-2.0
// Copyright DataDrivenConstruction. See third_party/ddc-openconstructionestimate.
// Modified: wrap original code nodes in ordinary JavaScript functions for Deno.
// The node bodies below are unchanged; no n8n runtime dependency.

const nodes = {};

nodes["Prep Text LLM"] = function($input, $, $getWorkflowStaticData, console) {
// ═══════════════════════════════════════════════════════════════════════════
// DDC CWICR - Prep Text LLM Request (for AI Node)
// Prepare prompt for text-to-works analysis
// ═══════════════════════════════════════════════════════════════════════════

const cfg = $('Config').first().json;
const tokenConfig = $('🔑 TOKEN').first().json;
const cid = String(cfg.chatId);
const sd = $getWorkflowStaticData('global');
const session = sd.sess?.[cid] || {};
const L = cfg.L || {};

const textInput = cfg.text || session.textInput || cfg.textInput || cfg.description || '';
const searchLang = L.search_lang || 'English';

console.log('=== PREP TEXT LLM ===');
console.log('Input:', textInput);
console.log('Language:', searchLang);

if (!textInput || textInput.length < 3) {
  return { json: { ...cfg, chatId: cid, _skip_llm: true, works: [], description: 'No input' }};
}

// Language-specific examples
const LANG_EXAMPLES = {
  'German': {
    input: 'Renovierung Badezimmer 8qm',
    output: '[{"name": "Fliesendemontage Wand Boden", "qty": 24, "unit": "m²"}, {"name": "Wandfliesen Feinsteinzeug 30x60", "qty": 16, "unit": "m²"}, {"name": "Bodenfliesen rutschfest", "qty": 8, "unit": "m²"}, {"name": "WC wandhängend montieren", "qty": 1, "unit": "pcs"}, {"name": "Waschtisch montieren", "qty": 1, "unit": "pcs"}]'
  },
  'English': {
    input: 'Bathroom renovation 8sqm',
    output: '[{"name": "Tile removal walls floor", "qty": 24, "unit": "m²"}, {"name": "Wall tiles porcelain 30x60", "qty": 16, "unit": "m²"}, {"name": "Floor tiles anti-slip", "qty": 8, "unit": "m²"}, {"name": "Wall-hung toilet install", "qty": 1, "unit": "pcs"}, {"name": "Vanity basin install", "qty": 1, "unit": "pcs"}]'
  },
  'Russian': {
    input: 'ремонт кухни 20м2 стены и ламинат',
    output: '[{"name": "Демонтаж старых обоев", "qty": 50, "unit": "m²"}, {"name": "Штукатурка стен гипсовая", "qty": 50, "unit": "m²"}, {"name": "Шпаклёвка стен финишная", "qty": 50, "unit": "m²"}, {"name": "Окраска стен водоэмульсионная", "qty": 50, "unit": "m²"}, {"name": "Демонтаж напольного покрытия", "qty": 20, "unit": "m²"}, {"name": "Укладка ламината с подложкой", "qty": 20, "unit": "m²"}, {"name": "Монтаж плинтуса", "qty": 18, "unit": "m"}]'
  },
  'Spanish': {
    input: 'reforma cocina 20m2 paredes y suelo',
    output: '[{"name": "Retirada papel pintado", "qty": 50, "unit": "m²"}, {"name": "Enlucido paredes", "qty": 50, "unit": "m²"}, {"name": "Pintura paredes", "qty": 50, "unit": "m²"}, {"name": "Demolición suelo", "qty": 20, "unit": "m²"}, {"name": "Tarima flotante", "qty": 20, "unit": "m²"}]'
  },
  'French': {
    input: 'rénovation cuisine 20m2 murs et sol',
    output: '[{"name": "Dépose papier peint", "qty": 50, "unit": "m²"}, {"name": "Enduit murs", "qty": 50, "unit": "m²"}, {"name": "Peinture murs", "qty": 50, "unit": "m²"}, {"name": "Dépose revêtement sol", "qty": 20, "unit": "m²"}, {"name": "Pose parquet flottant", "qty": 20, "unit": "m²"}]'
  },
  'Portuguese': {
    input: 'reforma cozinha 20m2 paredes e piso',
    output: '[{"name": "Remoção papel parede", "qty": 50, "unit": "m²"}, {"name": "Reboco paredes", "qty": 50, "unit": "m²"}, {"name": "Pintura paredes", "qty": 50, "unit": "m²"}, {"name": "Remoção piso", "qty": 20, "unit": "m²"}, {"name": "Piso laminado", "qty": 20, "unit": "m²"}]'
  }
};

const langExample = LANG_EXAMPLES[searchLang] || LANG_EXAMPLES['English'];

const parsePrompt = `You are a construction cost estimator. Extract ALL construction works from user's text.

RULES:
1. Output ONLY valid JSON array - NO explanations, NO markdown code blocks
2. Generate works in ${searchLang} language  
3. Be COMPREHENSIVE - include ALL works needed for described scope
4. Use REALISTIC quantities based on area/room size mentioned
5. Work names must be SPECIFIC for database search (not generic like "wall work")

UNITS: m² (area), m (linear), pcs (items), kg, l

EXAMPLE:
Input: "${langExample.input}"
Output: ${langExample.output}

USER INPUT: "${textInput}"

JSON ARRAY OUTPUT:`;

console.log('Prompt prepared, length:', parsePrompt.length);

return { json: { 
  ...cfg, 
  chatId: cid, 
  textInput,
  description: textInput.substring(0, 50) + (textInput.length > 50 ? '...' : ''),
  _parse_prompt: parsePrompt,
  L
}};
};

nodes["\ud83d\udcdd Parse Text Response"] = function($input, $, $getWorkflowStaticData, console) {
// Parse AI response for text works
const aiResponse = $input.first().json;
const prepData = $('Prep Text LLM').first().json;
const cid = String(prepData.chatId);
const sd = $getWorkflowStaticData('global');
const L = prepData.L || {};

console.log('=== PARSE TEXT RESPONSE ===');

let text = '';
if (aiResponse.text) {
  text = aiResponse.text;
} else if (aiResponse.response?.text) {
  text = aiResponse.response.text;
} else if (aiResponse.output) {
  text = aiResponse.output;
}

console.log('Raw response:', text?.substring(0, 200));

// Clean response - remove markdown code blocks
text = text.replace(/```json\n?/gi, '').replace(/```\n?/g, '').trim();

// Extract JSON array
let works = [];
try {
  const match = text.match(/\[.*\]/s);
  if (match) {
    works = JSON.parse(match[0]);
  } else {
    works = JSON.parse(text);
  }
} catch (e) {
  console.log('Parse error:', e.message);
  // Try line by line
  const lines = text.split('\n').filter(l => l.trim().startsWith('{'));
  if (lines.length > 0) {
    try {
      works = JSON.parse('[' + lines.join(',') + ']');
    } catch (e2) {
      console.log('Fallback parse failed');
    }
  }
}

console.log('Parsed works:', works.length);

// Validate and clean works
works = works.map((w, i) => ({
  id: i + 1,
  name: String(w.name || w.work || '').trim(),
  qty: parseFloat(w.qty || w.quantity || 1) || 1,
  unit: String(w.unit || 'm²').trim(),
  room: w.room || ''
})).filter(w => w.name.length > 0);

// Save to session
if (!sd.sess) sd.sess = {};
if (!sd.sess[cid]) sd.sess[cid] = {};
sd.sess[cid].works = works;
sd.sess[cid].description = prepData.description || prepData.textInput?.substring(0, 50) || '';
sd.sess[cid].state = 'parsed';

console.log('Saved', works.length, 'works to session');

return { json: { 
  ...prepData, 
  works, 
  _parsed: true,
  _works_count: works.length
}};
};

nodes["Prep Works"] = function($input, $, $getWorkflowStaticData, console) {
// ═══════════════════════════════════════════════════════════════════════════
// PREP WORKS - Prepare work items for calculation loop (: 5 items)
// ═══════════════════════════════════════════════════════════════════════════

const cfg = $input.first().json;
const cid = String(cfg.chatId);
const sd = $getWorkflowStaticData('global');
const session = sd.sess?.[cid] || {};

// Get all works (no limit)
const works = session.works || [];
const db = session.db || cfg.db;
const L = session.L || cfg.L;

// Initialize results accumulator
if (!sd.res) sd.res = {};
sd.res[cid] = [];

const totalWorks = works.length;

console.log('=== PREP WORKS ===');
console.log('Processing:', totalWorks, 'items');

// Return array for loop processing
return works.map((w, idx) => ({ 
  json: { 
    ...w, 
    db, 
    L, 
    currency: L?.sym || '€',
    bot_token: cfg.bot_token, 
    chatId: cid, 
    sq: w.query || w.name,
    original_query: w.query || w.name,
    work_index: idx + 1, 
    total_works: totalWorks,
    _is_limited: cfg._is_limited,
    _original_total: cfg._total_works
  } 
}));
};

nodes["1\ufe0f\u20e3 Prep Query"] = function($input, $, $getWorkflowStaticData, console) {
// ═══════════════════════════════════════════════════════════════════════════
// PREP QUERY - Prepare search query with Qdrant credentials from TOKEN
// ═══════════════════════════════════════════════════════════════════════════

const loopItem = $input.first().json;
const tokenData = $('🔑 TOKEN').first().json;

const originalQuery = loopItem.sq || loopItem.query || loopItem.name || '';
const collectionName = loopItem.db || '';
const L = loopItem.L || {};
const workUnit = loopItem.unit || 'm²';
const workQty = loopItem.qty || 1;

// Get Qdrant credentials from TOKEN node
const QDRANT_URL = tokenData.QDRANT_URL || 'http://localhost:6333';
const QDRANT_API_KEY = tokenData.QDRANT_API_KEY || '';

console.log('=== PREP QUERY ===');
console.log('Query:', originalQuery);
console.log('Collection:', collectionName);
console.log('Qdrant URL:', QDRANT_URL);

if (!originalQuery || !collectionName) {
  console.log('ERROR: Missing query or collection');
  return [{ json: { ...loopItem, _error: 'Missing data', _skip: true } }];
}

const searchLang = L.search_lang || 'Russian';

// Detect database language from collection name
const isRussianDB = collectionName.includes('RU_') || collectionName.includes('_RU');
const isGermanDB = collectionName.includes('DE_');
const dbLang = isRussianDB ? 'Russian' : (isGermanDB ? 'German' : 'English');

const transformPrompt = `You are a construction cost database search expert for ${dbLang} construction rates database.

TASK: Transform user query into optimal SEARCH KEYWORDS that will match entries in a vector database of construction work rates.

DATABASE CONTEXT:
- Contains standardized construction work rates with codes, names, units, resources
- Each rate has: rate_code, rate_name, rate_unit, scope_of_work, resources
- Language: ${dbLang}

TRANSFORMATION RULES:
1. EXPAND abbreviations to full professional terms
2. ADD synonyms and related construction terms
3. INCLUDE work action verbs (install, apply, lay, mount)
4. Keep original query terms + expanded terms
5. Output in ${dbLang} language only

USER QUERY: ${originalQuery}
UNIT: ${workUnit}

Reply with ONLY the optimized search keywords (one line, no explanations):`;

return [{ json: {
  ...loopItem,
  _original_query: originalQuery,
  _transform_prompt: transformPrompt,
  _collection: collectionName,
  _db_lang: dbLang,
  _qdrant_url: QDRANT_URL,
  _qdrant_key: QDRANT_API_KEY
}}];
};

nodes["2\ufe0f\u20e3 Extract Transform"] = function($input, $, $getWorkflowStaticData, console) {
// ═══════════════════════════════════════════════════════════════════════════
// EXTRACT TRANSFORM - Clean AI response and combine queries
// ═══════════════════════════════════════════════════════════════════════════

const prepData = $('1️⃣ Prep Query').first().json;
const aiResponse = $input.first().json;

console.log('=== EXTRACT TRANSFORM ===');

let transformedQuery = prepData._original_query;

try {
  // n8n AI node returns text in different places
  let content = '';
  if (aiResponse.text) {
    content = aiResponse.text;
  } else if (aiResponse.response?.text) {
    content = aiResponse.response.text;
  } else if (aiResponse.output) {
    content = aiResponse.output;
  } else if (aiResponse.choices?.[0]?.message?.content) {
    // Fallback for raw API response
    content = aiResponse.choices[0].message.content;
  }
  
  if (content && content.length > 5) {
    transformedQuery = content
      .replace(/^(keywords?:|search:|query:|result:)/i, '')
      .replace(/[\n\r]+/g, ' ')
      .trim();
    console.log('Transformed OK');
  }
} catch(e) {
  console.log('Transform failed:', e.message);
}

console.log('Original:', prepData._original_query);
console.log('Transformed:', transformedQuery.substring(0, 80));

// Smart combination - original is more important
const originalWords = prepData._original_query.toLowerCase().split(/\s+/);
const transformedWords = transformedQuery.toLowerCase().split(/\s+/);

// Add only new words from transformation
const newWords = transformedWords.filter(w => 
  w.length > 2 && !originalWords.some(ow => ow.includes(w) || w.includes(ow))
);

const combinedQuery = prepData._original_query + ' ' + newWords.slice(0, 10).join(' ');

console.log('Combined:', combinedQuery.substring(0, 100));

return [{ json: {
  ...prepData,
  _query: combinedQuery.trim(),
  _transformed_query: transformedQuery,
  _collection: prepData._collection,
  _qdrant_url: prepData._qdrant_url,
  _qdrant_key: prepData._qdrant_key,
  _step: 'transform_done'
}}];
};

nodes["4\ufe0f\u20e3 Extract Embedding"] = function($input, $, $getWorkflowStaticData, console) {
// ═══════════════════════════════════════════════════════════════════════════
// EXTRACT EMBEDDING - Get vector from OpenAI response
// ═══════════════════════════════════════════════════════════════════════════

const prepData = $('2️⃣ Extract Transform').first().json;
const embResponse = $input.first().json;

console.log('=== EXTRACT EMBEDDING ===');

if (embResponse.error) {
  console.log('OpenAI Error:', embResponse.error.message);
  return [{ json: { ...prepData, _error: embResponse.error.message, _embedding: [] }}];
}

const embedding = embResponse.data?.[0]?.embedding || [];
console.log('Embedding length:', embedding.length);

// Accept various embedding sizes
if (embedding.length < 256) {
  console.log('WARNING: Embedding too short:', embedding.length);
}

// Pass all data including Qdrant credentials
return [{ json: {
  ...prepData,
  _embedding: embedding,
  _collection: prepData._collection,
  _qdrant_url: prepData._qdrant_url,
  _qdrant_key: prepData._qdrant_key,
  _step: 'embedding_done'
}}];
};

nodes["6\ufe0f\u20e3 Prep Rerank"] = function($input, $, $getWorkflowStaticData, console) {
// ═══════════════════════════════════════════════════════════════════════════
// 6️⃣ PREP RERANK v4 - Fixed for LangChain/n8n vector store format
// ═══════════════════════════════════════════════════════════════════════════

const prepData = $('4️⃣ Extract Embedding').first().json;
const qdrantResponse = $input.first().json;

console.log('=== PREP RERANK v4 ===');

if (qdrantResponse.status?.error) {
  return [{ json: { ...prepData, rate_code: 'QDRANT_ERROR', uc: 0, tc: 0, ql: 'not_found', resources: [] }}];
}

const results = qdrantResponse.result || [];
console.log('Qdrant results:', results.length);

if (results.length === 0) {
  return [{ json: { ...prepData, rate_code: 'NOT_FOUND', rate_name: prepData._original_query, uc: 0, tc: 0, ql: 'not_found', resources: [] }}];
}

const originalQuery = prepData._original_query || prepData.name || '';
const workUnit = prepData.unit || 'm²';
const workQty = prepData.qty || 1;

// Helper: extract actual data from various payload formats
function getPayloadData(rawPayload) {
  // Format 1: LangChain/n8n format - data in payload_full
  if (rawPayload.payload_full) {
    return rawPayload.payload_full;
  }
  // Format 2: data in metadata
  if (rawPayload.metadata?.rate_code || rawPayload.metadata?.hierarchy) {
    return rawPayload.metadata;
  }
  // Format 3: direct format - data at root level
  if (rawPayload.rate_code || rawPayload.hierarchy) {
    return rawPayload;
  }
  // Return as-is
  return rawPayload;
}

// Format компактное описание кандидатов
const candidates = results.slice(0, 5).map((r, i) => {
  const rawPayload = r.payload || {};
  const p = getPayloadData(rawPayload);
  const h = p.hierarchy || {};
  
  // Extract rate info (support both formats)
  const code = p.rate_code || h.subsection_code || h.section_code || h.justification_nr || '';
  const name = p.rate_name || h.subsection_name || h.section_name || '';
  const unit = p.rate_unit || h.unit || '';
  
  // Scope of work
  const workSteps = p.work_steps || [];
  const scopeText = workSteps.slice(0, 3).map(s => s.text || s).join('; ');
  
  // Key materials
  const resources = p.resources || [];
  const materials = resources
    .filter(res => !res.resource_code?.match(/^(DXME|ME_|PU_|RI_)/))
    .slice(0, 3)
    .map(res => res.resource_name)
    .join(', ');
  
  const qdrantScore = (r.score * 100).toFixed(0);
  
  console.log('[' + i + '] ' + code + ' - ' + (name || '').substring(0, 40) + ' | ' + qdrantScore + '%');
  
  return i + '. [' + code + '] ' + name + '\n   Unit: ' + unit + ' | Scope: ' + (scopeText || 'n/a').substring(0, 100) + '\n   Materials: ' + (materials || 'n/a');
}).join('\n\n');

const rerankPrompt = `TASK: Score construction rate candidates (0-100) for matching user's work request.

SCORING GUIDE:
95-100: EXACT MATCH - Same work type, method, materials, unit compatible
80-94: VERY GOOD - Same work, minor spec differences (thickness, brand)
65-79: GOOD - Same category, different specification
50-64: PARTIAL - Related work, different scope
30-49: WEAK - Same trade, different work type
0-29: WRONG - Different trade or unrelated

CRITICAL DISTINCTIONS:
• ГКЛ (гипсокартон) ≠ ГВЛ (гипсоволокно) - DIFFERENT materials, max 60
• Стены ≠ Потолок - check work location matches
• Монтаж ≠ Демонтаж - opposite operations
• 1 слой ≠ 2 слоя - check layer count
• Profile types: ПП60 = ceiling, ПС = wall stud, ПН = guide

UNIT MATCHING:
• Query unit: ${workUnit}
• Rate unit should be compatible or convertible
• m² work → m² rate (ideal)
• m² work → 100m² rate (ok, will scale)

USER REQUEST: "${originalQuery}" (${workQty} ${workUnit})

CANDIDATES:
${candidates}

Return ONLY valid JSON (no markdown):
{"rankings":[{"index":0,"score":N,"reason":"brief reason"},{"index":1,"score":N,"reason":"brief reason"}]}`;

console.log('Prompt length:', rerankPrompt.length);

return [{ json: {
  ...prepData,
  _qdrant_results: results,
  _rerank_prompt: rerankPrompt,
  _step: 'prep_rerank_done'
}}];
};

nodes["8\ufe0f\u20e3 Apply Rerank"] = function($input, $, $getWorkflowStaticData, console) {
// ═══════════════════════════════════════════════════════════════════════════
// 8️⃣ APPLY RERANK v5 - Fixed empty results handling
// ═══════════════════════════════════════════════════════════════════════════

const prepData = $('6️⃣ Prep Rerank').first().json;
const llmResponse = $input.first().json;

console.log('=== APPLY RERANK v5 ===');

const qdrantResults = prepData._qdrant_results || [];

// Early exit if no results
if (qdrantResults.length === 0) {
  console.log('No Qdrant results to rerank');
  return [{ json: {
    ...prepData,
    _best_result: null,
    _best_payload: {},
    _llm_score: 0,
    _llm_reason: 'no results',
    _qdrant_score: 0,
    _quality_level: 'not_found',
    ql: 'not_found',
    _step: 'rerank_done'
  }}];
}

// Helper: extract actual data from various payload formats
function getPayloadData(rawPayload) {
  // Format 1: LangChain/n8n format - data in payload_full
  if (rawPayload.payload_full) {
    return rawPayload.payload_full;
  }
  // Format 2: data in metadata
  if (rawPayload.metadata?.rate_code || rawPayload.metadata?.hierarchy) {
    return rawPayload.metadata;
  }
  // Format 3: direct format - data at root level
  if (rawPayload.rate_code || rawPayload.hierarchy) {
    return rawPayload;
  }
  return rawPayload;
}

let rankings = [];
try {
  // AI node returns text directly, HTTP returns choices[0].message.content
  let text = llmResponse.text || llmResponse.choices?.[0]?.message?.content || '';
  
  // Clear от markdown и лишних символов
  text = text.replace(/```json\n?/g, '').replace(/```/g, '').trim();
  
  console.log('Raw LLM response:', text.substring(0, 200));
  
  // Пытаемся найти JSON
  const jsonMatch = text.match(/\{[\s\S]*\}/);
  if (jsonMatch) {
    const parsed = JSON.parse(jsonMatch[0]);
    rankings = parsed.rankings || [];
    console.log('Parsed rankings:', rankings.length);
  }
} catch(e) {
  console.log('Parse error:', e.message);
  // Fallback - используем Qdrant scores
  rankings = qdrantResults.map((r, i) => ({
    index: i,
    score: Math.round((r.score || 0) * 100),
    reason: 'qdrant score'
  }));
}

// Комбинируем LLM и Qdrant scores
const scored = qdrantResults.map((r, i) => {
  const rawPayload = r.payload || {};
  const p = getPayloadData(rawPayload);
  const h = p.hierarchy || {};
  
  // Normalize payload with extracted data
  const normalizedPayload = {
    ...p,
    rate_code: p.rate_code || h.subsection_code || h.section_code || h.justification_nr || '',
    rate_name: p.rate_name || h.subsection_name || h.section_name || '',
    rate_unit: p.rate_unit || h.unit || '',
    resources: p.resources || [],
    work_steps: p.work_steps || [],
    hierarchy: h
  };
  
  const rank = rankings.find(x => x.index === i);
  const llmScore = rank?.score || 0;
  const reason = rank?.reason || '';
  const qdrantScore = (r.score || 0) * 100;
  
  // Weighted combination: LLM важнее если есть, иначе Qdrant
  let combinedScore;
  if (llmScore > 0) {
    combinedScore = llmScore * 0.7 + qdrantScore * 0.3;
  } else {
    combinedScore = qdrantScore;
  }
  
  console.log('[' + i + '] LLM=' + llmScore + ' Qdrant=' + qdrantScore.toFixed(0) + ' Combined=' + combinedScore.toFixed(0) + ' - ' + (normalizedPayload.rate_code || 'N/A'));
  
  return {
    ...r,
    payload: normalizedPayload,
    llm_score: llmScore,
    llm_reason: reason,
    qdrant_score: r.score || 0,
    combined_score: combinedScore
  };
});

// Sort по комбинированному score
scored.sort((a, b) => b.combined_score - a.combined_score);

const best = scored[0];
const bestPayload = best?.payload || {};
const combinedScore = best?.combined_score || 0;

// Determine quality результата
let qualityLevel = 'not_found';
if (combinedScore >= 80) qualityLevel = 'high';
else if (combinedScore >= 60) qualityLevel = 'medium';
else if (combinedScore >= 40) qualityLevel = 'low';

console.log('');
console.log('✅ BEST: ' + (bestPayload.rate_code || 'N/A') + ' - ' + (bestPayload.rate_name || '').substring(0, 50));
console.log('   Combined: ' + combinedScore.toFixed(0) + ' | Quality: ' + qualityLevel);
console.log('   Reason: ' + (best?.llm_reason || 'N/A'));

return [{ json: {
  ...prepData,
  _best_result: best || null,
  _best_payload: bestPayload,
  _llm_score: best?.llm_score || 0,
  _llm_reason: best?.llm_reason || '',
  _qdrant_score: best?.qdrant_score || 0,
  _quality_level: qualityLevel,
  ql: qualityLevel,
  _step: 'rerank_done'
}}];
};

nodes["9\ufe0f\u20e3 Calculate"] = function($input, $, $getWorkflowStaticData, console) {
// ═══════════════════════════════════════════════════════════════════════════
// STEP 8: Calculate - FIXED VERSION v3
// Универсальный поиск данных в разных структурах
// ═══════════════════════════════════════════════════════════════════════════

const inputData = $input.first().json;

console.log('═══════════════════════════════════════════════════════════════');
console.log('STEP 8: CALCULATE v3');
console.log('═══════════════════════════════════════════════════════════════');

// ═══════════════════════════════════════════════════════════════════════════
// УМНЫЙ ПОИСК PAYLOAD - ищем во всех возможных местах
// ═══════════════════════════════════════════════════════════════════════════

let payload = null;
let payloadSource = 'not_found';

// Вариант 1: _best_result.payload
if (inputData._best_result?.payload?.rate_code) {
  payload = inputData._best_result.payload;
  payloadSource = '_best_result.payload';
}
// Вариант 2: _best_payload напрямую
else if (inputData._best_payload?.rate_code) {
  payload = inputData._best_payload;
  payloadSource = '_best_payload';
}
// Вариант 3: данные лежат прямо в _best_result (без вложенного payload)
else if (inputData._best_result?.rate_code) {
  payload = inputData._best_result;
  payloadSource = '_best_result (direct)';
}
// Вариант 4: payload внутри payload (двойная вложенность)
else if (inputData._best_result?.payload?.payload?.rate_code) {
  payload = inputData._best_result.payload.payload;
  payloadSource = '_best_result.payload.payload';
}
// Вариант 5: ищем rate_code где угодно в _best_result
else if (inputData._best_result) {
  const br = inputData._best_result;
  // Рекурсивный поиск
  const findPayload = (obj, depth = 0) => {
    if (!obj || depth > 3) return null;
    if (obj.rate_code && obj.resources) return obj;
    for (const key of Object.keys(obj)) {
      if (typeof obj[key] === 'object' && obj[key] !== null) {
        const found = findPayload(obj[key], depth + 1);
        if (found) return found;
      }
    }
    return null;
  };
  payload = findPayload(br);
  if (payload) payloadSource = '_best_result (deep search)';
}

console.log('Payload source:', payloadSource);
console.log('Payload found:', !!payload);

if (payload) {
  console.log('Payload keys:', Object.keys(payload));
  console.log('rate_code:', payload.rate_code);
  console.log('rate_name:', payload.rate_name?.substring(0, 50));
  console.log('resources count:', (payload.resources || []).length);
  console.log('cost_summary:', JSON.stringify(payload.cost_summary || {}).substring(0, 200));
}

// Если payload не найден - выводим структуру для диагностики
if (!payload) {
  console.log('');
  console.log('❌ PAYLOAD NOT FOUND! Debug info:');
  console.log('inputData keys:', Object.keys(inputData));
  if (inputData._best_result) {
    console.log('_best_result keys:', Object.keys(inputData._best_result));
    console.log('_best_result.payload:', typeof inputData._best_result.payload);
    if (inputData._best_result.payload) {
      console.log('_best_result.payload keys:', Object.keys(inputData._best_result.payload));
    }
  }
  
  // Возвращаем ошибку с диагностикой
  return [{ json: { 
    ...inputData,
    rate_code: 'PAYLOAD_NOT_FOUND',
    rate_name: inputData.name || inputData.sq || 'Unknown',
    uc: 0, tc: 0,
    resources: [],
    _debug_keys: Object.keys(inputData),
    _debug_best_result_keys: Object.keys(inputData._best_result || {}),
    _debug_payload_source: payloadSource
  }}];
}

// ═══════════════════════════════════════════════════════════════════════════
// Теперь payload найден - извлекаем данные
// ═══════════════════════════════════════════════════════════════════════════

// Базовые данные работы
const workName = inputData.name || inputData.sq || '';
const workQty = inputData.qty || 1;
const workUnit = inputData.unit || 'm²';

console.log('');
console.log('Work:', workName);
console.log('Qty:', workQty, workUnit);

// Данные расценки
const rateCode = payload.rate_code || 'NOT_FOUND';
const rateName = payload.rate_name || workName;
const rateUnit = payload.rate_unit || '';

console.log('Rate code:', rateCode);
console.log('Rate name:', rateName?.substring(0, 50));
console.log('Rate unit:', rateUnit);

// ═══════════════════════════════════════════════════════════════════════════
// Получаем стоимость
// ═══════════════════════════════════════════════════════════════════════════
const costSummary = payload.cost_summary || {};
let totalCost = parseFloat(costSummary.total_cost_position || costSummary.total_cost || 0);

// Если cost_summary пустой, вычисляем из ресурсов
const rawResources = payload.resources || [];
if (totalCost === 0 && rawResources.length > 0) {
  totalCost = rawResources.reduce((sum, r) => {
    return sum + parseFloat(r.resource_cost_eur || 0);
  }, 0);
  console.log('Total cost calculated from resources:', totalCost);
}

console.log('Total cost:', totalCost);
console.log('Resources count:', rawResources.length);

// ═══════════════════════════════════════════════════════════════════════════
// Определяем делитель единицы измерения
// ═══════════════════════════════════════════════════════════════════════════
let unitDivisor = 1;
const rateUnitLower = (rateUnit || '').toLowerCase();

if (rateUnitLower.includes('100 ') || rateUnitLower === '100 м' || rateUnitLower === '100 м²' || rateUnitLower === '100 м2') {
  unitDivisor = 100;
} else if (rateUnitLower.match(/^10\s/) || rateUnitLower.includes('10 м')) {
  unitDivisor = 10;
}

console.log('Unit divisor:', unitDivisor);

// ═══════════════════════════════════════════════════════════════════════════
// Price calculation
// ═══════════════════════════════════════════════════════════════════════════
const uc = unitDivisor > 0 ? totalCost / unitDivisor : 0;
const tc = workQty * uc;
const scaleFactor = unitDivisor > 0 ? workQty / unitDivisor : workQty;

console.log('');
console.log('=== PRICE CALCULATION ===');
console.log('UC (price per unit):', uc.toFixed(2), 'EUR');
console.log('TC (total cost):', tc.toFixed(2), 'EUR');
console.log('Scale factor:', scaleFactor);

// ═══════════════════════════════════════════════════════════════════════════
// Обработка ресурсов
// ═══════════════════════════════════════════════════════════════════════════
let workersTotal = 0;
let materialsTotal = 0;
let machinesTotal = 0;
let laborHoursTotal = 0;

const resources = rawResources.map(r => {
  const code = r.resource_code || '';
  const name = r.resource_name || '';
  const unit = r.resource_unit || '';
  const rowType = r.row_type || '';
  
  const originalQty = r.resource_quantity !== null && r.resource_quantity !== undefined 
    ? parseFloat(r.resource_quantity) 
    : null;
  const pricePerUnit = parseFloat(r.resource_price_per_unit_eur_current || 0);
  const originalCost = parseFloat(r.resource_cost_eur || 0);
  
  // Определяем тип ресурса
  let resourceType = 'material';
  const rowTypeLower = (rowType || '').toLowerCase();
  const codeUpper = (code || '').toUpperCase();
  
  if (rowTypeLower === 'машинист' || rowTypeLower.includes('машинист')) {
    resourceType = 'labor';
  } else if (rowTypeLower === 'электричество' || rowTypeLower.includes('электричеств')) {
    resourceType = 'machine';
  } else if (codeUpper.startsWith('DXME') || codeUpper.startsWith('DX')) {
    resourceType = 'machine';
  } else if (codeUpper.startsWith('ME_') || codeUpper.startsWith('PU_') || codeUpper.startsWith('RI_')) {
    resourceType = 'labor';
  }
  
  // Масштабирование
  let scaledQty = null;
  let scaledCost = 0;
  
  if (originalQty !== null) {
    scaledQty = originalQty * scaleFactor;
    scaledCost = scaledQty * pricePerUnit;
  } else {
    scaledCost = originalCost * scaleFactor;
  }
  
  // Суммируем по категориям
  if (resourceType === 'labor') {
    workersTotal += scaledCost;
    if (unit === 'ч' || unit === 'чел.-ч' || unit === 'чел-ч' || unit === 'маш.-ч') {
      laborHoursTotal += scaledQty || 0;
    }
  } else if (resourceType === 'machine') {
    machinesTotal += scaledCost;
  } else {
    materialsTotal += scaledCost;
  }
  
  return {
    resource_code: code,
    resource_name: name,
    resource_unit: unit,
    resource_type: resourceType,
    row_type: rowType,
    resource_price: pricePerUnit,
    original_quantity: originalQty,
    original_cost: originalCost,
    scaled_quantity: scaledQty,
    scaled_cost: scaledCost
  };
});

console.log('');
console.log('=== RESOURCES BREAKDOWN ===');
console.log('Resources processed:', resources.length);
console.log('Workers total:', workersTotal.toFixed(2), 'EUR');
console.log('Materials total:', materialsTotal.toFixed(2), 'EUR');
console.log('Machines total:', machinesTotal.toFixed(2), 'EUR');
console.log('Labor hours:', laborHoursTotal.toFixed(1), 'h');

// ═══════════════════════════════════════════════════════════════════════════
// Scope of work
// ═══════════════════════════════════════════════════════════════════════════
const workSteps = payload.work_steps || [];
const scopeOfWork = workSteps.map(s => s.text || '').filter(t => t.length > 0);

// ═══════════════════════════════════════════════════════════════════════════
// Quality
// ═══════════════════════════════════════════════════════════════════════════
const llmScore = inputData._llm_score || 0;
const qdrantScore = inputData._qdrant_score || 0;

const qualityLevel = llmScore >= 75 ? 'high' : 
                     llmScore >= 50 ? 'medium' : 
                     llmScore >= 25 ? 'low' : 'not_found';

console.log('');
console.log('═══════════════════════════════════════════════════════════════');
console.log('✅ CALCULATION COMPLETE');
console.log('Rate:', rateCode, '-', rateName?.substring(0, 40));
console.log('Total:', tc.toFixed(2), 'EUR');
console.log('Resources:', resources.length);
console.log('═══════════════════════════════════════════════════════════════');

// ═══════════════════════════════════════════════════════════════════════════
// ФИНАЛЬНЫЙ РЕЗУЛЬТАТ
// ═══════════════════════════════════════════════════════════════════════════
return [{ json: { 
  // Original data
  ...inputData,
  name: workName,
  qty: workQty,
  unit: workUnit,
  
  // Rate
  rate_code: rateCode,
  rate_name: rateName,
  rate_unit: workUnit,
  original_rate_unit: rateUnit,
  
  // Prices
  uc,
  tc,
  
  // Labor
  labor_hours: laborHoursTotal,
  workers_total: workersTotal,
  machines_total: machinesTotal,
  materials_total: materialsTotal,
  
  // Quality
  ql: qualityLevel,
  quality_score: llmScore,
  qdrant_score: qdrantScore,
  llm_score: llmScore,
  llm_reason: inputData._llm_reason || '',
  
  // Resources
  resources,
  
  // Scope of work
  scope_of_work: scopeOfWork,
  
  // Hierarchy
  hierarchy: payload.hierarchy || {},
  
  // Breakdown
  cost_breakdown: { 
    workers: workersTotal, 
    machines: machinesTotal, 
    materials: materialsTotal 
  },
  
  // Debug
  _payload_source: payloadSource,
  _scale_factor: scaleFactor,
  _unit_divisor: unitDivisor,
  _original_total_cost: totalCost
}}];
};

nodes["\ud83d\udcca Update Result"] = function($input, $, $getWorkflowStaticData, console) {
// ═══════════════════════════════════════════════════════════════════════════
// UPDATE RESULT - Format result message (✓ Found / Not found)
// ═══════════════════════════════════════════════════════════════════════════

const calcData = $input.first().json;
const sd = $getWorkflowStaticData('global');
const cid = String(calcData.chatId);
const L = calcData.L || {};

const current = calcData.work_index || 1;
const total = calcData.total_works || 1;
const name = calcData.name || calcData.sq || 'Work';

let shortName = name.length > 22 ? name.substring(0, 19) + '...' : name;

const tc = parseFloat(calcData.tc) || 0;
const uc = parseFloat(calcData.uc) || 0;
const rateCode = String(calcData.rate_code || '');
const rateName = String(calcData.rate_name || '');
const currency = calcData.currency || L.sym || '€';

const hasValidRate = rateCode && 
  !rateCode.includes('NOT_FOUND') && 
  !rateCode.includes('PAYLOAD_NOT_FOUND');

const found = tc > 0 || uc > 0 || hasValidRate || (rateName && rateName.length > 0);

console.log('Result:', shortName, found ? '✓' : '✗', tc.toFixed(0), currency);

let text = '';
if (found) {
  text = current + '/' + total + ' ' + shortName + ' ✓\n';
  text += tc.toFixed(0) + ' ' + currency;
  if (rateCode && hasValidRate) text += ' · ' + rateCode.substring(0, 20);
} else {
  text = current + '/' + total + ' ' + shortName + '\n';
  text += (L.not_found || 'Не найдено');
}

const msgId = sd.calcProgress?.[cid]?.lastMsgId || null;

return { json: { ...calcData, _result_text: text, _edit_msg_id: msgId, _found: found } };
};

nodes["Acc"] = function($input, $, $getWorkflowStaticData, console) {
// ═══════════════════════════════════════════════════════════════════════════
// ACC - Accumulate calculation results for final aggregation
// ═══════════════════════════════════════════════════════════════════════════

const sd = $getWorkflowStaticData('global');
const w = $('📊 Update Result').first().json;
const cid = String(w.chatId);

if (!sd.res) sd.res = {};
if (!sd.res[cid]) sd.res[cid] = [];
sd.res[cid].push(w);

console.log('Accumulated:', sd.res[cid].length, '/', w.total_works);

return { json: w };
};

nodes["Agg"] = function($input, $, $getWorkflowStaticData, console) {
// ═══════════════════════════════════════════════════════════════════════════
// AGG - Final aggregation of calculation results + DDC CWICR info
// ═══════════════════════════════════════════════════════════════════════════

const cfg = $('Config').first().json;
const cid = String(cfg.chatId);
const sd = $getWorkflowStaticData('global');
const session = sd.sess?.[cid] || {};

const L = cfg.L || {};
let total = 0, workers_sum = 0, materials_sum = 0, machines_sum = 0, labor_hours_sum = 0;
let found_count = 0;

// Get accumulated results
const storedResults = sd.res?.[cid] || [];

console.log('=== AGG ===');
console.log('Results count:', storedResults.length);

// Process each result
const works = storedResults.map(w => {
  const uc = w.uc || 0;
  const tc = w.tc || 0;

  total += tc;
  workers_sum += (w.workers_total || 0);
  materials_sum += (w.materials_total || 0);
  machines_sum += (w.machines_total || 0);
  labor_hours_sum += (w.labor_hours || 0);

  if (w._found) found_count++;

  return {
    id: w.id,
    name: w.name || w.sq,
    query: w.sq || w.query,
    qty: w.qty,
    unit: w.unit,
    room: w.room,
    uc: uc,
    tc: tc,
    rate_code: w.rate_code || '',
    rate_name: w.rate_name || '',
    resources: w.resources || [],
    workers_total: w.workers_total || 0,
    materials_total: w.materials_total || 0,
    machines_total: w.machines_total || 0,
    labor_hours: w.labor_hours || 0,
    found: w._found || false,
    scope_of_work: w.scope_of_work || [],
    original_query: w.original_query || w.name
  };
});

const pct = works.length > 0 ? Math.round(found_count / works.length * 100) : 0;

// DDC CWICR info
const isLimited = false; // No limit
const originalTotal = session.totalWorks || works.length;
const skippedWorks = originalTotal - works.length;

console.log('Calculated:', works.length, '/', originalTotal);
console.log('Found:', found_count, '/', works.length);
console.log('Total cost:', total.toFixed(2));
// No limit mode

// Cleanup staticData
if (sd.res?.[cid]) delete sd.res[cid];
if (sd.calcProgress?.[cid]) delete sd.calcProgress[cid];
if (sd.progress?.[cid]) delete sd.progress[cid];

// Save for report generation
sd.lastResults = { works, total, workers_sum, materials_sum, machines_sum, labor_hours_sum, found_count, pct, L };

return {
  json: {
    chatId: cid,
    bot_token: cfg.bot_token,
    works: works,
    total: Math.round(total * 100) / 100,
    workers_sum: Math.round(workers_sum * 100) / 100,
    materials_sum: Math.round(materials_sum * 100) / 100,
    machines_sum: Math.round(machines_sum * 100) / 100,
    labor_hours_sum: Math.round(labor_hours_sum * 100) / 100,
    found_count: found_count,
    total_count: works.length,
    pct: pct,
    L: L,
    currency: L.sym || '€',
    description: session.description || '',
    // DDC CWICR
    _is_limited: isLimited,
    _total_works: originalTotal,
    _skipped_works: skippedWorks
  }
};
};

export function runNode(name, input, context, state) {
  const get = value => ({ first: () => ({ json: value }), item: { json: value }, all: () => [{ json: value }] });
  const result = nodes[name](get(input), key => get(context[key] ?? {}), () => state, { log() {}, error() {} });
  return Array.isArray(result) ? result.map(x => x.json) : result.json;
}
