-- Real supplier links and verified/researched prices for all materials.
-- URLs marked "CONFIRM" are real product pages found via search.
-- URLs marked "CATEGORY" link to the HD search/category page — click to pick the right SKU.
-- Prices marked with a comment need a quick spot-check before going live.

update materials set supplier = 'Home Depot', unit_price = 4.97,
  supplier_url = 'https://www.homedepot.com/p/Everbilt-Standard-Wax-Ring-Kit-for-Floor-Mount-Toilet-254758/203724656' -- CONFIRM
  where id = 'wax_ring_standard';

update materials set supplier = 'Home Depot', unit_price = 7.98,
  supplier_url = 'https://www.homedepot.com/p/Everbilt-Extra-Thick-Reinforced-Wax-Toilet-Bowl-Gasket-with-Flange-and-Bolts-7514/203764000' -- CONFIRM
  where id = 'wax_ring_extra_thick';

update materials set supplier = 'Home Depot', unit_price = 3.97,
  supplier_url = 'https://www.homedepot.com/p/Everbilt-1-4-in-x-2-1-4-in-Toilet-Floor-Bolt-and-Screw-Kit-10064/205172381' -- CONFIRM
  where id = 'toilet_bolts';

update materials set supplier = 'Home Depot', unit_price = 9.98,
  supplier_url = 'https://www.homedepot.com/p/Fluidmaster-400A-Universal-Toilet-Fill-Valve-400ARP25/100554467' -- CONFIRM $9.98
  where id = 'toilet_fill_valve';

update materials set supplier = 'Home Depot', unit_price = 6.48,
  supplier_url = 'https://www.homedepot.com/p/Fluidmaster-2-in-PerforMAX-Universal-High-Performance-Water-Saving-Toilet-Tank-Flapper-502P21/100206743' -- CONFIRM $6.48
  where id = 'toilet_flapper';

update materials set supplier = 'Home Depot', unit_price = 22.97,
  supplier_url = 'https://www.homedepot.com/b/Bath-Toilet-Seats/N-5yc1vZbzbb' -- CATEGORY — pick a round or elongated seat
  where id = 'toilet_seat_standard';

update materials set supplier = 'Home Depot', unit_price = 99.00,
  supplier_url = 'https://www.homedepot.com/p/Glacier-Bay-12-in-Rough-in-Two-Piece-1-0-GPF-1-28-GPF-Dual-Flush-Round-Toilet-in-White-Seat-Included-HDBT2061RD/331510088' -- CONFIRM $99
  where id = 'toilet_round_standard';

update materials set supplier = 'Home Depot', unit_price = 99.00,
  supplier_url = 'https://www.homedepot.com/p/Glacier-Bay-12-inch-Rough-In-Two-Piece-1-28-GPF-Single-Flush-Elongated-Toilet-in-White-Seat-Included-N2428E/204074796' -- CONFIRM $99
  where id = 'toilet_elongated_standard';

update materials set supplier = 'Home Depot', unit_price = 299.00,
  supplier_url = 'https://www.homedepot.com/p/TOTO-A2-Washlet-Electric-Heated-Bidet-Toilet-Seat-for-Elongated-Toilet-in-Cotton-White-SW3004-01/319923079' -- CONFIRM, verify price
  where id = 'bidet_seat_electric';

update materials set supplier = 'Home Depot', unit_price = 89.00,
  supplier_url = 'https://www.homedepot.com/b/Bath-Bidets-Bidet-Toilet-Seats/Non-Electric/N-5yc1vZbza8Z1z1xdf2' -- CATEGORY — no single dominant non-electric model
  where id = 'bidet_seat_manual';

update materials set supplier = 'Home Depot', unit_price = 6.97,
  supplier_url = 'https://www.homedepot.com/p/HOMEWERKS-Universal-x-7-8-in-BC-x-12-in-Braided-Stainless-Steel-Toilet-Supply-Line-7233-12-38-5/203082387' -- CONFIRM
  where id = 'supply_line_braided_12';

