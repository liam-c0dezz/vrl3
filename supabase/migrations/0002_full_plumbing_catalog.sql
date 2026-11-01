-- Full plumbing catalog: 50 jobs + ~80 materials + recipes.
-- Prices are realistic placeholders to test the flow end-to-end.
-- Supplier URLs are intentionally NULL — to be filled in after the
-- 50-job structure is approved.

-- ============================================================
-- MATERIALS
-- ============================================================
insert into materials (id, name, unit, unit_price, supplier, supplier_url) values
  -- Toilets & toilet parts
  ('toilet_round_standard',     'Round Toilet (standard)',           'each', 119.00, null, null),
  ('toilet_elongated_standard', 'Elongated Toilet (standard)',       'each', 179.00, null, null),
  ('toilet_seat_standard',      'Standard Toilet Seat',              'each',  24.97, null, null),
  ('toilet_fill_valve',         'Toilet Fill Valve',                 'each',  12.97, null, null),
  ('toilet_flapper',            'Toilet Flapper',                    'each',   5.97, null, null),
  ('wax_ring_extra_thick',      'Extra Thick Wax Ring',              'each',   7.98, null, null),
  ('bidet_seat_electric',       'Electric Bidet Seat',               'each', 299.00, null, null),
  ('bidet_seat_manual',         'Non-Electric Bidet Seat',           'each',  89.00, null, null),

  -- Supply lines & shutoffs
  ('supply_line_braided_20',    'Braided Supply Line 20"',           'each',   9.98, null, null),
  ('shutoff_valve_compression', 'Compression Shutoff Valve',         'each',  10.97, null, null),
  ('ball_valve_half',           '1/2" Ball Valve',                   'each',   9.98, null, null),
  ('ball_valve_three_quarter',  '3/4" Ball Valve',                   'each',  12.98, null, null),
  ('main_shutoff_valve',        'Main Water Shutoff Valve',          'each',  45.00, null, null),
  ('pressure_regulator',        'Water Pressure Regulator',          'each',  85.00, null, null),
  ('water_hammer_arrestor',     'Water Hammer Arrestor',             'each',  18.98, null, null),
  ('hose_bib_standard',         'Standard Hose Bib',                 'each',  14.98, null, null),
  ('hose_bib_frost_free',       'Frost-Free Hose Bib',               'each',  29.98, null, null),

  -- Faucets & shower fixtures
  ('kitchen_faucet_standard',   'Kitchen Faucet (standard)',         'each', 129.00, null, null),
  ('kitchen_faucet_pullout',    'Kitchen Faucet (pullout)',          'each', 189.00, null, null),
  ('bath_faucet_standard',      'Bathroom Faucet (standard)',        'each',  79.00, null, null),
  ('bath_faucet_widespread',    'Bathroom Faucet (widespread)',      'each', 149.00, null, null),
  ('shower_valve_pb',           'Pressure-Balanced Shower Valve',    'each',  95.00, null, null),
  ('shower_head_standard',      'Standard Shower Head',              'each',  34.98, null, null),
  ('tub_spout_diverter',        'Tub Spout w/ Diverter',             'each',  24.98, null, null),

  -- Sinks, vanities, tubs
  ('kitchen_sink_dropin',       'Drop-In Stainless Kitchen Sink',    'each', 199.00, null, null),
  ('kitchen_sink_undermount',   'Undermount Kitchen Sink',           'each', 289.00, null, null),
  ('bath_sink_dropin',          'Drop-In Bathroom Sink',             'each',  89.00, null, null),
  ('bath_vanity_24',            '24" Bathroom Vanity',               'each', 249.00, null, null),
  ('bathtub_standard_60',       '60" Standard Bathtub',              'each', 299.00, null, null),
  ('shower_pan_36',             '36"x36" Shower Pan',                'each', 229.00, null, null),
  ('tub_shower_combo',          'Tub/Shower Combo Unit',             'each', 479.00, null, null),

  -- Water heaters & accessories
  ('water_heater_40gal_gas',    '40-gal Gas Water Heater',           'each', 599.00, null, null),
  ('water_heater_50gal_electric','50-gal Electric Water Heater',     'each', 549.00, null, null),
  ('water_heater_tankless_gas', 'Tankless Gas Water Heater',         'each',1199.00, null, null),
  ('water_heater_drain_pan',    'Water Heater Drain Pan',            'each',  24.98, null, null),
  ('water_heater_strap_kit',    'Water Heater Earthquake Strap Kit', 'each',  14.98, null, null),
  ('flex_gas_connector',        'Flex Gas Connector',                'each',  24.98, null, null),

  -- Drains, traps, disposals
  ('p_trap_kit',                'P-Trap Kit',                        'each',  12.98, null, null),
  ('garbage_disposal_half',     '1/2 HP Garbage Disposal',           'each', 129.00, null, null),
  ('garbage_disposal_three_q',  '3/4 HP Garbage Disposal',           'each', 179.00, null, null),
  ('abs_pipe_2in',              '2" ABS Drain Pipe',                 'foot',   1.85, null, null),
  ('pvc_pipe_2in',              '2" PVC Drain Pipe',                 'foot',   1.65, null, null),
  ('pvc_pipe_3in',              '3" PVC Drain Pipe',                 'foot',   2.85, null, null),
  ('pvc_fitting_2in',           '2" PVC Fitting',                    'each',   3.50, null, null),
  ('pvc_fitting_3in',           '3" PVC Fitting',                    'each',   5.25, null, null),
  ('abs_cement',                'ABS/PVC Cement',                    'each',   8.98, null, null),

  -- Supply pipes (PEX, copper)
  ('pex_three_quarter',         '3/4" PEX Tubing',                   'foot',   0.65, null, null),
  ('pex_fitting_three_quarter', '3/4" PEX Crimp Fitting',            'each',   2.85, null, null),
  ('copper_pipe_half',          '1/2" Copper Pipe',                  'foot',   3.45, null, null),
  ('copper_fitting_half',       '1/2" Copper Fitting',               'each',   1.95, null, null),
  ('teflon_tape',               'Teflon Tape',                       'each',   1.98, null, null),
  ('solder_lead_free',          'Lead-Free Solder',                  'each',  12.98, null, null),
  ('pipe_clamp_repair',         'Pipe Repair Clamp',                 'each',  11.98, null, null),

  -- Gas
  ('black_iron_pipe_half',      '1/2" Black Iron Pipe',              'foot',   3.85, null, null),
  ('black_iron_fitting_half',   '1/2" Black Iron Fitting',           'each',   4.85, null, null),
  ('csst_half',                 '1/2" CSST Gas Line',                'foot',   2.85, null, null),
  ('gas_shutoff_valve',         'Gas Shutoff Valve',                 'each',  18.98, null, null),
  ('gas_leak_detector',         'Gas Leak Detector Solution',        'each',   8.98, null, null),

  -- Appliance hookups
  ('washing_machine_box',       'Washing Machine Outlet Box',        'each',  34.98, null, null),
  ('washing_machine_hose_pair', 'Washing Machine Hose Pair',         'each',  22.98, null, null),
  ('ice_maker_line_kit',        'Ice Maker Line Kit',                'each',  24.98, null, null),
  ('dishwasher_supply_kit',     'Dishwasher Supply Kit',             'each',  16.98, null, null),
  ('dishwasher_drain_hose',     'Dishwasher Drain Hose',             'each',  12.98, null, null),

  -- Specialty equipment
  ('water_softener',            'Water Softener System',             'each', 499.00, null, null),
  ('water_filter_whole_house',  'Whole-House Water Filter',          'each', 229.00, null, null),
  ('sump_pump_third_hp',        '1/3 HP Sump Pump',                  'each', 179.00, null, null),
  ('sump_pump_half_hp',         '1/2 HP Sump Pump',                  'each', 249.00, null, null),
  ('ejector_pump',              'Sewage Ejector Pump',               'each', 329.00, null, null),
  ('backflow_preventer',        'Backflow Preventer',                'each', 189.00, null, null),

  -- Consumables & misc
  ('caulk_silicone',            'Silicone Caulk',                    'each',   6.98, null, null),
  ('plumbers_putty',            'Plumbers Putty',                    'each',   4.98, null, null),
  ('pipe_strap_pkg',            'Pipe Strap (pack)',                 'each',   7.98, null, null),
  ('mounting_hardware',         'Mounting Hardware Kit',             'each',   9.98, null, null),
  ('electrical_pigtail',        'Disposal Electrical Pigtail',       'each',   4.98, null, null),
  ('drain_cleaning_consumables','Drain Cleaning Consumables',        'each',  15.00, null, null),
  ('camera_scope_use',          'Sewer Camera Use Fee',              'each',  75.00, null, null),
  ('hydro_jet_use',             'Hydro-Jet Equipment Use Fee',       'each', 125.00, null, null)
