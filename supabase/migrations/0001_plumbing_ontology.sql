-- Plumbing ontology: jobs + materials + recipe + shop settings.
-- ChatGPT picks a job_id and a scale number. Everything else (prices,
-- quantities, labor) is computed by the edge function from these tables.

-- ============================================================
-- materials: every plumbing item you'd ever quote.
-- ============================================================
create table if not exists materials (
  id            text primary key,            -- e.g. 'wax_ring_standard'
  name          text not null,               -- e.g. 'Standard Wax Ring'
  unit          text not null,               -- 'each', 'foot', 'box'
  unit_price    numeric(10,2) not null,      -- real $ from supplier
  supplier      text,                        -- 'Home Depot', 'Lowe's', 'Ferguson'
  supplier_url  text,                        -- link to verify/refresh price
  updated_at    timestamptz not null default now()
);

-- ============================================================
-- jobs: the ~50 plumbing jobs the app supports.
-- ChatGPT must pick from this list — nothing else is allowed.
-- ============================================================
create table if not exists jobs (
  id            text primary key,            -- e.g. 'toilet_replace'
  name          text not null,               -- 'Replace Toilet'
  description   text not null,               -- plain English so ChatGPT can match
  labor_hours   numeric(5,2) not null,       -- baked-in hours for one unit of scale
  scale_unit    text not null,               -- 'fixture', 'linear_foot', 'gallon', 'job'
  scale_default numeric(8,2) not null default 1  -- if user gives no number, assume this
);

-- ============================================================
-- job_materials: the recipe.
-- For each job, which materials and how much per unit of scale.
-- ============================================================
create table if not exists job_materials (
  job_id              text not null references jobs(id) on delete cascade,
  material_id         text not null references materials(id) on delete restrict,
  quantity_per_scale  numeric(10,3) not null,  -- e.g. 1 wax ring per fixture, 6 ft pex per linear_foot
  primary key (job_id, material_id)
);

-- ============================================================
-- shop_settings: 1 row. Your rates.
-- ============================================================
create table if not exists shop_settings (
  id                 int primary key default 1,
  hourly_rate        numeric(8,2) not null default 130.00,
  material_markup    numeric(4,2) not null default 1.30,  -- 1.30 = 30% markup
  overhead_percent   numeric(4,2) not null default 0.10,  -- 10%
  constraint shop_settings_single_row check (id = 1)
);

insert into shop_settings (id) values (1) on conflict do nothing;

-- ============================================================
-- SEED DATA — a few materials + 3 jobs so you can see the flow.
-- Replace prices/URLs with real ones from your supplier of choice.
-- ============================================================
insert into materials (id, name, unit, unit_price, supplier, supplier_url) values
  ('wax_ring_standard',      'Standard Wax Ring',              'each', 4.98,  'Home Depot', 'https://www.homedepot.com/p/example-wax-ring'),
  ('toilet_bolts',           'Closet Bolt Set',                'each', 3.47,  'Home Depot', 'https://www.homedepot.com/p/example-bolts'),
  ('supply_line_braided_12', 'Braided Toilet Supply Line 12"', 'each', 7.98,  'Home Depot', 'https://www.homedepot.com/p/example-supply-line'),
  ('shutoff_valve_quarter',  '1/4-turn Angle Stop Valve',      'each', 11.97, 'Home Depot', 'https://www.homedepot.com/p/example-shutoff'),
  ('water_heater_50gal_gas', '50-gal Gas Water Heater',        'each', 749.00,'Home Depot', 'https://www.homedepot.com/p/example-water-heater'),
  ('tp_valve',               'T&P Relief Valve',               'each', 18.97, 'Home Depot', 'https://www.homedepot.com/p/example-tp-valve'),
  ('flex_supply_water',      'Flex Water Supply Connector',    'each', 14.98, 'Home Depot', 'https://www.homedepot.com/p/example-flex'),
  ('pipe_dope',              'Pipe Thread Sealant',            'each', 6.47,  'Home Depot', 'https://www.homedepot.com/p/example-pipe-dope'),
  ('pex_half_inch',          '1/2" PEX Tubing',                'foot', 0.45,  'Home Depot', 'https://www.homedepot.com/p/example-pex'),
  ('pex_fitting_half',       '1/2" PEX Crimp Fitting',         'each', 1.85,  'Home Depot', 'https://www.homedepot.com/p/example-pex-fitting')
on conflict (id) do nothing;

insert into jobs (id, name, description, labor_hours, scale_unit, scale_default) values
  ('toilet_replace',
   'Replace Toilet',
   'Remove existing toilet and install a new one. Includes new wax ring, bolts, and supply line. Per fixture.',
   2.0, 'fixture', 1),
  ('water_heater_install_gas',
   'Install Gas Water Heater',
   'Remove old tank and install a new gas water heater. Scale is gallons (40, 50, 75, etc.).',
   4.0, 'gallon', 50),
  ('repipe_run_pex',
   'Run PEX Water Line',
   'Run new 1/2" PEX water supply line. Scale is linear feet of run.',
   0.15, 'linear_foot', 20)
on conflict (id) do nothing;

insert into job_materials (job_id, material_id, quantity_per_scale) values
  -- Toilet replace: 1 of each per fixture
  ('toilet_replace', 'wax_ring_standard',      1),
  ('toilet_replace', 'toilet_bolts',           1),
  ('toilet_replace', 'supply_line_braided_12', 1),
  ('toilet_replace', 'shutoff_valve_quarter',  1),
  -- Water heater: 1 heater per "50 gallon unit" (scale_unit=gallon, but we keep recipe simple — 1 per job).
  -- Note: for the heater itself we use quantity 0.02 so 50 gallons => 1 heater. Pragmatic for now.
  ('water_heater_install_gas', 'water_heater_50gal_gas', 0.02),
  ('water_heater_install_gas', 'tp_valve',               0.02),
  ('water_heater_install_gas', 'flex_supply_water',      0.04),  -- 2 per install
  ('water_heater_install_gas', 'pipe_dope',              0.02),
  -- Repipe: 1 ft of PEX per linear foot, 1 fitting every 5 ft
  ('repipe_run_pex', 'pex_half_inch',    1.0),
  ('repipe_run_pex', 'pex_fitting_half', 0.2)
on conflict do nothing;