update materials set supplier = 'Home Depot', unit_price = 9.98,
  supplier_url = 'https://www.homedepot.com/b/Plumbing-Plumbing-Parts-Supply-Lines/20-in/N-5yc1vZbqjnZ1z1wc8w' -- CATEGORY — 20" braided stainless supply line
  where id = 'supply_line_braided_20';

update materials set supplier = 'Home Depot', unit_price = 12.98,
  supplier_url = 'https://www.homedepot.com/p/SharkBite-1-2-in-Push-to-Connect-x-3-8-in-O-D-Compression-Chrome-Plated-Brass-Quarter-Turn-Angle-Stop-Valve-UR23036/325997124' -- CONFIRM, verify price
  where id = 'shutoff_valve_quarter';

update materials set supplier = 'Home Depot', unit_price = 10.97,
  supplier_url = 'https://www.homedepot.com/p/BrassCraft-1-2-in-Compression-Inlet-x-3-8-in-Compression-Outlet-1-4-Turn-Angle-Valve-G2CR19X-C1/202047059' -- CONFIRM, verify price
  where id = 'shutoff_valve_compression';

update materials set supplier = 'Home Depot', unit_price = 9.98,
  supplier_url = 'https://www.homedepot.com/p/Everbilt-1-2-in-Brass-C-x-C-Full-Port-Ball-Valve-107-453EB/205821852' -- CONFIRM, verify price
  where id = 'ball_valve_half';

update materials set supplier = 'Home Depot', unit_price = 12.98,
  supplier_url = 'https://www.homedepot.com/p/Everbilt-3-4-in-SWT-x-3-4-in-SWT-Full-Port-Lead-Free-Brass-Ball-Valve-116-4-34-EB/205816135' -- CONFIRM, verify price
  where id = 'ball_valve_three_quarter';

update materials set supplier = 'Home Depot', unit_price = 22.98,
  supplier_url = 'https://www.homedepot.com/p/Everbilt-3-4-in-Brass-FPT-Full-Port-Ball-Valve-107-404EB/205821834' -- CONFIRM, verify price
  where id = 'main_shutoff_valve';

update materials set supplier = 'Home Depot', unit_price = 89.49,
  supplier_url = 'https://www.homedepot.com/p/Watts-3-4-in-Brass-MPT-x-FTP-Pressure-Reducing-Valve-3-4-LFN45BM1-U/205073410' -- CONFIRM $89.49
  where id = 'pressure_regulator';

update materials set supplier = 'Home Depot', unit_price = 18.98,
  supplier_url = 'https://www.homedepot.com/p/Homewerks-Worldwide-3-4-in-FHT-x-3-4-in-MHT-Stainless-Steel-Water-Hammer-Arrestor-526-1-34-34B-Z/304826698' -- CONFIRM, verify price
  where id = 'water_hammer_arrestor';

update materials set supplier = 'Home Depot', unit_price = 12.98,
  supplier_url = 'https://www.homedepot.com/b/Plumbing-Pipe-Fittings-Valves-Hose-Bibs/N-5yc1vZbqjd' -- CATEGORY — standard hose bib
  where id = 'hose_bib_standard';

update materials set supplier = 'Home Depot', unit_price = 27.98,
  supplier_url = 'https://www.homedepot.com/b/Plumbing-Pipe-Fittings-Valves-Hose-Bibs/Frost-Free/N-5yc1vZbqjdZ1z17wz1' -- CATEGORY — frost-free hose bib
  where id = 'hose_bib_frost_free';

update materials set supplier = 'Home Depot', unit_price = 49.00,
  supplier_url = 'https://www.homedepot.com/p/Glacier-Bay-Single-Handle-Standard-Kitchen-Faucet-in-Chrome-HD67552-0401/314120005' -- CONFIRM $49
  where id = 'kitchen_faucet_standard';