on conflict (id) do nothing;

-- ============================================================
-- JOBS — 50 common plumbing jobs.
-- Scale defaults: 1 unless the job is naturally per-foot or per-gallon.
-- ============================================================
insert into jobs (id, name, description, labor_hours, scale_unit, scale_default) values
  -- Toilets (5)
  ('toilet_repair_internal',     'Repair Toilet Internals',        'Replace fill valve and/or flapper to fix a running or weak-flushing toilet.',                     0.5, 'job', 1),
  ('toilet_reset_wax_ring',      'Reset Toilet on New Wax Ring',   'Pull existing toilet, install fresh wax ring and bolts, reset toilet. Fix wobble or seal leak.', 1.0, 'job', 1),
  ('bidet_seat_install',         'Install Bidet Seat',             'Install bidet seat onto existing toilet, including tee fitting on supply line.',                  0.75,'job', 1),
  ('toilet_snake',               'Snake Toilet Drain',             'Clear a clogged toilet with a closet auger.',                                                    0.5, 'job', 1),

  -- Sinks & faucets (6)
  ('kitchen_faucet_replace',     'Replace Kitchen Faucet',         'Remove old faucet, install new faucet and supply lines.',                                        1.5, 'job', 1),
  ('bath_faucet_replace',        'Replace Bathroom Faucet',        'Remove old faucet, install new faucet and supply lines.',                                        1.5, 'job', 1),
  ('kitchen_sink_install_dropin','Install Drop-In Kitchen Sink',   'Install drop-in stainless kitchen sink including faucet hookup and drain.',                       2.0, 'job', 1),
  ('kitchen_sink_install_under', 'Install Undermount Kitchen Sink','Install undermount kitchen sink including faucet hookup and drain.',                              3.0, 'job', 1),
  ('bath_sink_replace',          'Replace Bathroom Sink',          'Replace drop-in bathroom sink including faucet hookup and drain.',                                1.5, 'job', 1),
  ('vanity_install',             'Install Bathroom Vanity',        'Install 24" vanity with sink, faucet, and drain connections.',                                    2.5, 'job', 1),

  -- Showers & tubs (6)
  ('shower_valve_replace',       'Replace Shower Valve',           'Replace shower valve cartridge/body. Includes opening and patching access.',                      3.0, 'job', 1),
  ('shower_head_replace',        'Replace Shower Head',            'Swap shower head with new one. Teflon tape and re-thread.',                                       0.25,'job', 1),
  ('tub_spout_replace',          'Replace Tub Spout',              'Replace tub spout with diverter.',                                                                0.5, 'job', 1),
  ('tub_shower_combo_install',   'Install Tub/Shower Combo',       'Demo old unit, install new tub/shower combo with valve and drain.',                               8.0, 'job', 1),
  ('shower_pan_install',         'Install Shower Pan',             'Install 36"x36" shower pan with drain.',                                                          6.0, 'job', 1),
  ('bathtub_replace',            'Replace Bathtub',                'Remove old bathtub, install new 60" standard tub.',                                               6.0, 'job', 1),

  -- Water heaters (5)
  ('water_heater_install_elec',  'Install Electric Water Heater',  'Remove old tank and install new 50-gal electric water heater.',                                  3.0, 'job', 1),
  ('water_heater_install_tnk',   'Install Tankless Gas Heater',    'Install new tankless gas water heater including gas and water connections.',                      6.0, 'job', 1),
  ('water_heater_flush',         'Flush Water Heater',             'Drain, flush, and refill water heater. Annual maintenance.',                                      1.0, 'job', 1),
  ('water_heater_tp_valve',      'Replace T&P Valve',              'Replace temperature and pressure relief valve on water heater.',                                  1.0, 'job', 1),

  -- Drains & sewer (6)
  ('drain_snake_sink',           'Snake Sink Drain',               'Clear clogged kitchen or bath sink with hand snake.',                                             1.0, 'job', 1),
  ('drain_snake_main',           'Snake Main Sewer Line',          'Clear main sewer line with power snake through clean-out.',                                       1.5, 'job', 1),
  ('drain_hydro_jet',            'Hydro-Jet Sewer Line',           'Clear sewer line using hydro-jet for heavy grease or root intrusion.',                            2.0, 'job', 1),
  ('drain_camera_inspect',       'Camera Inspect Sewer Line',      'Run camera through sewer line and produce video report.',                                         1.5, 'job', 1),
  ('p_trap_replace',             'Replace P-Trap',                 'Replace P-trap under a sink.',                                                                    0.75,'job', 1),
  ('garbage_disposal_replace',   'Replace Garbage Disposal',       'Remove old disposal, install new 1/2 HP unit, reconnect drain and electrical.',                   1.5, 'job', 1),

  -- Water supply & pipes (8)
  ('shutoff_valve_replace',      'Replace Shutoff Valve',          'Replace angle stop / shutoff valve under sink or toilet.',                                        1.0, 'job', 1),
  ('whole_house_shutoff',        'Install Whole-House Shutoff',    'Install main ball valve at water entry.',                                                         2.0, 'job', 1),
  ('burst_pipe_repair',          'Repair Burst Pipe',              'Cut out burst section, install repair coupling or rebuild joint.',                                2.0, 'job', 1),
  ('hose_bib_install',           'Install Hose Bib',               'Install exterior hose bib through wall.',                                                         1.5, 'job', 1),
  ('water_main_shutoff_replace', 'Replace Water Main Shutoff',     'Replace main shutoff valve at house entry.',                                                      3.0, 'job', 1),
  ('pressure_regulator_install', 'Install Pressure Regulator',     'Install or replace water pressure regulator.',                                                    2.0, 'job', 1),
  ('water_hammer_arrestor_inst', 'Install Water Hammer Arrestor',  'Install water hammer arrestor on supply line.',                                                   1.0, 'job', 1),

  -- Gas (3)
  ('gas_line_appliance',         'Run Gas Line for Appliance',     'Run new gas line for stove, dryer, or other appliance. Scale is linear feet.',                    0.3, 'linear_foot', 10),
  ('gas_shutoff_replace',        'Replace Gas Shutoff Valve',      'Replace gas shutoff valve at appliance.',                                                         1.0, 'job', 1),
  ('gas_leak_test',              'Test for Gas Leak',              'Pressure test gas system and locate leaks.',                                                      1.0, 'job', 1),

  -- Drainage & appliance hookups (4)
  ('drain_line_run',             'Run Drain Line',                 'Run new ABS or PVC drain line. Scale is linear feet.',                                            0.3, 'linear_foot', 10),
  ('washing_machine_box_install','Install Washing Machine Box',    'Install recessed washing machine outlet box with hot/cold valves and drain.',                     2.0, 'job', 1),
  ('ice_maker_line_install',     'Install Ice Maker Line',         'Install supply line for refrigerator ice maker.',                                                 1.5, 'job', 1),
  ('dishwasher_hookup',          'Hook Up Dishwasher',             'Connect dishwasher water supply and drain.',                                                      1.5, 'job', 1),

  -- Specialty installs (5)
  ('water_softener_install',     'Install Water Softener',         'Install water softener at main supply.',                                                          3.0, 'job', 1),
  ('water_filter_install',       'Install Whole-House Filter',     'Install whole-house water filter at main supply.',                                                2.0, 'job', 1),
  ('sump_pump_install',          'Install Sump Pump',              'Install new sump pump in existing basin.',                                                        2.5, 'job', 1),
  ('ejector_pump_install',       'Install Sewage Ejector Pump',    'Install sewage ejector pump for below-grade fixtures.',                                           4.0, 'job', 1),
  ('backflow_preventer_install', 'Install Backflow Preventer',     'Install backflow preventer on irrigation or main supply.',                                        2.0, 'job', 1),

  -- Repairs / misc (2)
  ('pipe_joint_leak_repair',     'Repair Leaking Pipe Joint',      'Cut, clean, and remake a leaking pipe joint.',                                                    1.5, 'job', 1),
  ('washer_hoses_replace',       'Replace Washing Machine Hoses',  'Replace pair of washing machine supply hoses with braided stainless.',                            0.5, 'job', 1)