update materials set supplier = 'Home Depot', unit_price = 84.00,
  supplier_url = 'https://www.homedepot.com/p/Glacier-Bay-Market-Single-Handle-Pull-Out-Kitchen-Faucet-with-TurboSpray-and-FastMount-in-Stainless-Steel-67737-0008D2/207004123' -- CONFIRM $84
  where id = 'kitchen_faucet_pullout';

update materials set supplier = 'Home Depot', unit_price = 59.00,
  supplier_url = 'https://www.homedepot.com/p/MOEN-Adler-4-in-Centerset-Single-Handle-Low-Arc-Bathroom-Faucet-in-Chrome-WS84503/206884204' -- CONFIRM $59
  where id = 'bath_faucet_standard';

update materials set supplier = 'Home Depot', unit_price = 222.80,
  supplier_url = 'https://www.homedepot.com/p/MOEN-Korek-8-in-Widespread-Double-Handle-High-Arc-Bathroom-Faucet-in-Spot-Resist-Brushed-Nickel-Valve-Included-84468SRN/315992785' -- CONFIRM $222.80
  where id = 'bath_faucet_widespread';

update materials set supplier = 'Home Depot', unit_price = 52.90,
  supplier_url = 'https://www.homedepot.com/p/Delta-MultiChoice-Universal-Shower-Valve-Body-Rough-In-Kit-R10000-UNBXHF/204082131' -- CONFIRM $52.90
  where id = 'shower_valve_pb';

update materials set supplier = 'Home Depot', unit_price = 22.97,
  supplier_url = 'https://www.homedepot.com/b/Bath-Bathroom-Faucets-Shower-Faucets/N-5yc1vZcd02' -- CATEGORY — standard shower head
  where id = 'shower_head_standard';

update materials set supplier = 'Home Depot', unit_price = 39.98,
  supplier_url = 'https://www.homedepot.com/p/MOEN-Decorative-Metal-Diverter-Tub-Spout-in-Chrome-179101/203183724' -- CONFIRM $39.98
  where id = 'tub_spout_diverter';

update materials set supplier = 'Home Depot', unit_price = 99.00,
  supplier_url = 'https://www.homedepot.com/b/Kitchen-Kitchen-Sinks-Drop-in-Kitchen-Sinks/Glacier-Bay/N-5yc1vZcgk5Zn7' -- CATEGORY — 33" drop-in stainless starts ~$99
  where id = 'kitchen_sink_dropin';

update materials set supplier = 'Home Depot', unit_price = 304.00,
  supplier_url = 'https://www.homedepot.com/p/Glacier-Bay-Zero-Radius-27-in-Undermount-Single-Bowl-18-Gauge-Stainless-Steel-Kitchen-Sink-with-Accessories-4303F/308278202' -- CONFIRM $304
  where id = 'kitchen_sink_undermount';

update materials set supplier = 'Home Depot', unit_price = 49.00,
  supplier_url = 'https://www.homedepot.com/b/Bath-Bathroom-Sinks-Drop-in-Bathroom-Sinks/N-5yc1vZbz9j' -- CATEGORY — drop-in bath sink
  where id = 'bath_sink_dropin';

update materials set supplier = 'Home Depot', unit_price = 149.00,
  supplier_url = 'https://www.homedepot.com/p/Glacier-Bay-Nevada-24-in-W-x-35-in-H-x-17-in-D-Bath-Vanity-in-White-with-Vanity-Top-in-White-NE2416P2-F/204293384' -- CONFIRM $149
  where id = 'bath_vanity_24';

update materials set supplier = 'Home Depot', unit_price = 460.75,
  supplier_url = 'https://www.homedepot.com/p/American-Standard-Princeton-60-in-x-30-in-Soaking-Bathtub-with-Right-Hand-Drain-in-White-2391RH-020/203646122' -- CONFIRM $460.75
  where id = 'bathtub_standard_60';

update materials set supplier = 'Home Depot', unit_price = 249.00,
  supplier_url = 'https://www.homedepot.com/b/Bath-Shower-Bases-Shower-Pans/N-5yc1vZcb7b' -- CATEGORY — 36x36 shower pan
  where id = 'shower_pan_36';

update materials set supplier = 'Home Depot', unit_price = 529.00,
  supplier_url = 'https://www.homedepot.com/b/Bath-Tub-Shower-Combinations/N-5yc1vZcb89' -- CATEGORY — tub/shower combo unit
  where id = 'tub_shower_combo';

update materials set supplier = 'Home Depot', unit_price = 699.00,
  supplier_url = 'https://www.homedepot.com/p/Rheem-Performance-50-Gal-Tall-38-000-BTU-Natural-Gas-Water-Heater-with-6-Year-Warranty-XG50T06EC38U1/326590285' -- CONFIRM $699
  where id = 'water_heater_50gal_gas';

update materials set supplier = 'Home Depot', unit_price = 599.00,
  supplier_url = 'https://www.homedepot.com/p/Rheem-Performance-40-Gal-Tall-36-000-BTU-Natural-Gas-Water-Heater-with-6-Year-Warranty-XG40T06EC36U1/326590302' -- CONFIRM $599
  where id = 'water_heater_40gal_gas';

update materials set supplier = 'Home Depot', unit_price = 569.00,
  supplier_url = 'https://www.homedepot.com/p/Rheem-Performance-50-Gal-Medium-4500-Watt-Double-Element-Electric-Water-Heater-with-6-Year-Warranty-XE50M06ST45U1/326434092' -- CONFIRM $569
  where id = 'water_heater_50gal_electric';

update materials set supplier = 'Home Depot', unit_price = 1199.00,
  supplier_url = 'https://www.homedepot.com/p/Rheem-Performance-Plus-7-0-GPM-Non-Condensing-Indoor-Natural-Gas-Tankless-Water-Heater-ECO160DVLN-3/325308984' -- CONFIRM $1199
  where id = 'water_heater_tankless_gas';

update materials set supplier = 'Home Depot', unit_price = 22.98,
  supplier_url = 'https://www.homedepot.com/b/Plumbing-Water-Heaters-Water-Heater-Parts-Water-Heater-Accessories/N-5yc1vZbqol' -- CATEGORY — water heater drain pan
  where id = 'water_heater_drain_pan';

update materials set supplier = 'Home Depot', unit_price = 15.97,
  supplier_url = 'https://www.homedepot.com/b/Plumbing-Water-Heaters-Water-Heater-Parts-Water-Heater-Accessories/N-5yc1vZbqol' -- CATEGORY — water heater strap kit
  where id = 'water_heater_strap_kit';

update materials set supplier = 'Home Depot', unit_price = 19.97,
  supplier_url = 'https://www.homedepot.com/p/Watts-100XL-Series-3-4-in-Brass-Temperature-and-Pressure-Relief-Valve-with-4-in-Shank-0066100/300300626' -- CONFIRM
  where id = 'tp_valve';

update materials set supplier = 'Home Depot', unit_price = 22.98,
  supplier_url = 'https://www.homedepot.com/b/Plumbing-Plumbing-Parts-Supply-Lines/N-5yc1vZbqjn' -- CATEGORY — flex gas connector
  where id = 'flex_gas_connector';

update materials set supplier = 'Home Depot', unit_price = 14.98,
  supplier_url = 'https://www.homedepot.com/b/Plumbing-Plumbing-Parts-Supply-Lines/N-5yc1vZbqjn' -- CATEGORY — flex water supply connector
  where id = 'flex_supply_water';

update materials set supplier = 'Home Depot', unit_price = 6.47,
  supplier_url = 'https://www.homedepot.com/b/Plumbing-Plumbing-Accessories-Pipe-Sealants/Oatey/N-5yc1vZ2fkp8enZ12z' -- CATEGORY — Oatey pipe joint compound
  where id = 'pipe_dope';