on conflict (id) do nothing;

-- ============================================================
-- RECIPES — what materials each job needs.
-- Quantities are per scale unit (per fixture, per linear foot, etc.)
-- ============================================================
insert into job_materials (job_id, material_id, quantity_per_scale) values
  -- Toilet repairs
  ('toilet_repair_internal', 'toilet_fill_valve', 1),
  ('toilet_repair_internal', 'toilet_flapper', 1),

  ('toilet_reset_wax_ring', 'wax_ring_extra_thick', 1),
  ('toilet_reset_wax_ring', 'toilet_bolts', 1),
  ('toilet_reset_wax_ring', 'caulk_silicone', 1),

  ('bidet_seat_install', 'bidet_seat_electric', 1),
  ('bidet_seat_install', 'supply_line_braided_12', 1),

  ('toilet_snake', 'drain_cleaning_consumables', 1),

  -- Sinks & faucets
  ('kitchen_faucet_replace', 'kitchen_faucet_standard', 1),
  ('kitchen_faucet_replace', 'supply_line_braided_20', 2),
  ('kitchen_faucet_replace', 'plumbers_putty', 1),

  ('bath_faucet_replace', 'bath_faucet_standard', 1),
  ('bath_faucet_replace', 'supply_line_braided_12', 2),
  ('bath_faucet_replace', 'plumbers_putty', 1),

  ('kitchen_sink_install_dropin', 'kitchen_sink_dropin', 1),
  ('kitchen_sink_install_dropin', 'kitchen_faucet_standard', 1),
  ('kitchen_sink_install_dropin', 'supply_line_braided_20', 2),
  ('kitchen_sink_install_dropin', 'p_trap_kit', 1),
  ('kitchen_sink_install_dropin', 'shutoff_valve_quarter', 2),
  ('kitchen_sink_install_dropin', 'plumbers_putty', 1),
  ('kitchen_sink_install_dropin', 'caulk_silicone', 1),

  ('kitchen_sink_install_under', 'kitchen_sink_undermount', 1),
  ('kitchen_sink_install_under', 'kitchen_faucet_pullout', 1),
  ('kitchen_sink_install_under', 'supply_line_braided_20', 2),
  ('kitchen_sink_install_under', 'p_trap_kit', 1),
  ('kitchen_sink_install_under', 'shutoff_valve_quarter', 2),
  ('kitchen_sink_install_under', 'caulk_silicone', 2),
  ('kitchen_sink_install_under', 'mounting_hardware', 1),

  ('bath_sink_replace', 'bath_sink_dropin', 1),
  ('bath_sink_replace', 'bath_faucet_standard', 1),
  ('bath_sink_replace', 'supply_line_braided_12', 2),
  ('bath_sink_replace', 'p_trap_kit', 1),
  ('bath_sink_replace', 'plumbers_putty', 1),

  ('vanity_install', 'bath_vanity_24', 1),
  ('vanity_install', 'bath_faucet_standard', 1),
  ('vanity_install', 'supply_line_braided_12', 2),
  ('vanity_install', 'p_trap_kit', 1),
  ('vanity_install', 'shutoff_valve_quarter', 2),
  ('vanity_install', 'caulk_silicone', 1),
  ('vanity_install', 'mounting_hardware', 1),

  -- Showers & tubs
  ('shower_valve_replace', 'shower_valve_pb', 1),
  ('shower_valve_replace', 'solder_lead_free', 1),
  ('shower_valve_replace', 'copper_fitting_half', 4),
  ('shower_valve_replace', 'teflon_tape', 1),

  ('shower_head_replace', 'shower_head_standard', 1),
  ('shower_head_replace', 'teflon_tape', 1),

  ('tub_spout_replace', 'tub_spout_diverter', 1),
  ('tub_spout_replace', 'teflon_tape', 1),
  ('tub_spout_replace', 'caulk_silicone', 1),

  ('tub_shower_combo_install', 'tub_shower_combo', 1),
  ('tub_shower_combo_install', 'shower_valve_pb', 1),
  ('tub_shower_combo_install', 'shower_head_standard', 1),
  ('tub_shower_combo_install', 'tub_spout_diverter', 1),
  ('tub_shower_combo_install', 'p_trap_kit', 1),
  ('tub_shower_combo_install', 'pvc_pipe_2in', 8),
  ('tub_shower_combo_install', 'pvc_fitting_2in', 4),
  ('tub_shower_combo_install', 'abs_cement', 1),
  ('tub_shower_combo_install', 'caulk_silicone', 2),

  ('shower_pan_install', 'shower_pan_36', 1),
  ('shower_pan_install', 'p_trap_kit', 1),
  ('shower_pan_install', 'pvc_pipe_2in', 6),
  ('shower_pan_install', 'pvc_fitting_2in', 3),
  ('shower_pan_install', 'abs_cement', 1),
  ('shower_pan_install', 'caulk_silicone', 1),

  ('bathtub_replace', 'bathtub_standard_60', 1),
  ('bathtub_replace', 'p_trap_kit', 1),
  ('bathtub_replace', 'tub_spout_diverter', 1),
  ('bathtub_replace', 'pvc_pipe_2in', 6),
  ('bathtub_replace', 'pvc_fitting_2in', 3),
  ('bathtub_replace', 'abs_cement', 1),
  ('bathtub_replace', 'caulk_silicone', 2),

  -- Water heaters
  ('water_heater_install_elec', 'water_heater_50gal_electric', 1),
  ('water_heater_install_elec', 'tp_valve', 1),
  ('water_heater_install_elec', 'flex_supply_water', 2),
  ('water_heater_install_elec', 'water_heater_drain_pan', 1),
  ('water_heater_install_elec', 'water_heater_strap_kit', 1),
  ('water_heater_install_elec', 'pipe_dope', 1),

  ('water_heater_install_tnk', 'water_heater_tankless_gas', 1),
  ('water_heater_install_tnk', 'tp_valve', 1),
  ('water_heater_install_tnk', 'flex_supply_water', 2),
  ('water_heater_install_tnk', 'flex_gas_connector', 1),
  ('water_heater_install_tnk', 'gas_shutoff_valve', 1),
  ('water_heater_install_tnk', 'pipe_dope', 1),

  ('water_heater_flush', 'drain_cleaning_consumables', 1),

  ('water_heater_tp_valve', 'tp_valve', 1),
  ('water_heater_tp_valve', 'pipe_dope', 1),

  -- Drains & sewer
  ('drain_snake_sink', 'drain_cleaning_consumables', 1),

  ('drain_snake_main', 'drain_cleaning_consumables', 2),

  ('drain_hydro_jet', 'hydro_jet_use', 1),
  ('drain_hydro_jet', 'drain_cleaning_consumables', 1),

  ('drain_camera_inspect', 'camera_scope_use', 1),

  ('p_trap_replace', 'p_trap_kit', 1),
  ('p_trap_replace', 'pipe_dope', 1),

  ('garbage_disposal_replace', 'garbage_disposal_half', 1),
  ('garbage_disposal_replace', 'electrical_pigtail', 1),
  ('garbage_disposal_replace', 'plumbers_putty', 1),

  -- Water supply
  ('shutoff_valve_replace', 'shutoff_valve_quarter', 1),
  ('shutoff_valve_replace', 'teflon_tape', 1),

  ('whole_house_shutoff', 'ball_valve_three_quarter', 1),
  ('whole_house_shutoff', 'solder_lead_free', 1),
  ('whole_house_shutoff', 'copper_fitting_half', 2),

  ('burst_pipe_repair', 'pipe_clamp_repair', 1),
  ('burst_pipe_repair', 'copper_pipe_half', 3),
  ('burst_pipe_repair', 'copper_fitting_half', 2),
  ('burst_pipe_repair', 'solder_lead_free', 1),

  ('hose_bib_install', 'hose_bib_frost_free', 1),
  ('hose_bib_install', 'solder_lead_free', 1),
  ('hose_bib_install', 'copper_fitting_half', 2),
  ('hose_bib_install', 'caulk_silicone', 1),

  ('water_main_shutoff_replace', 'main_shutoff_valve', 1),
  ('water_main_shutoff_replace', 'solder_lead_free', 1),
  ('water_main_shutoff_replace', 'copper_fitting_half', 2),

  ('pressure_regulator_install', 'pressure_regulator', 1),
  ('pressure_regulator_install', 'solder_lead_free', 1),
  ('pressure_regulator_install', 'copper_fitting_half', 2),

  ('water_hammer_arrestor_inst', 'water_hammer_arrestor', 1),
  ('water_hammer_arrestor_inst', 'teflon_tape', 1),

  -- Gas
  ('gas_line_appliance', 'csst_half', 1),
  ('gas_line_appliance', 'black_iron_fitting_half', 0.25),
  ('gas_line_appliance', 'pipe_strap_pkg', 0.1),
  ('gas_line_appliance', 'gas_leak_detector', 0.1),

  ('gas_shutoff_replace', 'gas_shutoff_valve', 1),
  ('gas_shutoff_replace', 'pipe_dope', 1),
  ('gas_shutoff_replace', 'gas_leak_detector', 1),

  ('gas_leak_test', 'gas_leak_detector', 1),

  -- Drainage & appliance hookups
  ('drain_line_run', 'pvc_pipe_2in', 1),
  ('drain_line_run', 'pvc_fitting_2in', 0.2),
  ('drain_line_run', 'abs_cement', 0.05),
  ('drain_line_run', 'pipe_strap_pkg', 0.1),

  ('washing_machine_box_install', 'washing_machine_box', 1),
  ('washing_machine_box_install', 'washing_machine_hose_pair', 1),
  ('washing_machine_box_install', 'ball_valve_half', 2),
  ('washing_machine_box_install', 'pvc_pipe_2in', 4),
  ('washing_machine_box_install', 'pvc_fitting_2in', 2),

  ('ice_maker_line_install', 'ice_maker_line_kit', 1),
  ('ice_maker_line_install', 'shutoff_valve_quarter', 1),

  ('dishwasher_hookup', 'dishwasher_supply_kit', 1),
  ('dishwasher_hookup', 'dishwasher_drain_hose', 1),
  ('dishwasher_hookup', 'shutoff_valve_quarter', 1),

  -- Specialty installs
  ('water_softener_install', 'water_softener', 1),
  ('water_softener_install', 'pex_three_quarter', 6),
  ('water_softener_install', 'pex_fitting_three_quarter', 4),
  ('water_softener_install', 'ball_valve_three_quarter', 2),

  ('water_filter_install', 'water_filter_whole_house', 1),
  ('water_filter_install', 'pex_three_quarter', 4),
  ('water_filter_install', 'pex_fitting_three_quarter', 4),
  ('water_filter_install', 'ball_valve_three_quarter', 2),

  ('sump_pump_install', 'sump_pump_third_hp', 1),
  ('sump_pump_install', 'pvc_pipe_2in', 6),
  ('sump_pump_install', 'pvc_fitting_2in', 3),
  ('sump_pump_install', 'abs_cement', 1),

  ('ejector_pump_install', 'ejector_pump', 1),
  ('ejector_pump_install', 'pvc_pipe_2in', 8),
  ('ejector_pump_install', 'pvc_fitting_2in', 4),
  ('ejector_pump_install', 'abs_cement', 1),

  ('backflow_preventer_install', 'backflow_preventer', 1),
  ('backflow_preventer_install', 'copper_pipe_half', 4),
  ('backflow_preventer_install', 'copper_fitting_half', 4),
  ('backflow_preventer_install', 'solder_lead_free', 1),

  -- Repairs / misc
  ('pipe_joint_leak_repair', 'copper_fitting_half', 2),
  ('pipe_joint_leak_repair', 'solder_lead_free', 1),
  ('pipe_joint_leak_repair', 'teflon_tape', 1),

  ('washer_hoses_replace', 'washing_machine_hose_pair', 1)
on conflict do nothing;