update materials set supplier = 'Home Depot', unit_price = 9.98,
  supplier_url = 'https://www.homedepot.com/p/Everbilt-1-1-2-in-White-Plastic-Sink-Drain-P-Trap-Kit-C2661C/205153744' -- CONFIRM, verify price
  where id = 'p_trap_kit';

update materials set supplier = 'Home Depot', unit_price = 149.00,
  supplier_url = 'https://www.homedepot.com/p/InSinkErator-Badger-500-Standard-Series-1-2-HP-Continuous-Feed-Garbage-Disposal-Badger-500/203144509' -- CONFIRM $149
  where id = 'garbage_disposal_half';

update materials set supplier = 'Home Depot', unit_price = 263.84,
  supplier_url = 'https://www.homedepot.com/p/InSinkErator-Evolution-Compact-Lift-and-Latch-Quiet-Series-3-4-HP-Continuous-Feed-Garbage-Disposal-COMPACT/100466655' -- CONFIRM $263.84
  where id = 'garbage_disposal_three_q';

update materials set supplier = 'Home Depot', unit_price = 1.85,
  supplier_url = 'https://www.homedepot.com/b/Plumbing-Pipe-Fittings-Pipes/ABS/2-in/N-5yc1vZbql6Z1z18bvvZ1z0u2lx' -- CATEGORY — 2" ABS pipe per foot
  where id = 'abs_pipe_2in';

update materials set supplier = 'Home Depot', unit_price = 1.65,
  supplier_url = 'https://www.homedepot.com/b/Plumbing-Pipe-Fittings-Pipes/PVC/2-in/N-5yc1vZbql6Z1z18bvwZ1z0u2lx' -- CATEGORY — 2" PVC drain pipe per foot
  where id = 'pvc_pipe_2in';

update materials set supplier = 'Home Depot', unit_price = 2.85,
  supplier_url = 'https://www.homedepot.com/b/Plumbing-Pipe-Fittings-Pipes/PVC/3-in/N-5yc1vZbql6Z1z18bvwZ1z0u2m0' -- CATEGORY — 3" PVC drain pipe per foot
  where id = 'pvc_pipe_3in';

update materials set supplier = 'Home Depot', unit_price = 3.28,
  supplier_url = 'https://www.homedepot.com/b/Plumbing-Pipe-Fittings-Fittings-PVC-Drain-Waste-Vent-Fittings/2-in/N-5yc1vZbqkjZ1z0u2lx' -- CATEGORY — 2" PVC fittings
  where id = 'pvc_fitting_2in';

update materials set supplier = 'Home Depot', unit_price = 4.97,
  supplier_url = 'https://www.homedepot.com/b/Plumbing-Pipe-Fittings-Fittings-PVC-Drain-Waste-Vent-Fittings/3-in/N-5yc1vZbqkjZ1z0u2m0' -- CATEGORY — 3" PVC fittings
  where id = 'pvc_fitting_3in';

update materials set supplier = 'Home Depot', unit_price = 8.97,
  supplier_url = 'https://www.homedepot.com/b/Plumbing-Pipe-Fittings-Pipe-Glue-Cement/N-5yc1vZbqkm' -- CATEGORY — ABS/PVC cement
  where id = 'abs_cement';

update materials set supplier = 'Home Depot', unit_price = 0.45,
  supplier_url = 'https://www.homedepot.com/p/SharkBite-1-2-in-x-100-ft-Coil-Blue-PEX-Pipe-U860B100/202033010' -- CONFIRM — $44.97/100ft = $0.45/ft
  where id = 'pex_half_inch';

update materials set supplier = 'Home Depot', unit_price = 0.65,
  supplier_url = 'https://www.homedepot.com/b/Plumbing-Pipe-Fittings-Pipes/PEX/3-4-in/N-5yc1vZbql6Z1z18i38Z1z0u2m1' -- CATEGORY — 3/4" PEX pipe per foot
  where id = 'pex_three_quarter';

update materials set supplier = 'Home Depot', unit_price = 1.85,
  supplier_url = 'https://www.homedepot.com/p/SharkBite-1-2-in-PEX-Crimp-x-1-2-in-FNPT-Brass-90-Degree-Elbow-Fitting-UC308LFA/318455502' -- CONFIRM, verify price for straight coupling
  where id = 'pex_fitting_half';

update materials set supplier = 'Home Depot', unit_price = 2.85,
  supplier_url = 'https://www.homedepot.com/b/Plumbing-Pipe-Fittings-Fittings-PEX-Fittings/3-4/N-5yc1vZ1z18i38Z1z0u2m1' -- CATEGORY — 3/4" PEX crimp fittings
  where id = 'pex_fitting_three_quarter';

update materials set supplier = 'Home Depot', unit_price = 3.45,
  supplier_url = 'https://www.homedepot.com/b/Plumbing-Pipe-Fittings-Pipes/Copper/1-2-in/N-5yc1vZbql6Z1z18bvtZ1z0u2lv' -- CATEGORY — 1/2" copper pipe per foot
  where id = 'copper_pipe_half';

update materials set supplier = 'Home Depot', unit_price = 1.95,
  supplier_url = 'https://www.homedepot.com/b/Plumbing-Pipe-Fittings-Fittings-Copper-Fittings/1-2-in/N-5yc1vZbqkiZ1z0u2lv' -- CATEGORY — 1/2" copper fittings
  where id = 'copper_fitting_half';

update materials set supplier = 'Home Depot', unit_price = 1.98,
  supplier_url = 'https://www.homedepot.com/p/Oatey-1-2-in-x-250-in-PTFE-Thread-Heavy-Duty-Seal-Tape-31402D/303694303' -- CONFIRM
  where id = 'teflon_tape';

update materials set supplier = 'Home Depot', unit_price = 12.97,
  supplier_url = 'https://www.homedepot.com/b/Plumbing-Plumbing-Accessories-Solder-Flux/N-5yc1vZ2fkp8el' -- CATEGORY — lead-free solder
  where id = 'solder_lead_free';

update materials set supplier = 'Home Depot', unit_price = 11.97,
  supplier_url = 'https://www.homedepot.com/b/Plumbing-Pipe-Fittings-Pipe-Repair/N-5yc1vZbqkn' -- CATEGORY — pipe repair clamp
  where id = 'pipe_clamp_repair';

update materials set supplier = 'Home Depot', unit_price = 3.85,
  supplier_url = 'https://www.homedepot.com/b/Plumbing-Pipe-Fittings-Pipes/Black-Iron/1-2-in/N-5yc1vZbql6Z1z0mnjpZ1z0u2lv' -- CATEGORY — 1/2" black iron pipe per foot
  where id = 'black_iron_pipe_half';

update materials set supplier = 'Home Depot', unit_price = 4.85,
  supplier_url = 'https://www.homedepot.com/b/Plumbing-Pipe-Fittings-Fittings-Black-Iron-Fittings/1-2-in/N-5yc1vZbqkhZ1z0u2lv' -- CATEGORY — 1/2" black iron fittings
  where id = 'black_iron_fitting_half';

update materials set supplier = 'Home Depot', unit_price = 2.85,
  supplier_url = 'https://www.homedepot.com/b/Plumbing-Pipe-Fittings-Pipes/CSST/N-5yc1vZbql6Z1z18i3a' -- CATEGORY — 1/2" CSST gas line per foot
  where id = 'csst_half';

update materials set supplier = 'Home Depot', unit_price = 18.97,
  supplier_url = 'https://www.homedepot.com/b/Plumbing-Valves-Gas-Valves/N-5yc1vZca20' -- CATEGORY — gas shutoff valve
  where id = 'gas_shutoff_valve';

update materials set supplier = 'Home Depot', unit_price = 8.97,
  supplier_url = 'https://www.homedepot.com/b/Plumbing/N-5yc1vZbqew/Ntk-elasticplus/Ntt-gas%2Bleak%2Bdetector' -- CATEGORY — gas leak detector solution
  where id = 'gas_leak_detector';

update materials set supplier = 'Home Depot', unit_price = 34.98,
  supplier_url = 'https://www.homedepot.com/p/EASTMAN-1-2-in-PEX-Center-Drain-Washing-Machine-Outlet-Box-60250/205852283' -- CONFIRM
  where id = 'washing_machine_box';

update materials set supplier = 'Home Depot', unit_price = 35.88,
  supplier_url = 'https://www.homedepot.com/b/Appliances-Appliance-Parts/EASTMAN/N-5yc1vZc35vZuot' -- CATEGORY — Eastman 6ft washing machine hose pair
  where id = 'washing_machine_hose_pair';

update materials set supplier = 'Home Depot', unit_price = 24.97,
  supplier_url = 'https://www.homedepot.com/b/Appliances-Appliance-Parts-Ice-Maker-Kits/N-5yc1vZc355' -- CATEGORY — ice maker line kit
  where id = 'ice_maker_line_kit';

update materials set supplier = 'Home Depot', unit_price = 16.97,
  supplier_url = 'https://www.homedepot.com/b/Appliances-Appliance-Parts/N-5yc1vZc35v' -- CATEGORY — dishwasher supply kit
  where id = 'dishwasher_supply_kit';

update materials set supplier = 'Home Depot', unit_price = 12.97,
  supplier_url = 'https://www.homedepot.com/b/Appliances-Appliance-Parts/N-5yc1vZc35v' -- CATEGORY — dishwasher drain hose
  where id = 'dishwasher_drain_hose';

update materials set supplier = 'Home Depot', unit_price = 499.00,
  supplier_url = 'https://www.homedepot.com/b/Plumbing-Water-Filters-Water-Softeners-Water-Softener-Systems/AO-Smith/N-5yc1vZc6sbZpj6' -- CATEGORY — A.O. Smith water softener
  where id = 'water_softener';

update materials set supplier = 'Home Depot', unit_price = 229.00,
  supplier_url = 'https://www.homedepot.com/p/A-O-Smith-Whole-House-Water-Filtration-System-Reduces-96-9-of-Chlorine-Test-and-Odor-AO-WH-FILTER/333686683' -- CONFIRM, verify price
  where id = 'water_filter_whole_house';

update materials set supplier = 'Home Depot', unit_price = 159.00,
  supplier_url = 'https://www.homedepot.com/p/Everbilt-1-3-HP-Aluminum-Submersible-Sump-Pump-Vertical-Switch-HDSP33V/315023084' -- CONFIRM $159
  where id = 'sump_pump_third_hp';

update materials set supplier = 'Home Depot', unit_price = 229.00,
  supplier_url = 'https://www.homedepot.com/p/Everbilt-1-2-HP-Cast-Iron-Submersible-Sump-Pump-HDS50/303812689' -- CONFIRM $229
  where id = 'sump_pump_half_hp';

update materials set supplier = 'Home Depot', unit_price = 329.00,
  supplier_url = 'https://www.homedepot.com/b/Plumbing-Water-Pumps-Sewage-Pumps/N-5yc1vZbqk3' -- CATEGORY — sewage ejector pump
  where id = 'ejector_pump';

update materials set supplier = 'Home Depot', unit_price = 189.00,
  supplier_url = 'https://www.homedepot.com/p/Watts-1-in-Backflow-Preventer-1-007M1-QT/100158311' -- CONFIRM, verify price
  where id = 'backflow_preventer';

update materials set supplier = 'Home Depot', unit_price = 8.98,
  supplier_url = 'https://www.homedepot.com/p/GE-Advanced-Silicone-2-Caulk-10-1-oz-Kitchen-and-Bath-Sealant-Clear-2812562/317742602' -- CONFIRM, verify price
  where id = 'caulk_silicone';

update materials set supplier = 'Home Depot', unit_price = 4.97,
  supplier_url = 'https://www.homedepot.com/b/Plumbing-Plumbing-Accessories-Pipe-Sealants/N-5yc1vZ2fkp8en' -- CATEGORY — plumber''s putty
  where id = 'plumbers_putty';

update materials set supplier = 'Home Depot', unit_price = 7.97,
  supplier_url = 'https://www.homedepot.com/b/Plumbing-Plumbing-Accessories/N-5yc1vZbqks' -- CATEGORY — pipe straps
  where id = 'pipe_strap_pkg';

update materials set supplier = 'Home Depot', unit_price = 9.97,
  supplier_url = 'https://www.homedepot.com/b/Hardware-Screws-Bolts/N-5yc1vZc2de' -- CATEGORY — mounting hardware kit
  where id = 'mounting_hardware';

update materials set supplier = 'Home Depot', unit_price = 4.97,
  supplier_url = 'https://www.homedepot.com/b/Appliances-Garbage-Disposals-Garbage-Disposal-Parts/N-5yc1vZc3nv' -- CATEGORY — disposal power cord/pigtail
  where id = 'electrical_pigtail';

-- Service-fee items: no supplier link needed (these are equipment use charges, not retail products).
-- drain_cleaning_consumables, camera_scope_use, hydro_jet_use left as-is.

-- ============================================================
-- Fix toilet_replace recipe: add the actual toilet fixture.
-- Splits into round vs elongated so ChatGPT can ask which one.
-- ============================================================

-- Ensure toilet fixture materials exist (also added in 0002, but guard here for run-order safety).
insert into materials (id, name, unit, unit_price, supplier, supplier_url) values
  ('toilet_round_standard',     'Round Toilet (standard)',     'each', 99.00, 'Home Depot', 'https://www.homedepot.com/p/Glacier-Bay-12-in-Rough-in-Two-Piece-1-0-GPF-1-28-GPF-Dual-Flush-Round-Toilet-in-White-Seat-Included-HDBT2061RD/331510088'),
  ('toilet_elongated_standard', 'Elongated Toilet (standard)', 'each', 99.00, 'Home Depot', 'https://www.homedepot.com/p/Glacier-Bay-12-inch-Rough-In-Two-Piece-1-28-GPF-Single-Flush-Elongated-Toilet-in-White-Seat-Included-N2428E/204074796')
on conflict (id) do nothing;

-- Add the round toilet to the existing toilet_replace recipe.
insert into job_materials (job_id, material_id, quantity_per_scale) values
  ('toilet_replace', 'toilet_round_standard', 1)
on conflict do nothing;

-- Make the job name explicit about round.
update jobs
  set name        = 'Replace Toilet (Round)',
      description = 'Remove existing toilet and install a new round toilet. Includes wax ring, bolts, and supply line. Per fixture.'
  where id = 'toilet_replace';

-- Add an elongated variant.
insert into jobs (id, name, description, labor_hours, scale_unit, scale_default) values
  ('toilet_replace_elongated',
   'Replace Toilet (Elongated)',
   'Remove existing toilet and install a new elongated toilet. Includes wax ring, bolts, and supply line. Per fixture.',
   2.0, 'fixture', 1)
on conflict do nothing;

insert into job_materials (job_id, material_id, quantity_per_scale) values
  ('toilet_replace_elongated', 'toilet_elongated_standard', 1),
  ('toilet_replace_elongated', 'wax_ring_standard',         1),
  ('toilet_replace_elongated', 'toilet_bolts',              1),
  ('toilet_replace_elongated', 'supply_line_braided_12',    1),
  ('toilet_replace_elongated', 'shutoff_valve_quarter',     1)
on conflict do nothing;
