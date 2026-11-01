// GENERATED FILE — do not hand edit.
// Source: EasyBid construction template review catalog.
export const constructionCatalog = {
  "metadata": {
    "name": "EasyBid Residential Construction Template Review Catalog",
    "version": "0.9.0-review",
    "pricing_as_of": "2026-08-09",
    "status": "REVIEW_ONLY_NOT_APPROVED_FOR_PRODUCTION",
    "currency": "USD"
  },
  "labor_roles": [
    {
      "id": "laborer",
      "name": "General Laborer",
      "billing_rate_multiplier": 0.72
    },
    {
      "id": "general",
      "name": "General Remodeling Crew",
      "billing_rate_multiplier": 1
    },
    {
      "id": "carpenter",
      "name": "Carpenter",
      "billing_rate_multiplier": 1.05
    },
    {
      "id": "finish_carpenter",
      "name": "Finish Carpenter",
      "billing_rate_multiplier": 1.12
    },
    {
      "id": "drywall",
      "name": "Drywall Installer/Finisher",
      "billing_rate_multiplier": 0.95
    },
    {
      "id": "painter",
      "name": "Painter",
      "billing_rate_multiplier": 0.9
    },
    {
      "id": "flooring",
      "name": "Flooring Installer",
      "billing_rate_multiplier": 0.98
    },
    {
      "id": "tile",
      "name": "Tile Setter",
      "billing_rate_multiplier": 1.08
    },
    {
      "id": "cabinet",
      "name": "Cabinet Installer",
      "billing_rate_multiplier": 1.1
    },
    {
      "id": "plumber",
      "name": "Plumber",
      "billing_rate_multiplier": 1.22
    },
    {
      "id": "electrician",
      "name": "Electrician",
      "billing_rate_multiplier": 1.25
    },
    {
      "id": "hvac",
      "name": "HVAC Technician",
      "billing_rate_multiplier": 1.25
    },
    {
      "id": "roofer",
      "name": "Roofer",
      "billing_rate_multiplier": 1.05
    },
    {
      "id": "siding",
      "name": "Siding Installer",
      "billing_rate_multiplier": 1
    },
    {
      "id": "concrete",
      "name": "Concrete/Masonry Crew",
      "billing_rate_multiplier": 1.02
    },
    {
      "id": "project_manager",
      "name": "Project Manager",
      "billing_rate_multiplier": 1.2
    }
  ],
  "assemblies": [
    {
      "id": "site_protection_basic",
      "trade": "general_conditions",
      "name": "Protect occupied work area",
      "description": "Protect occupied work area. Quantity is measured per job.",
      "unit": "job",
      "labor_role_id": "general",
      "crew_hours_per_unit": {
        "base": 5
      },
      "national_seed_material_cost_per_unit": {
        "base": 175
      },
      "equipment_cost_per_unit_base": 25,
      "default_waste_percent": 5,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal residential access and one mobilization are included.",
      "default_exclusions": "Engineering, hazardous-material remediation, bonds, and unusual insurance requirements.",
      "confidence": "medium"
    },
    {
      "id": "mobilization_small",
      "trade": "general_conditions",
      "name": "Small project mobilization",
      "description": "Small project mobilization. Quantity is measured per job.",
      "unit": "job",
      "labor_role_id": "general",
      "crew_hours_per_unit": {
        "base": 3
      },
      "national_seed_material_cost_per_unit": {
        "base": 100
      },
      "equipment_cost_per_unit_base": 75,
      "default_waste_percent": 0,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal residential access and one mobilization are included.",
      "default_exclusions": "Engineering, hazardous-material remediation, bonds, and unusual insurance requirements.",
      "confidence": "medium"
    },
    {
      "id": "mobilization_large",
      "trade": "general_conditions",
      "name": "Large remodel mobilization",
      "description": "Large remodel mobilization. Quantity is measured per job.",
      "unit": "job",
      "labor_role_id": "general",
      "crew_hours_per_unit": {
        "base": 14
      },
      "national_seed_material_cost_per_unit": {
        "base": 650
      },
      "equipment_cost_per_unit_base": 250,
      "default_waste_percent": 0,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal residential access and one mobilization are included.",
      "default_exclusions": "Engineering, hazardous-material remediation, bonds, and unusual insurance requirements.",
      "confidence": "medium"
    },
    {
      "id": "temporary_dust_wall",
      "trade": "general_conditions",
      "name": "Temporary dust partition",
      "description": "Temporary dust partition. Quantity is measured per lf.",
      "unit": "lf",
      "labor_role_id": "general",
      "crew_hours_per_unit": {
        "base": 0.25
      },
      "national_seed_material_cost_per_unit": {
        "base": 8
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 8,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal residential access and one mobilization are included.",
      "default_exclusions": "Engineering, hazardous-material remediation, bonds, and unusual insurance requirements.",
      "confidence": "medium"
    },
    {
      "id": "floor_protection",
      "trade": "general_conditions",
      "name": "Protect finished flooring",
      "description": "Protect finished flooring. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "general",
      "crew_hours_per_unit": {
        "base": 0.03
      },
      "national_seed_material_cost_per_unit": {
        "base": 0.75
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal residential access and one mobilization are included.",
      "default_exclusions": "Engineering, hazardous-material remediation, bonds, and unusual insurance requirements.",
      "confidence": "medium"
    },
    {
      "id": "daily_cleanup",
      "trade": "general_conditions",
      "name": "Daily cleanup and material organization",
      "description": "Daily cleanup and material organization. Quantity is measured per day.",
      "unit": "day",
      "labor_role_id": "general",
      "crew_hours_per_unit": {
        "base": 1.25
      },
      "national_seed_material_cost_per_unit": {
        "base": 25
      },
      "equipment_cost_per_unit_base": 15,
      "default_waste_percent": 0,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal residential access and one mobilization are included.",
      "default_exclusions": "Engineering, hazardous-material remediation, bonds, and unusual insurance requirements.",
      "confidence": "medium"
    },
    {
      "id": "final_cleanup",
      "trade": "general_conditions",
      "name": "Final construction cleanup",
      "description": "Final construction cleanup. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "general",
      "crew_hours_per_unit": {
        "base": 0.03
      },
      "national_seed_material_cost_per_unit": {
        "base": 0.18
      },
      "equipment_cost_per_unit_base": 10,
      "default_waste_percent": 0,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal residential access and one mobilization are included.",
      "default_exclusions": "Engineering, hazardous-material remediation, bonds, and unusual insurance requirements.",
      "confidence": "medium"
    },
    {
      "id": "permit_allowance_minor",
      "trade": "general_conditions",
      "name": "Minor permit and inspection allowance",
      "description": "Minor permit and inspection allowance. Quantity is measured per allowance.",
      "unit": "allowance",
      "labor_role_id": "general",
      "crew_hours_per_unit": {
        "base": 2
      },
      "national_seed_material_cost_per_unit": {
        "base": 350
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 0,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal residential access and one mobilization are included.",
      "default_exclusions": "Engineering, hazardous-material remediation, bonds, and unusual insurance requirements.",
      "confidence": "low"
    },
    {
      "id": "permit_allowance_major",
      "trade": "general_conditions",
      "name": "Major remodel permit allowance",
      "description": "Major remodel permit allowance. Quantity is measured per allowance.",
      "unit": "allowance",
      "labor_role_id": "general",
      "crew_hours_per_unit": {
        "base": 6
      },
      "national_seed_material_cost_per_unit": {
        "base": 2500
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 0,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal residential access and one mobilization are included.",
      "default_exclusions": "Engineering, hazardous-material remediation, bonds, and unusual insurance requirements.",
      "confidence": "low"
    },
    {
      "id": "project_management",
      "trade": "general_conditions",
      "name": "Project management and coordination",
      "description": "Project management and coordination. Quantity is measured per week.",
      "unit": "week",
      "labor_role_id": "general",
      "crew_hours_per_unit": {
        "base": 4
      },
      "national_seed_material_cost_per_unit": {
        "base": 25
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 0,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal residential access and one mobilization are included.",
      "default_exclusions": "Engineering, hazardous-material remediation, bonds, and unusual insurance requirements.",
      "confidence": "medium"
    },
    {
      "id": "dumpster_small",
      "trade": "general_conditions",
      "name": "Small dumpster and disposal allowance",
      "description": "Small dumpster and disposal allowance. Quantity is measured per ea.",
      "unit": "ea",
      "labor_role_id": "general",
      "crew_hours_per_unit": {
        "base": 2
      },
      "national_seed_material_cost_per_unit": {
        "base": 550
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 0,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal residential access and one mobilization are included.",
      "default_exclusions": "Engineering, hazardous-material remediation, bonds, and unusual insurance requirements.",
      "confidence": "medium"
    },
    {
      "id": "dumpster_large",
      "trade": "general_conditions",
      "name": "Large dumpster and disposal allowance",
      "description": "Large dumpster and disposal allowance. Quantity is measured per ea.",
      "unit": "ea",
      "labor_role_id": "general",
      "crew_hours_per_unit": {
        "base": 3
      },
      "national_seed_material_cost_per_unit": {
        "base": 950
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 0,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal residential access and one mobilization are included.",
      "default_exclusions": "Engineering, hazardous-material remediation, bonds, and unusual insurance requirements.",
      "confidence": "medium"
    },
    {
      "id": "demo_cabinetry",
      "trade": "demolition",
      "name": "Remove base and wall cabinets",
      "description": "Remove base and wall cabinets. Quantity is measured per lf.",
      "unit": "lf",
      "labor_role_id": "laborer",
      "crew_hours_per_unit": {
        "base": 0.22
      },
      "national_seed_material_cost_per_unit": {
        "base": 0
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 0,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Selective removal, ordinary hand tools, and normal loading are included.",
      "default_exclusions": "Hazardous materials, structural shoring, hidden utilities, and unusually heavy disposal.",
      "confidence": "medium"
    },
    {
      "id": "demo_countertop",
      "trade": "demolition",
      "name": "Remove countertop",
      "description": "Remove countertop. Quantity is measured per lf.",
      "unit": "lf",
      "labor_role_id": "laborer",
      "crew_hours_per_unit": {
        "base": 0.15
      },
      "national_seed_material_cost_per_unit": {
        "base": 0
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 0,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Selective removal, ordinary hand tools, and normal loading are included.",
      "default_exclusions": "Hazardous materials, structural shoring, hidden utilities, and unusually heavy disposal.",
      "confidence": "medium"
    },
    {
      "id": "demo_flooring_resilient",
      "trade": "demolition",
      "name": "Remove resilient flooring",
      "description": "Remove resilient flooring. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "laborer",
      "crew_hours_per_unit": {
        "base": 0.05
      },
      "national_seed_material_cost_per_unit": {
        "base": 0.12
      },
      "equipment_cost_per_unit_base": 0.03,
      "default_waste_percent": 0,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Selective removal, ordinary hand tools, and normal loading are included.",
      "default_exclusions": "Hazardous materials, structural shoring, hidden utilities, and unusually heavy disposal.",
      "confidence": "medium"
    },
    {
      "id": "demo_flooring_carpet",
      "trade": "demolition",
      "name": "Remove carpet and pad",
      "description": "Remove carpet and pad. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "laborer",
      "crew_hours_per_unit": {
        "base": 0.03
      },
      "national_seed_material_cost_per_unit": {
        "base": 0.08
      },
      "equipment_cost_per_unit_base": 0.02,
      "default_waste_percent": 0,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Selective removal, ordinary hand tools, and normal loading are included.",
      "default_exclusions": "Hazardous materials, structural shoring, hidden utilities, and unusually heavy disposal.",
      "confidence": "high"
    },
    {
      "id": "demo_flooring_hardwood",
      "trade": "demolition",
      "name": "Remove nailed or glued wood flooring",
      "description": "Remove nailed or glued wood flooring. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "laborer",
      "crew_hours_per_unit": {
        "base": 0.12
      },
      "national_seed_material_cost_per_unit": {
        "base": 0.18
      },
      "equipment_cost_per_unit_base": 0.05,
      "default_waste_percent": 0,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Selective removal, ordinary hand tools, and normal loading are included.",
      "default_exclusions": "Hazardous materials, structural shoring, hidden utilities, and unusually heavy disposal.",
      "confidence": "medium"
    },
    {
      "id": "demo_tile_floor",
      "trade": "demolition",
      "name": "Remove tile floor and setting bed",
      "description": "Remove tile floor and setting bed. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "laborer",
      "crew_hours_per_unit": {
        "base": 0.18
      },
      "national_seed_material_cost_per_unit": {
        "base": 0.28
      },
      "equipment_cost_per_unit_base": 0.08,
      "default_waste_percent": 0,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Selective removal, ordinary hand tools, and normal loading are included.",
      "default_exclusions": "Hazardous materials, structural shoring, hidden utilities, and unusually heavy disposal.",
      "confidence": "medium"
    },
    {
      "id": "demo_tile_wall",
      "trade": "demolition",
      "name": "Remove tiled wall or surround",
      "description": "Remove tiled wall or surround. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "laborer",
      "crew_hours_per_unit": {
        "base": 0.22
      },
      "national_seed_material_cost_per_unit": {
        "base": 0.3
      },
      "equipment_cost_per_unit_base": 0.08,
      "default_waste_percent": 0,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Selective removal, ordinary hand tools, and normal loading are included.",
      "default_exclusions": "Hazardous materials, structural shoring, hidden utilities, and unusually heavy disposal.",
      "confidence": "medium"
    },
    {
      "id": "demo_drywall",
      "trade": "demolition",
      "name": "Remove drywall",
      "description": "Remove drywall. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "laborer",
      "crew_hours_per_unit": {
        "base": 0.06
      },
      "national_seed_material_cost_per_unit": {
        "base": 0.1
      },
      "equipment_cost_per_unit_base": 0.02,
      "default_waste_percent": 0,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Selective removal, ordinary hand tools, and normal loading are included.",
      "default_exclusions": "Hazardous materials, structural shoring, hidden utilities, and unusually heavy disposal.",
      "confidence": "medium"
    },
    {
      "id": "demo_nonbearing_wall",
      "trade": "demolition",
      "name": "Remove non-bearing framed wall",
      "description": "Remove non-bearing framed wall. Quantity is measured per lf.",
      "unit": "lf",
      "labor_role_id": "laborer",
      "crew_hours_per_unit": {
        "base": 0.7
      },
      "national_seed_material_cost_per_unit": {
        "base": 0.8
      },
      "equipment_cost_per_unit_base": 0.1,
      "default_waste_percent": 0,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Selective removal, ordinary hand tools, and normal loading are included.",
      "default_exclusions": "Hazardous materials, structural shoring, hidden utilities, and unusually heavy disposal.",
      "confidence": "low"
    },
    {
      "id": "demo_bathtub",
      "trade": "demolition",
      "name": "Remove bathtub",
      "description": "Remove bathtub. Quantity is measured per ea.",
      "unit": "ea",
      "labor_role_id": "laborer",
      "crew_hours_per_unit": {
        "base": 4
      },
      "national_seed_material_cost_per_unit": {
        "base": 35
      },
      "equipment_cost_per_unit_base": 20,
      "default_waste_percent": 0,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Selective removal, ordinary hand tools, and normal loading are included.",
      "default_exclusions": "Hazardous materials, structural shoring, hidden utilities, and unusually heavy disposal.",
      "confidence": "medium"
    },
    {
      "id": "demo_shower",
      "trade": "demolition",
      "name": "Remove prefabricated shower",
      "description": "Remove prefabricated shower. Quantity is measured per ea.",
      "unit": "ea",
      "labor_role_id": "laborer",
      "crew_hours_per_unit": {
        "base": 4
      },
      "national_seed_material_cost_per_unit": {
        "base": 30
      },
      "equipment_cost_per_unit_base": 15,
      "default_waste_percent": 0,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Selective removal, ordinary hand tools, and normal loading are included.",
      "default_exclusions": "Hazardous materials, structural shoring, hidden utilities, and unusually heavy disposal.",
      "confidence": "medium"
    },
    {
      "id": "demo_vanity",
      "trade": "demolition",
      "name": "Remove bathroom vanity and top",
      "description": "Remove bathroom vanity and top. Quantity is measured per ea.",
      "unit": "ea",
      "labor_role_id": "laborer",
      "crew_hours_per_unit": {
        "base": 1.5
      },
      "national_seed_material_cost_per_unit": {
        "base": 5
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 0,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Selective removal, ordinary hand tools, and normal loading are included.",
      "default_exclusions": "Hazardous materials, structural shoring, hidden utilities, and unusually heavy disposal.",
      "confidence": "high"
    },
    {
      "id": "demo_door",
      "trade": "demolition",
      "name": "Remove door, frame, and casing",
      "description": "Remove door, frame, and casing. Quantity is measured per opening.",
      "unit": "opening",
      "labor_role_id": "laborer",
      "crew_hours_per_unit": {
        "base": 1
      },
      "national_seed_material_cost_per_unit": {
        "base": 5
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 0,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Selective removal, ordinary hand tools, and normal loading are included.",
      "default_exclusions": "Hazardous materials, structural shoring, hidden utilities, and unusually heavy disposal.",
      "confidence": "high"
    },
    {
      "id": "demo_window",
      "trade": "demolition",
      "name": "Remove existing window",
      "description": "Remove existing window. Quantity is measured per opening.",
      "unit": "opening",
      "labor_role_id": "laborer",
      "crew_hours_per_unit": {
        "base": 2
      },
      "national_seed_material_cost_per_unit": {
        "base": 20
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 0,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Selective removal, ordinary hand tools, and normal loading are included.",
      "default_exclusions": "Hazardous materials, structural shoring, hidden utilities, and unusually heavy disposal.",
      "confidence": "medium"
    },
    {
      "id": "demo_roofing_asphalt",
      "trade": "demolition",
      "name": "Tear off asphalt roofing",
      "description": "Tear off asphalt roofing. Quantity is measured per square.",
      "unit": "square",
      "labor_role_id": "laborer",
      "crew_hours_per_unit": {
        "base": 5
      },
      "national_seed_material_cost_per_unit": {
        "base": 40
      },
      "equipment_cost_per_unit_base": 35,
      "default_waste_percent": 0,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Selective removal, ordinary hand tools, and normal loading are included.",
      "default_exclusions": "Hazardous materials, structural shoring, hidden utilities, and unusually heavy disposal.",
      "confidence": "medium"
    },
    {
      "id": "demo_siding",
      "trade": "demolition",
      "name": "Remove siding",
      "description": "Remove siding. Quantity is measured per square.",
      "unit": "square",
      "labor_role_id": "laborer",
      "crew_hours_per_unit": {
        "base": 7
      },
      "national_seed_material_cost_per_unit": {
        "base": 45
      },
      "equipment_cost_per_unit_base": 20,
      "default_waste_percent": 0,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Selective removal, ordinary hand tools, and normal loading are included.",
      "default_exclusions": "Hazardous materials, structural shoring, hidden utilities, and unusually heavy disposal.",
      "confidence": "medium"
    },
    {
      "id": "frame_partition_2x4",
      "trade": "framing",
      "name": "Frame non-bearing 2x4 partition",
      "description": "Frame non-bearing 2x4 partition. Quantity is measured per lf.",
      "unit": "lf",
      "labor_role_id": "carpenter",
      "crew_hours_per_unit": {
        "base": 0.5
      },
      "national_seed_material_cost_per_unit": {
        "base": 9
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 12,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard wood framing, fastening, and normal layout are included.",
      "default_exclusions": "Engineering, steel, engineered beams, and concealed structural damage.",
      "confidence": "medium"
    },
    {
      "id": "frame_partition_2x6",
      "trade": "framing",
      "name": "Frame non-bearing 2x6 partition",
      "description": "Frame non-bearing 2x6 partition. Quantity is measured per lf.",
      "unit": "lf",
      "labor_role_id": "carpenter",
      "crew_hours_per_unit": {
        "base": 0.58
      },
      "national_seed_material_cost_per_unit": {
        "base": 12
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 12,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard wood framing, fastening, and normal layout are included.",
      "default_exclusions": "Engineering, steel, engineered beams, and concealed structural damage.",
      "confidence": "medium"
    },
    {
      "id": "frame_bearing_wall",
      "trade": "framing",
      "name": "Frame bearing wall",
      "description": "Frame bearing wall. Quantity is measured per lf.",
      "unit": "lf",
      "labor_role_id": "carpenter",
      "crew_hours_per_unit": {
        "base": 0.85
      },
      "national_seed_material_cost_per_unit": {
        "base": 18
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 12,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard wood framing, fastening, and normal layout are included.",
      "default_exclusions": "Engineering, steel, engineered beams, and concealed structural damage.",
      "confidence": "low"
    },
    {
      "id": "frame_door_opening",
      "trade": "framing",
      "name": "Frame interior door opening",
      "description": "Frame interior door opening. Quantity is measured per opening.",
      "unit": "opening",
      "labor_role_id": "carpenter",
      "crew_hours_per_unit": {
        "base": 3.5
      },
      "national_seed_material_cost_per_unit": {
        "base": 45
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard wood framing, fastening, and normal layout are included.",
      "default_exclusions": "Engineering, steel, engineered beams, and concealed structural damage.",
      "confidence": "medium"
    },
    {
      "id": "frame_window_opening",
      "trade": "framing",
      "name": "Frame window opening",
      "description": "Frame window opening. Quantity is measured per opening.",
      "unit": "opening",
      "labor_role_id": "carpenter",
      "crew_hours_per_unit": {
        "base": 5
      },
      "national_seed_material_cost_per_unit": {
        "base": 80
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard wood framing, fastening, and normal layout are included.",
      "default_exclusions": "Engineering, steel, engineered beams, and concealed structural damage.",
      "confidence": "low"
    },
    {
      "id": "frame_soffit",
      "trade": "framing",
      "name": "Frame soffit or chase",
      "description": "Frame soffit or chase. Quantity is measured per lf.",
      "unit": "lf",
      "labor_role_id": "carpenter",
      "crew_hours_per_unit": {
        "base": 0.65
      },
      "national_seed_material_cost_per_unit": {
        "base": 8
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 12,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard wood framing, fastening, and normal layout are included.",
      "default_exclusions": "Engineering, steel, engineered beams, and concealed structural damage.",
      "confidence": "medium"
    },
    {
      "id": "subfloor_patch",
      "trade": "framing",
      "name": "Patch structural subfloor",
      "description": "Patch structural subfloor. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "carpenter",
      "crew_hours_per_unit": {
        "base": 0.25
      },
      "national_seed_material_cost_per_unit": {
        "base": 4.5
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 15,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard wood framing, fastening, and normal layout are included.",
      "default_exclusions": "Engineering, steel, engineered beams, and concealed structural damage.",
      "confidence": "medium"
    },
    {
      "id": "wall_blocking",
      "trade": "framing",
      "name": "Install wall blocking",
      "description": "Install wall blocking. Quantity is measured per lf.",
      "unit": "lf",
      "labor_role_id": "carpenter",
      "crew_hours_per_unit": {
        "base": 0.28
      },
      "national_seed_material_cost_per_unit": {
        "base": 3
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 12,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard wood framing, fastening, and normal layout are included.",
      "default_exclusions": "Engineering, steel, engineered beams, and concealed structural damage.",
      "confidence": "high"
    },
    {
      "id": "ceiling_furring",
      "trade": "framing",
      "name": "Fur or level ceiling framing",
      "description": "Fur or level ceiling framing. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "carpenter",
      "crew_hours_per_unit": {
        "base": 0.16
      },
      "national_seed_material_cost_per_unit": {
        "base": 2.25
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 12,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard wood framing, fastening, and normal layout are included.",
      "default_exclusions": "Engineering, steel, engineered beams, and concealed structural damage.",
      "confidence": "medium"
    },
    {
      "id": "structural_allowance",
      "trade": "framing",
      "name": "Structural framing allowance pending engineering",
      "description": "Structural framing allowance pending engineering. Quantity is measured per allowance.",
      "unit": "allowance",
      "labor_role_id": "carpenter",
      "crew_hours_per_unit": {
        "base": 20
      },
      "national_seed_material_cost_per_unit": {
        "base": 2500
      },
      "equipment_cost_per_unit_base": 500,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard wood framing, fastening, and normal layout are included.",
      "default_exclusions": "Engineering, steel, engineered beams, and concealed structural damage.",
      "confidence": "low"
    },
    {
      "id": "drywall_half_install",
      "trade": "drywall",
      "name": "Install 1/2-inch drywall",
      "description": "Install 1/2-inch drywall. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "drywall",
      "crew_hours_per_unit": {
        "base": 0.06
      },
      "national_seed_material_cost_per_unit": {
        "base": 0.85
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 12,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard gypsum board installation and finishing for the stated level are included.",
      "default_exclusions": "Lead/asbestos remediation, specialty access, and extensive concealed backing.",
      "confidence": "high"
    },
    {
      "id": "drywall_type_x_install",
      "trade": "drywall",
      "name": "Install 5/8-inch Type X drywall",
      "description": "Install 5/8-inch Type X drywall. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "drywall",
      "crew_hours_per_unit": {
        "base": 0.075
      },
      "national_seed_material_cost_per_unit": {
        "base": 1.05
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 12,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard gypsum board installation and finishing for the stated level are included.",
      "default_exclusions": "Lead/asbestos remediation, specialty access, and extensive concealed backing.",
      "confidence": "high"
    },
    {
      "id": "drywall_finish_level4",
      "trade": "drywall",
      "name": "Tape and finish drywall Level 4",
      "description": "Tape and finish drywall Level 4. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "drywall",
      "crew_hours_per_unit": {
        "base": 0.09
      },
      "national_seed_material_cost_per_unit": {
        "base": 0.3
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 8,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard gypsum board installation and finishing for the stated level are included.",
      "default_exclusions": "Lead/asbestos remediation, specialty access, and extensive concealed backing.",
      "confidence": "medium"
    },
    {
      "id": "drywall_finish_level5",
      "trade": "drywall",
      "name": "Finish drywall Level 5",
      "description": "Finish drywall Level 5. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "drywall",
      "crew_hours_per_unit": {
        "base": 0.14
      },
      "national_seed_material_cost_per_unit": {
        "base": 0.48
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 8,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard gypsum board installation and finishing for the stated level are included.",
      "default_exclusions": "Lead/asbestos remediation, specialty access, and extensive concealed backing.",
      "confidence": "medium"
    },
    {
      "id": "drywall_patch_small",
      "trade": "drywall",
      "name": "Small drywall patch",
      "description": "Small drywall patch. Quantity is measured per ea.",
      "unit": "ea",
      "labor_role_id": "drywall",
      "crew_hours_per_unit": {
        "base": 2
      },
      "national_seed_material_cost_per_unit": {
        "base": 20
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard gypsum board installation and finishing for the stated level are included.",
      "default_exclusions": "Lead/asbestos remediation, specialty access, and extensive concealed backing.",
      "confidence": "medium"
    },
    {
      "id": "drywall_patch_large",
      "trade": "drywall",
      "name": "Large drywall patch",
      "description": "Large drywall patch. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "drywall",
      "crew_hours_per_unit": {
        "base": 0.2
      },
      "national_seed_material_cost_per_unit": {
        "base": 1.2
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 12,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard gypsum board installation and finishing for the stated level are included.",
      "default_exclusions": "Lead/asbestos remediation, specialty access, and extensive concealed backing.",
      "confidence": "medium"
    },
    {
      "id": "ceiling_texture_match",
      "trade": "drywall",
      "name": "Match existing ceiling texture",
      "description": "Match existing ceiling texture. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "drywall",
      "crew_hours_per_unit": {
        "base": 0.09
      },
      "national_seed_material_cost_per_unit": {
        "base": 0.35
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 8,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard gypsum board installation and finishing for the stated level are included.",
      "default_exclusions": "Lead/asbestos remediation, specialty access, and extensive concealed backing.",
      "confidence": "low"
    },
    {
      "id": "skim_coat_walls",
      "trade": "drywall",
      "name": "Skim coat existing walls",
      "description": "Skim coat existing walls. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "drywall",
      "crew_hours_per_unit": {
        "base": 0.12
      },
      "national_seed_material_cost_per_unit": {
        "base": 0.4
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 8,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard gypsum board installation and finishing for the stated level are included.",
      "default_exclusions": "Lead/asbestos remediation, specialty access, and extensive concealed backing.",
      "confidence": "medium"
    },
    {
      "id": "insulate_wall_batt",
      "trade": "insulation",
      "name": "Install fiberglass wall batt insulation",
      "description": "Install fiberglass wall batt insulation. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "general",
      "crew_hours_per_unit": {
        "base": 0.045
      },
      "national_seed_material_cost_per_unit": {
        "base": 1.05
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 8,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard residential insulation placement is included.",
      "default_exclusions": "Air-quality remediation, inaccessible cavities, and code upgrades beyond stated scope.",
      "confidence": "high"
    },
    {
      "id": "insulate_ceiling_batt",
      "trade": "insulation",
      "name": "Install ceiling batt insulation",
      "description": "Install ceiling batt insulation. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "general",
      "crew_hours_per_unit": {
        "base": 0.055
      },
      "national_seed_material_cost_per_unit": {
        "base": 1.3
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 8,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard residential insulation placement is included.",
      "default_exclusions": "Air-quality remediation, inaccessible cavities, and code upgrades beyond stated scope.",
      "confidence": "high"
    },
    {
      "id": "insulate_attic_blown",
      "trade": "insulation",
      "name": "Install blown attic insulation",
      "description": "Install blown attic insulation. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "general",
      "crew_hours_per_unit": {
        "base": 0.035
      },
      "national_seed_material_cost_per_unit": {
        "base": 1.35
      },
      "equipment_cost_per_unit_base": 0.05,
      "default_waste_percent": 8,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard residential insulation placement is included.",
      "default_exclusions": "Air-quality remediation, inaccessible cavities, and code upgrades beyond stated scope.",
      "confidence": "medium"
    },
    {
      "id": "spray_foam_allowance",
      "trade": "insulation",
      "name": "Closed-cell spray foam allowance",
      "description": "Closed-cell spray foam allowance. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "general",
      "crew_hours_per_unit": {
        "base": 0.05
      },
      "national_seed_material_cost_per_unit": {
        "base": 3.4
      },
      "equipment_cost_per_unit_base": 0.1,
      "default_waste_percent": 8,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard residential insulation placement is included.",
      "default_exclusions": "Air-quality remediation, inaccessible cavities, and code upgrades beyond stated scope.",
      "confidence": "low"
    },
    {
      "id": "air_sealing",
      "trade": "insulation",
      "name": "Air seal accessible penetrations",
      "description": "Air seal accessible penetrations. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "general",
      "crew_hours_per_unit": {
        "base": 0.04
      },
      "national_seed_material_cost_per_unit": {
        "base": 0.3
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard residential insulation placement is included.",
      "default_exclusions": "Air-quality remediation, inaccessible cavities, and code upgrades beyond stated scope.",
      "confidence": "medium"
    },
    {
      "id": "paint_wall_repaint",
      "trade": "painting",
      "name": "Prepare and repaint walls",
      "description": "Prepare and repaint walls. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "painter",
      "crew_hours_per_unit": {
        "base": 0.045
      },
      "national_seed_material_cost_per_unit": {
        "base": 0.35
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal preparation and two finish coats over sound surfaces are included.",
      "default_exclusions": "Lead abatement, extensive substrate repair, specialty coatings, and occupied-space moving.",
      "confidence": "medium"
    },
    {
      "id": "paint_ceiling",
      "trade": "painting",
      "name": "Prepare and paint ceiling",
      "description": "Prepare and paint ceiling. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "painter",
      "crew_hours_per_unit": {
        "base": 0.055
      },
      "national_seed_material_cost_per_unit": {
        "base": 0.4
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal preparation and two finish coats over sound surfaces are included.",
      "default_exclusions": "Lead abatement, extensive substrate repair, specialty coatings, and occupied-space moving.",
      "confidence": "medium"
    },
    {
      "id": "paint_new_drywall",
      "trade": "painting",
      "name": "Prime and paint new drywall",
      "description": "Prime and paint new drywall. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "painter",
      "crew_hours_per_unit": {
        "base": 0.052
      },
      "national_seed_material_cost_per_unit": {
        "base": 0.42
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal preparation and two finish coats over sound surfaces are included.",
      "default_exclusions": "Lead abatement, extensive substrate repair, specialty coatings, and occupied-space moving.",
      "confidence": "high"
    },
    {
      "id": "paint_trim",
      "trade": "painting",
      "name": "Prepare and paint trim",
      "description": "Prepare and paint trim. Quantity is measured per lf.",
      "unit": "lf",
      "labor_role_id": "painter",
      "crew_hours_per_unit": {
        "base": 0.07
      },
      "national_seed_material_cost_per_unit": {
        "base": 0.2
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal preparation and two finish coats over sound surfaces are included.",
      "default_exclusions": "Lead abatement, extensive substrate repair, specialty coatings, and occupied-space moving.",
      "confidence": "medium"
    },
    {
      "id": "paint_door_slab",
      "trade": "painting",
      "name": "Prepare and paint door slab",
      "description": "Prepare and paint door slab. Quantity is measured per side.",
      "unit": "side",
      "labor_role_id": "painter",
      "crew_hours_per_unit": {
        "base": 0.75
      },
      "national_seed_material_cost_per_unit": {
        "base": 12
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal preparation and two finish coats over sound surfaces are included.",
      "default_exclusions": "Lead abatement, extensive substrate repair, specialty coatings, and occupied-space moving.",
      "confidence": "medium"
    },
    {
      "id": "paint_cabinetry",
      "trade": "painting",
      "name": "Prepare and spray or brush cabinets",
      "description": "Prepare and spray or brush cabinets. Quantity is measured per door_drawer.",
      "unit": "door_drawer",
      "labor_role_id": "painter",
      "crew_hours_per_unit": {
        "base": 0.95
      },
      "national_seed_material_cost_per_unit": {
        "base": 18
      },
      "equipment_cost_per_unit_base": 5,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal preparation and two finish coats over sound surfaces are included.",
      "default_exclusions": "Lead abatement, extensive substrate repair, specialty coatings, and occupied-space moving.",
      "confidence": "low"
    },
    {
      "id": "paint_exterior_wall",
      "trade": "painting",
      "name": "Prepare and paint exterior wall",
      "description": "Prepare and paint exterior wall. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "painter",
      "crew_hours_per_unit": {
        "base": 0.065
      },
      "national_seed_material_cost_per_unit": {
        "base": 0.55
      },
      "equipment_cost_per_unit_base": 0.02,
      "default_waste_percent": 12,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal preparation and two finish coats over sound surfaces are included.",
      "default_exclusions": "Lead abatement, extensive substrate repair, specialty coatings, and occupied-space moving.",
      "confidence": "medium"
    },
    {
      "id": "stain_deck",
      "trade": "painting",
      "name": "Clean and stain deck surface",
      "description": "Clean and stain deck surface. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "painter",
      "crew_hours_per_unit": {
        "base": 0.05
      },
      "national_seed_material_cost_per_unit": {
        "base": 0.5
      },
      "equipment_cost_per_unit_base": 0.03,
      "default_waste_percent": 12,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal preparation and two finish coats over sound surfaces are included.",
      "default_exclusions": "Lead abatement, extensive substrate repair, specialty coatings, and occupied-space moving.",
      "confidence": "medium"
    },
    {
      "id": "floor_lvp_install",
      "trade": "flooring",
      "name": "Install luxury vinyl plank flooring",
      "description": "Install luxury vinyl plank flooring. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "flooring",
      "crew_hours_per_unit": {
        "base": 0.1
      },
      "national_seed_material_cost_per_unit": {
        "base": 4.5
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal layout, cutting, and installation over a suitable substrate are included.",
      "default_exclusions": "Major leveling, moisture remediation, structural subfloor repair, and furniture moving.",
      "confidence": "medium"
    },
    {
      "id": "floor_laminate_install",
      "trade": "flooring",
      "name": "Install laminate flooring",
      "description": "Install laminate flooring. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "flooring",
      "crew_hours_per_unit": {
        "base": 0.11
      },
      "national_seed_material_cost_per_unit": {
        "base": 3.5
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal layout, cutting, and installation over a suitable substrate are included.",
      "default_exclusions": "Major leveling, moisture remediation, structural subfloor repair, and furniture moving.",
      "confidence": "medium"
    },
    {
      "id": "floor_engineered_wood",
      "trade": "flooring",
      "name": "Install engineered wood flooring",
      "description": "Install engineered wood flooring. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "flooring",
      "crew_hours_per_unit": {
        "base": 0.14
      },
      "national_seed_material_cost_per_unit": {
        "base": 8.5
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal layout, cutting, and installation over a suitable substrate are included.",
      "default_exclusions": "Major leveling, moisture remediation, structural subfloor repair, and furniture moving.",
      "confidence": "medium"
    },
    {
      "id": "floor_solid_hardwood",
      "trade": "flooring",
      "name": "Install solid hardwood flooring",
      "description": "Install solid hardwood flooring. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "flooring",
      "crew_hours_per_unit": {
        "base": 0.18
      },
      "national_seed_material_cost_per_unit": {
        "base": 10
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 12,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal layout, cutting, and installation over a suitable substrate are included.",
      "default_exclusions": "Major leveling, moisture remediation, structural subfloor repair, and furniture moving.",
      "confidence": "medium"
    },
    {
      "id": "floor_carpet_install",
      "trade": "flooring",
      "name": "Install carpet and pad",
      "description": "Install carpet and pad. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "flooring",
      "crew_hours_per_unit": {
        "base": 0.045
      },
      "national_seed_material_cost_per_unit": {
        "base": 4.25
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 8,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal layout, cutting, and installation over a suitable substrate are included.",
      "default_exclusions": "Major leveling, moisture remediation, structural subfloor repair, and furniture moving.",
      "confidence": "medium"
    },
    {
      "id": "floor_sheet_vinyl",
      "trade": "flooring",
      "name": "Install sheet vinyl flooring",
      "description": "Install sheet vinyl flooring. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "flooring",
      "crew_hours_per_unit": {
        "base": 0.1
      },
      "national_seed_material_cost_per_unit": {
        "base": 3.25
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal layout, cutting, and installation over a suitable substrate are included.",
      "default_exclusions": "Major leveling, moisture remediation, structural subfloor repair, and furniture moving.",
      "confidence": "medium"
    },
    {
      "id": "floor_underlayment",
      "trade": "flooring",
      "name": "Install flooring underlayment",
      "description": "Install flooring underlayment. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "flooring",
      "crew_hours_per_unit": {
        "base": 0.04
      },
      "national_seed_material_cost_per_unit": {
        "base": 0.75
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal layout, cutting, and installation over a suitable substrate are included.",
      "default_exclusions": "Major leveling, moisture remediation, structural subfloor repair, and furniture moving.",
      "confidence": "high"
    },
    {
      "id": "floor_leveling_minor",
      "trade": "flooring",
      "name": "Minor floor leveling",
      "description": "Minor floor leveling. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "flooring",
      "crew_hours_per_unit": {
        "base": 0.09
      },
      "national_seed_material_cost_per_unit": {
        "base": 1.1
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal layout, cutting, and installation over a suitable substrate are included.",
      "default_exclusions": "Major leveling, moisture remediation, structural subfloor repair, and furniture moving.",
      "confidence": "low"
    },
    {
      "id": "floor_refinish_hardwood",
      "trade": "flooring",
      "name": "Sand and refinish hardwood flooring",
      "description": "Sand and refinish hardwood flooring. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "flooring",
      "crew_hours_per_unit": {
        "base": 0.15
      },
      "national_seed_material_cost_per_unit": {
        "base": 1.25
      },
      "equipment_cost_per_unit_base": 0.08,
      "default_waste_percent": 8,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal layout, cutting, and installation over a suitable substrate are included.",
      "default_exclusions": "Major leveling, moisture remediation, structural subfloor repair, and furniture moving.",
      "confidence": "medium"
    },
    {
      "id": "baseboard_install",
      "trade": "doors_windows_trim",
      "name": "Install baseboard trim",
      "description": "Install baseboard trim. Quantity is measured per lf.",
      "unit": "lf",
      "labor_role_id": "finish_carpenter",
      "crew_hours_per_unit": {
        "base": 0.13
      },
      "national_seed_material_cost_per_unit": {
        "base": 2.75
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 12,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal residential installation, fastening, shimming, and basic sealant are included.",
      "default_exclusions": "Structural reframing, rot remediation, custom finishing, and security hardware unless selected.",
      "confidence": "medium"
    },
    {
      "id": "tile_floor_standard",
      "trade": "tile",
      "name": "Install standard-format floor tile",
      "description": "Install standard-format floor tile. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "tile",
      "crew_hours_per_unit": {
        "base": 0.32
      },
      "national_seed_material_cost_per_unit": {
        "base": 7.5
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 15,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard layout, setting materials, grout, and normal cuts are included.",
      "default_exclusions": "Stone fabrication, major substrate correction, heated systems, and specialty patterns unless selected.",
      "confidence": "medium"
    },
    {
      "id": "tile_floor_large_format",
      "trade": "tile",
      "name": "Install large-format floor tile",
      "description": "Install large-format floor tile. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "tile",
      "crew_hours_per_unit": {
        "base": 0.42
      },
      "national_seed_material_cost_per_unit": {
        "base": 11
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 15,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard layout, setting materials, grout, and normal cuts are included.",
      "default_exclusions": "Stone fabrication, major substrate correction, heated systems, and specialty patterns unless selected.",
      "confidence": "medium"
    },
    {
      "id": "tile_wall_standard",
      "trade": "tile",
      "name": "Install standard wall tile",
      "description": "Install standard wall tile. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "tile",
      "crew_hours_per_unit": {
        "base": 0.38
      },
      "national_seed_material_cost_per_unit": {
        "base": 9
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 15,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard layout, setting materials, grout, and normal cuts are included.",
      "default_exclusions": "Stone fabrication, major substrate correction, heated systems, and specialty patterns unless selected.",
      "confidence": "medium"
    },
    {
      "id": "tile_shower_premium",
      "trade": "tile",
      "name": "Install premium shower tile",
      "description": "Install premium shower tile. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "tile",
      "crew_hours_per_unit": {
        "base": 0.55
      },
      "national_seed_material_cost_per_unit": {
        "base": 16
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 18,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard layout, setting materials, grout, and normal cuts are included.",
      "default_exclusions": "Stone fabrication, major substrate correction, heated systems, and specialty patterns unless selected.",
      "confidence": "low"
    },
    {
      "id": "tile_backer_board",
      "trade": "tile",
      "name": "Install cement backer board",
      "description": "Install cement backer board. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "tile",
      "crew_hours_per_unit": {
        "base": 0.13
      },
      "national_seed_material_cost_per_unit": {
        "base": 1.7
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 12,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard layout, setting materials, grout, and normal cuts are included.",
      "default_exclusions": "Stone fabrication, major substrate correction, heated systems, and specialty patterns unless selected.",
      "confidence": "high"
    },
    {
      "id": "tile_uncoupling_membrane",
      "trade": "tile",
      "name": "Install uncoupling membrane",
      "description": "Install uncoupling membrane. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "tile",
      "crew_hours_per_unit": {
        "base": 0.08
      },
      "national_seed_material_cost_per_unit": {
        "base": 2
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard layout, setting materials, grout, and normal cuts are included.",
      "default_exclusions": "Stone fabrication, major substrate correction, heated systems, and specialty patterns unless selected.",
      "confidence": "high"
    },
    {
      "id": "shower_waterproofing",
      "trade": "tile",
      "name": "Waterproof shower walls and pan",
      "description": "Waterproof shower walls and pan. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "tile",
      "crew_hours_per_unit": {
        "base": 0.17
      },
      "national_seed_material_cost_per_unit": {
        "base": 3
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 15,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard layout, setting materials, grout, and normal cuts are included.",
      "default_exclusions": "Stone fabrication, major substrate correction, heated systems, and specialty patterns unless selected.",
      "confidence": "medium"
    },
    {
      "id": "shower_pan_mud",
      "trade": "tile",
      "name": "Form mortar shower pan",
      "description": "Form mortar shower pan. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "tile",
      "crew_hours_per_unit": {
        "base": 0.4
      },
      "national_seed_material_cost_per_unit": {
        "base": 4.5
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 15,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard layout, setting materials, grout, and normal cuts are included.",
      "default_exclusions": "Stone fabrication, major substrate correction, heated systems, and specialty patterns unless selected.",
      "confidence": "medium"
    },
    {
      "id": "tile_grout_seal",
      "trade": "tile",
      "name": "Grout and seal tile installation",
      "description": "Grout and seal tile installation. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "tile",
      "crew_hours_per_unit": {
        "base": 0.065
      },
      "national_seed_material_cost_per_unit": {
        "base": 0.65
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 8,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard layout, setting materials, grout, and normal cuts are included.",
      "default_exclusions": "Stone fabrication, major substrate correction, heated systems, and specialty patterns unless selected.",
      "confidence": "high"
    },
    {
      "id": "tile_niche",
      "trade": "tile",
      "name": "Build and tile shower niche",
      "description": "Build and tile shower niche. Quantity is measured per ea.",
      "unit": "ea",
      "labor_role_id": "tile",
      "crew_hours_per_unit": {
        "base": 5
      },
      "national_seed_material_cost_per_unit": {
        "base": 140
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 15,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard layout, setting materials, grout, and normal cuts are included.",
      "default_exclusions": "Stone fabrication, major substrate correction, heated systems, and specialty patterns unless selected.",
      "confidence": "medium"
    },
    {
      "id": "cabinet_stock_base",
      "trade": "cabinetry",
      "name": "Provide and install stock base cabinets",
      "description": "Provide and install stock base cabinets. Quantity is measured per lf.",
      "unit": "lf",
      "labor_role_id": "cabinet",
      "crew_hours_per_unit": {
        "base": 0.8
      },
      "national_seed_material_cost_per_unit": {
        "base": 260
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 8,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal cabinet layout, fastening, leveling, and adjustment are included.",
      "default_exclusions": "Structural wall changes, appliance modifications, and utility relocation.",
      "confidence": "low"
    },
    {
      "id": "cabinet_stock_wall",
      "trade": "cabinetry",
      "name": "Provide and install stock wall cabinets",
      "description": "Provide and install stock wall cabinets. Quantity is measured per lf.",
      "unit": "lf",
      "labor_role_id": "cabinet",
      "crew_hours_per_unit": {
        "base": 0.9
      },
      "national_seed_material_cost_per_unit": {
        "base": 220
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 8,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal cabinet layout, fastening, leveling, and adjustment are included.",
      "default_exclusions": "Structural wall changes, appliance modifications, and utility relocation.",
      "confidence": "low"
    },
    {
      "id": "cabinet_semi_custom",
      "trade": "cabinetry",
      "name": "Provide and install semi-custom cabinets",
      "description": "Provide and install semi-custom cabinets. Quantity is measured per lf.",
      "unit": "lf",
      "labor_role_id": "cabinet",
      "crew_hours_per_unit": {
        "base": 1.1
      },
      "national_seed_material_cost_per_unit": {
        "base": 600
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 8,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal cabinet layout, fastening, leveling, and adjustment are included.",
      "default_exclusions": "Structural wall changes, appliance modifications, and utility relocation.",
      "confidence": "low"
    },
    {
      "id": "cabinet_hardware",
      "trade": "cabinetry",
      "name": "Install cabinet pulls or knobs",
      "description": "Install cabinet pulls or knobs. Quantity is measured per ea.",
      "unit": "ea",
      "labor_role_id": "cabinet",
      "crew_hours_per_unit": {
        "base": 0.15
      },
      "national_seed_material_cost_per_unit": {
        "base": 8
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 5,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal cabinet layout, fastening, leveling, and adjustment are included.",
      "default_exclusions": "Structural wall changes, appliance modifications, and utility relocation.",
      "confidence": "medium"
    },
    {
      "id": "cabinet_crown",
      "trade": "cabinetry",
      "name": "Install cabinet crown molding",
      "description": "Install cabinet crown molding. Quantity is measured per lf.",
      "unit": "lf",
      "labor_role_id": "cabinet",
      "crew_hours_per_unit": {
        "base": 0.25
      },
      "national_seed_material_cost_per_unit": {
        "base": 6
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 12,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal cabinet layout, fastening, leveling, and adjustment are included.",
      "default_exclusions": "Structural wall changes, appliance modifications, and utility relocation.",
      "confidence": "medium"
    },
    {
      "id": "vanity_stock",
      "trade": "cabinetry",
      "name": "Provide and install stock bathroom vanity",
      "description": "Provide and install stock bathroom vanity. Quantity is measured per ea.",
      "unit": "ea",
      "labor_role_id": "cabinet",
      "crew_hours_per_unit": {
        "base": 4
      },
      "national_seed_material_cost_per_unit": {
        "base": 650
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 5,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal cabinet layout, fastening, leveling, and adjustment are included.",
      "default_exclusions": "Structural wall changes, appliance modifications, and utility relocation.",
      "confidence": "low"
    },
    {
      "id": "counter_laminate",
      "trade": "countertops",
      "name": "Install laminate countertop",
      "description": "Install laminate countertop. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "finish_carpenter",
      "crew_hours_per_unit": {
        "base": 0.15
      },
      "national_seed_material_cost_per_unit": {
        "base": 40
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 8,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Template, ordinary edge treatment, cutouts, delivery, and installation are included when applicable.",
      "default_exclusions": "Premium slabs, waterfall edges, structural reinforcement, and plumbing reconnection.",
      "confidence": "medium"
    },
    {
      "id": "counter_solid_surface",
      "trade": "countertops",
      "name": "Install solid-surface countertop",
      "description": "Install solid-surface countertop. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "finish_carpenter",
      "crew_hours_per_unit": {
        "base": 0.2
      },
      "national_seed_material_cost_per_unit": {
        "base": 75
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 8,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Template, ordinary edge treatment, cutouts, delivery, and installation are included when applicable.",
      "default_exclusions": "Premium slabs, waterfall edges, structural reinforcement, and plumbing reconnection.",
      "confidence": "low"
    },
    {
      "id": "counter_quartz",
      "trade": "countertops",
      "name": "Install quartz countertop",
      "description": "Install quartz countertop. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "finish_carpenter",
      "crew_hours_per_unit": {
        "base": 0.25
      },
      "national_seed_material_cost_per_unit": {
        "base": 95
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 8,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Template, ordinary edge treatment, cutouts, delivery, and installation are included when applicable.",
      "default_exclusions": "Premium slabs, waterfall edges, structural reinforcement, and plumbing reconnection.",
      "confidence": "low"
    },
    {
      "id": "counter_stone_premium",
      "trade": "countertops",
      "name": "Install premium natural-stone countertop",
      "description": "Install premium natural-stone countertop. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "finish_carpenter",
      "crew_hours_per_unit": {
        "base": 0.3
      },
      "national_seed_material_cost_per_unit": {
        "base": 140
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 12,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Template, ordinary edge treatment, cutouts, delivery, and installation are included when applicable.",
      "default_exclusions": "Premium slabs, waterfall edges, structural reinforcement, and plumbing reconnection.",
      "confidence": "low"
    },
    {
      "id": "plumb_toilet_replace",
      "trade": "plumbing",
      "name": "Replace toilet in existing location",
      "description": "Replace toilet in existing location. Quantity is measured per ea.",
      "unit": "ea",
      "labor_role_id": "plumber",
      "crew_hours_per_unit": {
        "base": 2.5
      },
      "national_seed_material_cost_per_unit": {
        "base": 350
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 8,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard residential connections and accessible piping are included.",
      "default_exclusions": "Utility service upgrades, concealed damage, hazardous materials, and code corrections outside scope.",
      "confidence": "medium"
    },
    {
      "id": "plumb_vanity_connect",
      "trade": "plumbing",
      "name": "Connect bathroom vanity sink and faucet",
      "description": "Connect bathroom vanity sink and faucet. Quantity is measured per ea.",
      "unit": "ea",
      "labor_role_id": "plumber",
      "crew_hours_per_unit": {
        "base": 2.5
      },
      "national_seed_material_cost_per_unit": {
        "base": 220
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 8,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard residential connections and accessible piping are included.",
      "default_exclusions": "Utility service upgrades, concealed damage, hazardous materials, and code corrections outside scope.",
      "confidence": "medium"
    },
    {
      "id": "plumb_kitchen_sink",
      "trade": "plumbing",
      "name": "Connect kitchen sink, faucet, and drain",
      "description": "Connect kitchen sink, faucet, and drain. Quantity is measured per ea.",
      "unit": "ea",
      "labor_role_id": "plumber",
      "crew_hours_per_unit": {
        "base": 3.5
      },
      "national_seed_material_cost_per_unit": {
        "base": 350
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 8,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard residential connections and accessible piping are included.",
      "default_exclusions": "Utility service upgrades, concealed damage, hazardous materials, and code corrections outside scope.",
      "confidence": "medium"
    },
    {
      "id": "plumb_dishwasher",
      "trade": "plumbing",
      "name": "Connect dishwasher",
      "description": "Connect dishwasher. Quantity is measured per ea.",
      "unit": "ea",
      "labor_role_id": "plumber",
      "crew_hours_per_unit": {
        "base": 2
      },
      "national_seed_material_cost_per_unit": {
        "base": 90
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 8,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard residential connections and accessible piping are included.",
      "default_exclusions": "Utility service upgrades, concealed damage, hazardous materials, and code corrections outside scope.",
      "confidence": "medium"
    },
    {
      "id": "plumb_tub_set",
      "trade": "plumbing",
      "name": "Set and connect bathtub",
      "description": "Set and connect bathtub. Quantity is measured per ea.",
      "unit": "ea",
      "labor_role_id": "plumber",
      "crew_hours_per_unit": {
        "base": 7
      },
      "national_seed_material_cost_per_unit": {
        "base": 900
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 8,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard residential connections and accessible piping are included.",
      "default_exclusions": "Utility service upgrades, concealed damage, hazardous materials, and code corrections outside scope.",
      "confidence": "low"
    },
    {
      "id": "plumb_shower_trim",
      "trade": "plumbing",
      "name": "Install shower valve trim and fixtures",
      "description": "Install shower valve trim and fixtures. Quantity is measured per ea.",
      "unit": "ea",
      "labor_role_id": "plumber",
      "crew_hours_per_unit": {
        "base": 3
      },
      "national_seed_material_cost_per_unit": {
        "base": 450
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 8,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard residential connections and accessible piping are included.",
      "default_exclusions": "Utility service upgrades, concealed damage, hazardous materials, and code corrections outside scope.",
      "confidence": "medium"
    },
    {
      "id": "plumb_shower_rough",
      "trade": "plumbing",
      "name": "Relocate or install shower rough plumbing",
      "description": "Relocate or install shower rough plumbing. Quantity is measured per ea.",
      "unit": "ea",
      "labor_role_id": "plumber",
      "crew_hours_per_unit": {
        "base": 10
      },
      "national_seed_material_cost_per_unit": {
        "base": 550
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard residential connections and accessible piping are included.",
      "default_exclusions": "Utility service upgrades, concealed damage, hazardous materials, and code corrections outside scope.",
      "confidence": "low"
    },
    {
      "id": "plumb_tub_rough",
      "trade": "plumbing",
      "name": "Relocate or install bathtub rough plumbing",
      "description": "Relocate or install bathtub rough plumbing. Quantity is measured per ea.",
      "unit": "ea",
      "labor_role_id": "plumber",
      "crew_hours_per_unit": {
        "base": 10
      },
      "national_seed_material_cost_per_unit": {
        "base": 500
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard residential connections and accessible piping are included.",
      "default_exclusions": "Utility service upgrades, concealed damage, hazardous materials, and code corrections outside scope.",
      "confidence": "low"
    },
    {
      "id": "plumb_sink_rough",
      "trade": "plumbing",
      "name": "Relocate sink rough plumbing",
      "description": "Relocate sink rough plumbing. Quantity is measured per ea.",
      "unit": "ea",
      "labor_role_id": "plumber",
      "crew_hours_per_unit": {
        "base": 7
      },
      "national_seed_material_cost_per_unit": {
        "base": 300
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard residential connections and accessible piping are included.",
      "default_exclusions": "Utility service upgrades, concealed damage, hazardous materials, and code corrections outside scope.",
      "confidence": "low"
    },
    {
      "id": "plumb_water_line",
      "trade": "plumbing",
      "name": "Install accessible water line",
      "description": "Install accessible water line. Quantity is measured per lf.",
      "unit": "lf",
      "labor_role_id": "plumber",
      "crew_hours_per_unit": {
        "base": 0.22
      },
      "national_seed_material_cost_per_unit": {
        "base": 3.5
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 12,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard residential connections and accessible piping are included.",
      "default_exclusions": "Utility service upgrades, concealed damage, hazardous materials, and code corrections outside scope.",
      "confidence": "medium"
    },
    {
      "id": "plumb_drain_line",
      "trade": "plumbing",
      "name": "Install accessible drain line",
      "description": "Install accessible drain line. Quantity is measured per lf.",
      "unit": "lf",
      "labor_role_id": "plumber",
      "crew_hours_per_unit": {
        "base": 0.32
      },
      "national_seed_material_cost_per_unit": {
        "base": 7
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 12,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard residential connections and accessible piping are included.",
      "default_exclusions": "Utility service upgrades, concealed damage, hazardous materials, and code corrections outside scope.",
      "confidence": "medium"
    },
    {
      "id": "plumb_water_heater",
      "trade": "plumbing",
      "name": "Replace standard tank water heater",
      "description": "Replace standard tank water heater. Quantity is measured per ea.",
      "unit": "ea",
      "labor_role_id": "plumber",
      "crew_hours_per_unit": {
        "base": 7
      },
      "national_seed_material_cost_per_unit": {
        "base": 1150
      },
      "equipment_cost_per_unit_base": 25,
      "default_waste_percent": 8,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard residential connections and accessible piping are included.",
      "default_exclusions": "Utility service upgrades, concealed damage, hazardous materials, and code corrections outside scope.",
      "confidence": "low"
    },
    {
      "id": "plumb_allowance_unknown",
      "trade": "plumbing",
      "name": "Plumbing allowance pending site verification",
      "description": "Plumbing allowance pending site verification. Quantity is measured per allowance.",
      "unit": "allowance",
      "labor_role_id": "plumber",
      "crew_hours_per_unit": {
        "base": 10
      },
      "national_seed_material_cost_per_unit": {
        "base": 900
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard residential connections and accessible piping are included.",
      "default_exclusions": "Utility service upgrades, concealed damage, hazardous materials, and code corrections outside scope.",
      "confidence": "low"
    },
    {
      "id": "elec_receptacle_replace",
      "trade": "electrical",
      "name": "Replace receptacle or switch",
      "description": "Replace receptacle or switch. Quantity is measured per ea.",
      "unit": "ea",
      "labor_role_id": "electrician",
      "crew_hours_per_unit": {
        "base": 0.5
      },
      "national_seed_material_cost_per_unit": {
        "base": 18
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 5,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard residential devices, cable, boxes, and accessible routing are included.",
      "default_exclusions": "Service upgrades, utility fees, concealed violations, and specialty controls unless selected.",
      "confidence": "high"
    },
    {
      "id": "elec_receptacle_new",
      "trade": "electrical",
      "name": "Install new receptacle on accessible circuit",
      "description": "Install new receptacle on accessible circuit. Quantity is measured per ea.",
      "unit": "ea",
      "labor_role_id": "electrician",
      "crew_hours_per_unit": {
        "base": 2
      },
      "national_seed_material_cost_per_unit": {
        "base": 55
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 8,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard residential devices, cable, boxes, and accessible routing are included.",
      "default_exclusions": "Service upgrades, utility fees, concealed violations, and specialty controls unless selected.",
      "confidence": "medium"
    },
    {
      "id": "elec_gfci",
      "trade": "electrical",
      "name": "Install GFCI receptacle",
      "description": "Install GFCI receptacle. Quantity is measured per ea.",
      "unit": "ea",
      "labor_role_id": "electrician",
      "crew_hours_per_unit": {
        "base": 1
      },
      "national_seed_material_cost_per_unit": {
        "base": 35
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 5,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard residential devices, cable, boxes, and accessible routing are included.",
      "default_exclusions": "Service upgrades, utility fees, concealed violations, and specialty controls unless selected.",
      "confidence": "high"
    },
    {
      "id": "elec_light_fixture",
      "trade": "electrical",
      "name": "Replace light fixture",
      "description": "Replace light fixture. Quantity is measured per ea.",
      "unit": "ea",
      "labor_role_id": "electrician",
      "crew_hours_per_unit": {
        "base": 1.5
      },
      "national_seed_material_cost_per_unit": {
        "base": 160
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 5,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard residential devices, cable, boxes, and accessible routing are included.",
      "default_exclusions": "Service upgrades, utility fees, concealed violations, and specialty controls unless selected.",
      "confidence": "medium"
    },
    {
      "id": "elec_recessed_light",
      "trade": "electrical",
      "name": "Install LED recessed light",
      "description": "Install LED recessed light. Quantity is measured per ea.",
      "unit": "ea",
      "labor_role_id": "electrician",
      "crew_hours_per_unit": {
        "base": 2
      },
      "national_seed_material_cost_per_unit": {
        "base": 70
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 8,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard residential devices, cable, boxes, and accessible routing are included.",
      "default_exclusions": "Service upgrades, utility fees, concealed violations, and specialty controls unless selected.",
      "confidence": "medium"
    },
    {
      "id": "elec_vanity_light",
      "trade": "electrical",
      "name": "Install bathroom vanity light",
      "description": "Install bathroom vanity light. Quantity is measured per ea.",
      "unit": "ea",
      "labor_role_id": "electrician",
      "crew_hours_per_unit": {
        "base": 1.5
      },
      "national_seed_material_cost_per_unit": {
        "base": 140
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 5,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard residential devices, cable, boxes, and accessible routing are included.",
      "default_exclusions": "Service upgrades, utility fees, concealed violations, and specialty controls unless selected.",
      "confidence": "medium"
    },
    {
      "id": "elec_exhaust_fan",
      "trade": "electrical",
      "name": "Install bathroom exhaust fan",
      "description": "Install bathroom exhaust fan. Quantity is measured per ea.",
      "unit": "ea",
      "labor_role_id": "electrician",
      "crew_hours_per_unit": {
        "base": 5
      },
      "national_seed_material_cost_per_unit": {
        "base": 220
      },
      "equipment_cost_per_unit_base": 20,
      "default_waste_percent": 8,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard residential devices, cable, boxes, and accessible routing are included.",
      "default_exclusions": "Service upgrades, utility fees, concealed violations, and specialty controls unless selected.",
      "confidence": "low"
    },
    {
      "id": "elec_dedicated_circuit",
      "trade": "electrical",
      "name": "Install dedicated branch circuit",
      "description": "Install dedicated branch circuit. Quantity is measured per circuit.",
      "unit": "circuit",
      "labor_role_id": "electrician",
      "crew_hours_per_unit": {
        "base": 7
      },
      "national_seed_material_cost_per_unit": {
        "base": 220
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard residential devices, cable, boxes, and accessible routing are included.",
      "default_exclusions": "Service upgrades, utility fees, concealed violations, and specialty controls unless selected.",
      "confidence": "low"
    },
    {
      "id": "elec_appliance_connect",
      "trade": "electrical",
      "name": "Connect hardwired appliance",
      "description": "Connect hardwired appliance. Quantity is measured per ea.",
      "unit": "ea",
      "labor_role_id": "electrician",
      "crew_hours_per_unit": {
        "base": 1.5
      },
      "national_seed_material_cost_per_unit": {
        "base": 45
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 5,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard residential devices, cable, boxes, and accessible routing are included.",
      "default_exclusions": "Service upgrades, utility fees, concealed violations, and specialty controls unless selected.",
      "confidence": "medium"
    },
    {
      "id": "elec_smoke_detector",
      "trade": "electrical",
      "name": "Install interconnected smoke or CO alarm",
      "description": "Install interconnected smoke or CO alarm. Quantity is measured per ea.",
      "unit": "ea",
      "labor_role_id": "electrician",
      "crew_hours_per_unit": {
        "base": 1.5
      },
      "national_seed_material_cost_per_unit": {
        "base": 60
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 5,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard residential devices, cable, boxes, and accessible routing are included.",
      "default_exclusions": "Service upgrades, utility fees, concealed violations, and specialty controls unless selected.",
      "confidence": "medium"
    },
    {
      "id": "elec_panel_allowance",
      "trade": "electrical",
      "name": "Electrical panel or service allowance",
      "description": "Electrical panel or service allowance. Quantity is measured per allowance.",
      "unit": "allowance",
      "labor_role_id": "electrician",
      "crew_hours_per_unit": {
        "base": 20
      },
      "national_seed_material_cost_per_unit": {
        "base": 2500
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard residential devices, cable, boxes, and accessible routing are included.",
      "default_exclusions": "Service upgrades, utility fees, concealed violations, and specialty controls unless selected.",
      "confidence": "low"
    },
    {
      "id": "elec_allowance_unknown",
      "trade": "electrical",
      "name": "Electrical allowance pending site verification",
      "description": "Electrical allowance pending site verification. Quantity is measured per allowance.",
      "unit": "allowance",
      "labor_role_id": "electrician",
      "crew_hours_per_unit": {
        "base": 10
      },
      "national_seed_material_cost_per_unit": {
        "base": 750
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard residential devices, cable, boxes, and accessible routing are included.",
      "default_exclusions": "Service upgrades, utility fees, concealed violations, and specialty controls unless selected.",
      "confidence": "low"
    },
    {
      "id": "hvac_register",
      "trade": "hvac",
      "name": "Relocate or add HVAC register",
      "description": "Relocate or add HVAC register. Quantity is measured per ea.",
      "unit": "ea",
      "labor_role_id": "hvac",
      "crew_hours_per_unit": {
        "base": 4
      },
      "national_seed_material_cost_per_unit": {
        "base": 120
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard residential equipment connection or duct modification is included.",
      "default_exclusions": "Engineering, asbestos, utility upgrades, and inaccessible concealed conditions.",
      "confidence": "low"
    },
    {
      "id": "hvac_duct_run",
      "trade": "hvac",
      "name": "Install insulated branch duct",
      "description": "Install insulated branch duct. Quantity is measured per lf.",
      "unit": "lf",
      "labor_role_id": "hvac",
      "crew_hours_per_unit": {
        "base": 0.35
      },
      "national_seed_material_cost_per_unit": {
        "base": 9
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 12,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard residential equipment connection or duct modification is included.",
      "default_exclusions": "Engineering, asbestos, utility upgrades, and inaccessible concealed conditions.",
      "confidence": "medium"
    },
    {
      "id": "hvac_bath_fan_duct",
      "trade": "hvac",
      "name": "Duct bath fan to exterior",
      "description": "Duct bath fan to exterior. Quantity is measured per lf.",
      "unit": "lf",
      "labor_role_id": "hvac",
      "crew_hours_per_unit": {
        "base": 0.3
      },
      "national_seed_material_cost_per_unit": {
        "base": 7
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 12,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard residential equipment connection or duct modification is included.",
      "default_exclusions": "Engineering, asbestos, utility upgrades, and inaccessible concealed conditions.",
      "confidence": "medium"
    },
    {
      "id": "hvac_mini_split",
      "trade": "hvac",
      "name": "Install single-zone mini-split allowance",
      "description": "Install single-zone mini-split allowance. Quantity is measured per ea.",
      "unit": "ea",
      "labor_role_id": "hvac",
      "crew_hours_per_unit": {
        "base": 20
      },
      "national_seed_material_cost_per_unit": {
        "base": 2800
      },
      "equipment_cost_per_unit_base": 150,
      "default_waste_percent": 8,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard residential equipment connection or duct modification is included.",
      "default_exclusions": "Engineering, asbestos, utility upgrades, and inaccessible concealed conditions.",
      "confidence": "low"
    },
    {
      "id": "hvac_system_replace",
      "trade": "hvac",
      "name": "Replace residential HVAC system allowance",
      "description": "Replace residential HVAC system allowance. Quantity is measured per ea.",
      "unit": "ea",
      "labor_role_id": "hvac",
      "crew_hours_per_unit": {
        "base": 36
      },
      "national_seed_material_cost_per_unit": {
        "base": 5500
      },
      "equipment_cost_per_unit_base": 300,
      "default_waste_percent": 8,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard residential equipment connection or duct modification is included.",
      "default_exclusions": "Engineering, asbestos, utility upgrades, and inaccessible concealed conditions.",
      "confidence": "low"
    },
    {
      "id": "hvac_allowance_unknown",
      "trade": "hvac",
      "name": "HVAC allowance pending site verification",
      "description": "HVAC allowance pending site verification. Quantity is measured per allowance.",
      "unit": "allowance",
      "labor_role_id": "hvac",
      "crew_hours_per_unit": {
        "base": 10
      },
      "national_seed_material_cost_per_unit": {
        "base": 1200
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Standard residential equipment connection or duct modification is included.",
      "default_exclusions": "Engineering, asbestos, utility upgrades, and inaccessible concealed conditions.",
      "confidence": "low"
    },
    {
      "id": "door_interior_prehung",
      "trade": "doors_windows_trim",
      "name": "Install prehung interior door",
      "description": "Install prehung interior door. Quantity is measured per opening.",
      "unit": "opening",
      "labor_role_id": "finish_carpenter",
      "crew_hours_per_unit": {
        "base": 4
      },
      "national_seed_material_cost_per_unit": {
        "base": 320
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 8,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal residential installation, fastening, shimming, and basic sealant are included.",
      "default_exclusions": "Structural reframing, rot remediation, custom finishing, and security hardware unless selected.",
      "confidence": "medium"
    },
    {
      "id": "door_exterior_prehung",
      "trade": "doors_windows_trim",
      "name": "Install prehung exterior door",
      "description": "Install prehung exterior door. Quantity is measured per opening.",
      "unit": "opening",
      "labor_role_id": "finish_carpenter",
      "crew_hours_per_unit": {
        "base": 8
      },
      "national_seed_material_cost_per_unit": {
        "base": 1100
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 8,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal residential installation, fastening, shimming, and basic sealant are included.",
      "default_exclusions": "Structural reframing, rot remediation, custom finishing, and security hardware unless selected.",
      "confidence": "low"
    },
    {
      "id": "door_bifold",
      "trade": "doors_windows_trim",
      "name": "Install bifold closet door",
      "description": "Install bifold closet door. Quantity is measured per opening.",
      "unit": "opening",
      "labor_role_id": "finish_carpenter",
      "crew_hours_per_unit": {
        "base": 3.5
      },
      "national_seed_material_cost_per_unit": {
        "base": 260
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 8,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal residential installation, fastening, shimming, and basic sealant are included.",
      "default_exclusions": "Structural reframing, rot remediation, custom finishing, and security hardware unless selected.",
      "confidence": "medium"
    },
    {
      "id": "door_hardware",
      "trade": "doors_windows_trim",
      "name": "Install door lockset or passage set",
      "description": "Install door lockset or passage set. Quantity is measured per ea.",
      "unit": "ea",
      "labor_role_id": "finish_carpenter",
      "crew_hours_per_unit": {
        "base": 0.6
      },
      "national_seed_material_cost_per_unit": {
        "base": 60
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 5,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal residential installation, fastening, shimming, and basic sealant are included.",
      "default_exclusions": "Structural reframing, rot remediation, custom finishing, and security hardware unless selected.",
      "confidence": "high"
    },
    {
      "id": "window_replacement_insert",
      "trade": "doors_windows_trim",
      "name": "Install replacement window insert",
      "description": "Install replacement window insert. Quantity is measured per opening.",
      "unit": "opening",
      "labor_role_id": "finish_carpenter",
      "crew_hours_per_unit": {
        "base": 5
      },
      "national_seed_material_cost_per_unit": {
        "base": 700
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 8,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal residential installation, fastening, shimming, and basic sealant are included.",
      "default_exclusions": "Structural reframing, rot remediation, custom finishing, and security hardware unless selected.",
      "confidence": "low"
    },
    {
      "id": "window_new_construction",
      "trade": "doors_windows_trim",
      "name": "Install new-construction window",
      "description": "Install new-construction window. Quantity is measured per opening.",
      "unit": "opening",
      "labor_role_id": "finish_carpenter",
      "crew_hours_per_unit": {
        "base": 8
      },
      "national_seed_material_cost_per_unit": {
        "base": 950
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 8,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal residential installation, fastening, shimming, and basic sealant are included.",
      "default_exclusions": "Structural reframing, rot remediation, custom finishing, and security hardware unless selected.",
      "confidence": "low"
    },
    {
      "id": "casing_install",
      "trade": "doors_windows_trim",
      "name": "Install door or window casing",
      "description": "Install door or window casing. Quantity is measured per lf.",
      "unit": "lf",
      "labor_role_id": "finish_carpenter",
      "crew_hours_per_unit": {
        "base": 0.15
      },
      "national_seed_material_cost_per_unit": {
        "base": 3
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 12,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal residential installation, fastening, shimming, and basic sealant are included.",
      "default_exclusions": "Structural reframing, rot remediation, custom finishing, and security hardware unless selected.",
      "confidence": "medium"
    },
    {
      "id": "crown_molding",
      "trade": "doors_windows_trim",
      "name": "Install crown molding",
      "description": "Install crown molding. Quantity is measured per lf.",
      "unit": "lf",
      "labor_role_id": "finish_carpenter",
      "crew_hours_per_unit": {
        "base": 0.23
      },
      "national_seed_material_cost_per_unit": {
        "base": 4.5
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 12,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal residential installation, fastening, shimming, and basic sealant are included.",
      "default_exclusions": "Structural reframing, rot remediation, custom finishing, and security hardware unless selected.",
      "confidence": "medium"
    },
    {
      "id": "closet_shelving",
      "trade": "doors_windows_trim",
      "name": "Install basic closet shelving",
      "description": "Install basic closet shelving. Quantity is measured per lf.",
      "unit": "lf",
      "labor_role_id": "finish_carpenter",
      "crew_hours_per_unit": {
        "base": 0.25
      },
      "national_seed_material_cost_per_unit": {
        "base": 10
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal residential installation, fastening, shimming, and basic sealant are included.",
      "default_exclusions": "Structural reframing, rot remediation, custom finishing, and security hardware unless selected.",
      "confidence": "medium"
    },
    {
      "id": "trim_allowance_custom",
      "trade": "doors_windows_trim",
      "name": "Custom millwork allowance",
      "description": "Custom millwork allowance. Quantity is measured per allowance.",
      "unit": "allowance",
      "labor_role_id": "finish_carpenter",
      "crew_hours_per_unit": {
        "base": 20
      },
      "national_seed_material_cost_per_unit": {
        "base": 2500
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 12,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal residential installation, fastening, shimming, and basic sealant are included.",
      "default_exclusions": "Structural reframing, rot remediation, custom finishing, and security hardware unless selected.",
      "confidence": "low"
    },
    {
      "id": "roof_asphalt_shingle",
      "trade": "roofing",
      "name": "Install architectural asphalt shingles",
      "description": "Install architectural asphalt shingles. Quantity is measured per square.",
      "unit": "square",
      "labor_role_id": "roofer",
      "crew_hours_per_unit": {
        "base": 8
      },
      "national_seed_material_cost_per_unit": {
        "base": 210
      },
      "equipment_cost_per_unit_base": 20,
      "default_waste_percent": 12,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal access, underlayment, flashing, fastening, and cleanup are included.",
      "default_exclusions": "Structural deck repair, hazardous materials, steep/high-access premiums, and solar work.",
      "confidence": "medium"
    },
    {
      "id": "roof_underlayment",
      "trade": "roofing",
      "name": "Install roofing underlayment",
      "description": "Install roofing underlayment. Quantity is measured per square.",
      "unit": "square",
      "labor_role_id": "roofer",
      "crew_hours_per_unit": {
        "base": 2
      },
      "national_seed_material_cost_per_unit": {
        "base": 65
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal access, underlayment, flashing, fastening, and cleanup are included.",
      "default_exclusions": "Structural deck repair, hazardous materials, steep/high-access premiums, and solar work.",
      "confidence": "high"
    },
    {
      "id": "roof_ice_water",
      "trade": "roofing",
      "name": "Install ice and water membrane",
      "description": "Install ice and water membrane. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "roofer",
      "crew_hours_per_unit": {
        "base": 0.03
      },
      "national_seed_material_cost_per_unit": {
        "base": 0.75
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal access, underlayment, flashing, fastening, and cleanup are included.",
      "default_exclusions": "Structural deck repair, hazardous materials, steep/high-access premiums, and solar work.",
      "confidence": "high"
    },
    {
      "id": "roof_flashing",
      "trade": "roofing",
      "name": "Replace typical roof flashing",
      "description": "Replace typical roof flashing. Quantity is measured per lf.",
      "unit": "lf",
      "labor_role_id": "roofer",
      "crew_hours_per_unit": {
        "base": 0.25
      },
      "national_seed_material_cost_per_unit": {
        "base": 7
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 12,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal access, underlayment, flashing, fastening, and cleanup are included.",
      "default_exclusions": "Structural deck repair, hazardous materials, steep/high-access premiums, and solar work.",
      "confidence": "medium"
    },
    {
      "id": "roof_deck_patch",
      "trade": "roofing",
      "name": "Patch roof sheathing",
      "description": "Patch roof sheathing. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "roofer",
      "crew_hours_per_unit": {
        "base": 0.25
      },
      "national_seed_material_cost_per_unit": {
        "base": 4.5
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 15,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal access, underlayment, flashing, fastening, and cleanup are included.",
      "default_exclusions": "Structural deck repair, hazardous materials, steep/high-access premiums, and solar work.",
      "confidence": "low"
    },
    {
      "id": "gutter_install",
      "trade": "exterior",
      "name": "Install aluminum gutter and downspout system",
      "description": "Install aluminum gutter and downspout system. Quantity is measured per lf.",
      "unit": "lf",
      "labor_role_id": "siding",
      "crew_hours_per_unit": {
        "base": 0.2
      },
      "national_seed_material_cost_per_unit": {
        "base": 11
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal residential exterior installation and weather detailing are included.",
      "default_exclusions": "Structural sheathing repair, hazardous materials, scaffolding, and concealed water damage.",
      "confidence": "medium"
    },
    {
      "id": "siding_vinyl",
      "trade": "exterior",
      "name": "Install vinyl siding",
      "description": "Install vinyl siding. Quantity is measured per square.",
      "unit": "square",
      "labor_role_id": "siding",
      "crew_hours_per_unit": {
        "base": 13
      },
      "national_seed_material_cost_per_unit": {
        "base": 420
      },
      "equipment_cost_per_unit_base": 25,
      "default_waste_percent": 12,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal residential exterior installation and weather detailing are included.",
      "default_exclusions": "Structural sheathing repair, hazardous materials, scaffolding, and concealed water damage.",
      "confidence": "medium"
    },
    {
      "id": "siding_fiber_cement",
      "trade": "exterior",
      "name": "Install fiber-cement siding",
      "description": "Install fiber-cement siding. Quantity is measured per square.",
      "unit": "square",
      "labor_role_id": "siding",
      "crew_hours_per_unit": {
        "base": 18
      },
      "national_seed_material_cost_per_unit": {
        "base": 650
      },
      "equipment_cost_per_unit_base": 35,
      "default_waste_percent": 15,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal residential exterior installation and weather detailing are included.",
      "default_exclusions": "Structural sheathing repair, hazardous materials, scaffolding, and concealed water damage.",
      "confidence": "medium"
    },
    {
      "id": "exterior_trim",
      "trade": "exterior",
      "name": "Install exterior trim boards",
      "description": "Install exterior trim boards. Quantity is measured per lf.",
      "unit": "lf",
      "labor_role_id": "siding",
      "crew_hours_per_unit": {
        "base": 0.25
      },
      "national_seed_material_cost_per_unit": {
        "base": 6.5
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 15,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal residential exterior installation and weather detailing are included.",
      "default_exclusions": "Structural sheathing repair, hazardous materials, scaffolding, and concealed water damage.",
      "confidence": "medium"
    },
    {
      "id": "housewrap",
      "trade": "exterior",
      "name": "Install weather-resistive barrier",
      "description": "Install weather-resistive barrier. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "siding",
      "crew_hours_per_unit": {
        "base": 0.045
      },
      "national_seed_material_cost_per_unit": {
        "base": 0.35
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal residential exterior installation and weather detailing are included.",
      "default_exclusions": "Structural sheathing repair, hazardous materials, scaffolding, and concealed water damage.",
      "confidence": "high"
    },
    {
      "id": "concrete_slab_4in",
      "trade": "concrete_masonry",
      "name": "Place 4-inch concrete slab",
      "description": "Place 4-inch concrete slab. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "concrete",
      "crew_hours_per_unit": {
        "base": 0.15
      },
      "national_seed_material_cost_per_unit": {
        "base": 5.5
      },
      "equipment_cost_per_unit_base": 0.6,
      "default_waste_percent": 8,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal excavation, forming, placement, reinforcement, and finish for stated scope are included.",
      "default_exclusions": "Engineering, unsuitable soils, pumping premiums, winter conditions, and utility conflicts.",
      "confidence": "medium"
    },
    {
      "id": "concrete_demo",
      "trade": "concrete_masonry",
      "name": "Demolish concrete slab",
      "description": "Demolish concrete slab. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "concrete",
      "crew_hours_per_unit": {
        "base": 0.25
      },
      "national_seed_material_cost_per_unit": {
        "base": 0.3
      },
      "equipment_cost_per_unit_base": 0.25,
      "default_waste_percent": 0,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal excavation, forming, placement, reinforcement, and finish for stated scope are included.",
      "default_exclusions": "Engineering, unsuitable soils, pumping premiums, winter conditions, and utility conflicts.",
      "confidence": "medium"
    },
    {
      "id": "footing_continuous",
      "trade": "concrete_masonry",
      "name": "Form and place continuous footing",
      "description": "Form and place continuous footing. Quantity is measured per lf.",
      "unit": "lf",
      "labor_role_id": "concrete",
      "crew_hours_per_unit": {
        "base": 0.75
      },
      "national_seed_material_cost_per_unit": {
        "base": 22
      },
      "equipment_cost_per_unit_base": 1,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal excavation, forming, placement, reinforcement, and finish for stated scope are included.",
      "default_exclusions": "Engineering, unsuitable soils, pumping premiums, winter conditions, and utility conflicts.",
      "confidence": "low"
    },
    {
      "id": "foundation_wall_allowance",
      "trade": "concrete_masonry",
      "name": "Foundation wall allowance",
      "description": "Foundation wall allowance. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "concrete",
      "crew_hours_per_unit": {
        "base": 0.7
      },
      "national_seed_material_cost_per_unit": {
        "base": 28
      },
      "equipment_cost_per_unit_base": 1,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal excavation, forming, placement, reinforcement, and finish for stated scope are included.",
      "default_exclusions": "Engineering, unsuitable soils, pumping premiums, winter conditions, and utility conflicts.",
      "confidence": "low"
    },
    {
      "id": "masonry_repair",
      "trade": "concrete_masonry",
      "name": "Minor masonry repair",
      "description": "Minor masonry repair. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "concrete",
      "crew_hours_per_unit": {
        "base": 0.6
      },
      "national_seed_material_cost_per_unit": {
        "base": 15
      },
      "equipment_cost_per_unit_base": 0.1,
      "default_waste_percent": 15,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal excavation, forming, placement, reinforcement, and finish for stated scope are included.",
      "default_exclusions": "Engineering, unsuitable soils, pumping premiums, winter conditions, and utility conflicts.",
      "confidence": "low"
    },
    {
      "id": "deck_pressure_treated",
      "trade": "decks_fences",
      "name": "Build pressure-treated wood deck",
      "description": "Build pressure-treated wood deck. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "carpenter",
      "crew_hours_per_unit": {
        "base": 0.6
      },
      "national_seed_material_cost_per_unit": {
        "base": 13
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 12,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal residential layout, fastening, and code-typical construction are included.",
      "default_exclusions": "Engineering, difficult excavation, utility relocation, and premium access.",
      "confidence": "low"
    },
    {
      "id": "deck_composite",
      "trade": "decks_fences",
      "name": "Build composite deck",
      "description": "Build composite deck. Quantity is measured per sf.",
      "unit": "sf",
      "labor_role_id": "carpenter",
      "crew_hours_per_unit": {
        "base": 0.7
      },
      "national_seed_material_cost_per_unit": {
        "base": 25
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal residential layout, fastening, and code-typical construction are included.",
      "default_exclusions": "Engineering, difficult excavation, utility relocation, and premium access.",
      "confidence": "low"
    },
    {
      "id": "deck_railing_wood",
      "trade": "decks_fences",
      "name": "Install wood deck railing",
      "description": "Install wood deck railing. Quantity is measured per lf.",
      "unit": "lf",
      "labor_role_id": "carpenter",
      "crew_hours_per_unit": {
        "base": 0.8
      },
      "national_seed_material_cost_per_unit": {
        "base": 24
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 12,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal residential layout, fastening, and code-typical construction are included.",
      "default_exclusions": "Engineering, difficult excavation, utility relocation, and premium access.",
      "confidence": "medium"
    },
    {
      "id": "deck_railing_composite",
      "trade": "decks_fences",
      "name": "Install composite or metal railing",
      "description": "Install composite or metal railing. Quantity is measured per lf.",
      "unit": "lf",
      "labor_role_id": "carpenter",
      "crew_hours_per_unit": {
        "base": 0.85
      },
      "national_seed_material_cost_per_unit": {
        "base": 60
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal residential layout, fastening, and code-typical construction are included.",
      "default_exclusions": "Engineering, difficult excavation, utility relocation, and premium access.",
      "confidence": "low"
    },
    {
      "id": "deck_stairs",
      "trade": "decks_fences",
      "name": "Build exterior deck stair run",
      "description": "Build exterior deck stair run. Quantity is measured per rise.",
      "unit": "rise",
      "labor_role_id": "carpenter",
      "crew_hours_per_unit": {
        "base": 1.4
      },
      "national_seed_material_cost_per_unit": {
        "base": 38
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 12,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal residential layout, fastening, and code-typical construction are included.",
      "default_exclusions": "Engineering, difficult excavation, utility relocation, and premium access.",
      "confidence": "low"
    },
    {
      "id": "deck_footing",
      "trade": "decks_fences",
      "name": "Install deck footing",
      "description": "Install deck footing. Quantity is measured per ea.",
      "unit": "ea",
      "labor_role_id": "carpenter",
      "crew_hours_per_unit": {
        "base": 3
      },
      "national_seed_material_cost_per_unit": {
        "base": 90
      },
      "equipment_cost_per_unit_base": 25,
      "default_waste_percent": 10,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal residential layout, fastening, and code-typical construction are included.",
      "default_exclusions": "Engineering, difficult excavation, utility relocation, and premium access.",
      "confidence": "low"
    },
    {
      "id": "fence_wood_privacy",
      "trade": "decks_fences",
      "name": "Install wood privacy fence",
      "description": "Install wood privacy fence. Quantity is measured per lf.",
      "unit": "lf",
      "labor_role_id": "carpenter",
      "crew_hours_per_unit": {
        "base": 0.65
      },
      "national_seed_material_cost_per_unit": {
        "base": 32
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 12,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal residential layout, fastening, and code-typical construction are included.",
      "default_exclusions": "Engineering, difficult excavation, utility relocation, and premium access.",
      "confidence": "medium"
    },
    {
      "id": "fence_gate",
      "trade": "decks_fences",
      "name": "Install wood fence gate",
      "description": "Install wood fence gate. Quantity is measured per ea.",
      "unit": "ea",
      "labor_role_id": "carpenter",
      "crew_hours_per_unit": {
        "base": 5
      },
      "national_seed_material_cost_per_unit": {
        "base": 300
      },
      "equipment_cost_per_unit_base": 0,
      "default_waste_percent": 12,
      "finish_tier_multipliers": {
        "economy": 0.78,
        "standard": 1,
        "premium": 1.65,
        "luxury": 2.6
      },
      "difficulty_multipliers": {
        "easy": 0.85,
        "standard": 1,
        "difficult": 1.3,
        "extreme": 1.7
      },
      "included_scope": "Normal residential layout, fastening, and code-typical construction are included.",
      "default_exclusions": "Engineering, difficult excavation, utility relocation, and premium access.",
      "confidence": "medium"
    }
  ],
  "project_templates": [
    {
      "id": "bathroom_cosmetic_refresh",
      "name": "Bathroom Cosmetic Refresh",
      "category": "Bathroom",
      "description": "Starting scope for bathroom cosmetic refresh. Every quantity and selected option must be confirmed before customer use.",
      "risk_level": "medium",
      "required_assembly_ids": [
        "site_protection_basic",
        "demo_vanity",
        "vanity_stock",
        "plumb_vanity_connect",
        "paint_wall_repaint",
        "final_cleanup"
      ],
      "optional_assembly_ids": [
        "plumb_toilet_replace",
        "elec_vanity_light",
        "elec_gfci",
        "floor_lvp_install",
        "tile_floor_standard",
        "baseboard_install",
        "dumpster_small"
      ],
      "intake_question_ids": [
        "location",
        "occupied",
        "dimensions",
        "finish_tier",
        "demo_extent",
        "flooring_type",
        "customer_supplied",
        "substrate_condition"
      ],
      "estimate_policy": {
        "require_location": true,
        "show_assumptions": true,
        "show_allowances": true,
        "require_contractor_review": true,
        "prohibit_auto_send": true
      }
    },
    {
      "id": "bathroom_full_same_layout",
      "name": "Full Bathroom Remodel — Same Layout",
      "category": "Bathroom",
      "description": "Starting scope for full bathroom remodel — same layout. Every quantity and selected option must be confirmed before customer use.",
      "risk_level": "medium",
      "required_assembly_ids": [
        "site_protection_basic",
        "temporary_dust_wall",
        "demo_vanity",
        "demo_tile_floor",
        "demo_tile_wall",
        "demo_bathtub",
        "dumpster_small",
        "subfloor_patch",
        "tile_backer_board",
        "shower_waterproofing",
        "tile_floor_standard",
        "tile_wall_standard",
        "tile_grout_seal",
        "vanity_stock",
        "counter_quartz",
        "plumb_vanity_connect",
        "plumb_toilet_replace",
        "plumb_tub_set",
        "plumb_shower_trim",
        "elec_gfci",
        "elec_vanity_light",
        "elec_exhaust_fan",
        "paint_wall_repaint",
        "paint_ceiling",
        "baseboard_install",
        "final_cleanup"
      ],
      "optional_assembly_ids": [
        "shower_pan_mud",
        "tile_niche",
        "tile_shower_premium",
        "drywall_patch_large",
        "wall_blocking",
        "floor_leveling_minor",
        "permit_allowance_minor"
      ],
      "intake_question_ids": [
        "location",
        "occupied",
        "access",
        "dimensions",
        "finish_tier",
        "shower_type",
        "tile_area",
        "tile_format",
        "substrate_condition",
        "customer_supplied",
        "permit_status",
        "hazardous_age"
      ],
      "estimate_policy": {
        "require_location": true,
        "show_assumptions": true,
        "show_allowances": true,
        "require_contractor_review": true,
        "prohibit_auto_send": true
      }
    },
    {
      "id": "bathroom_layout_change",
      "name": "Full Bathroom Remodel — Layout Change",
      "category": "Bathroom",
      "description": "Starting scope for full bathroom remodel — layout change. Every quantity and selected option must be confirmed before customer use.",
      "risk_level": "high",
      "required_assembly_ids": [
        "mobilization_large",
        "temporary_dust_wall",
        "demo_vanity",
        "demo_tile_floor",
        "demo_tile_wall",
        "demo_bathtub",
        "demo_drywall",
        "dumpster_small",
        "frame_partition_2x4",
        "wall_blocking",
        "subfloor_patch",
        "drywall_half_install",
        "drywall_finish_level4",
        "paint_new_drywall",
        "shower_waterproofing",
        "tile_backer_board",
        "tile_floor_standard",
        "tile_shower_premium",
        "tile_grout_seal",
        "vanity_stock",
        "counter_quartz",
        "plumb_sink_rough",
        "plumb_shower_rough",
        "plumb_vanity_connect",
        "plumb_toilet_replace",
        "plumb_shower_trim",
        "elec_gfci",
        "elec_vanity_light",
        "elec_exhaust_fan",
        "final_cleanup",
        "permit_allowance_major"
      ],
      "optional_assembly_ids": [
        "plumb_drain_line",
        "plumb_water_line",
        "elec_dedicated_circuit",
        "hvac_register",
        "structural_allowance",
        "tile_niche",
        "shower_pan_mud"
      ],
      "intake_question_ids": [
        "location",
        "occupied",
        "access",
        "dimensions",
        "layout_change",
        "structural_change",
        "finish_tier",
        "shower_type",
        "tile_area",
        "plumbing_move",
        "electrical_changes",
        "hvac_changes",
        "substrate_condition",
        "permit_status",
        "hazardous_age"
      ],
      "estimate_policy": {
        "require_location": true,
        "show_assumptions": true,
        "show_allowances": true,
        "require_contractor_review": true,
        "prohibit_auto_send": true
      }
    },
    {
      "id": "kitchen_cosmetic_refresh",
      "name": "Kitchen Cosmetic Refresh",
      "category": "Kitchen",
      "description": "Starting scope for kitchen cosmetic refresh. Every quantity and selected option must be confirmed before customer use.",
      "risk_level": "medium",
      "required_assembly_ids": [
        "site_protection_basic",
        "demo_countertop",
        "counter_quartz",
        "plumb_kitchen_sink",
        "paint_wall_repaint",
        "final_cleanup"
      ],
      "optional_assembly_ids": [
        "paint_cabinetry",
        "cabinet_hardware",
        "tile_wall_standard",
        "tile_grout_seal",
        "elec_light_fixture",
        "floor_lvp_install",
        "baseboard_install"
      ],
      "intake_question_ids": [
        "location",
        "occupied",
        "dimensions",
        "finish_tier",
        "counter_area",
        "paint_scope",
        "flooring_type",
        "customer_supplied"
      ],
      "estimate_policy": {
        "require_location": true,
        "show_assumptions": true,
        "show_allowances": true,
        "require_contractor_review": true,
        "prohibit_auto_send": true
      }
    },
    {
      "id": "kitchen_full_same_layout",
      "name": "Full Kitchen Remodel — Same Layout",
      "category": "Kitchen",
      "description": "Starting scope for full kitchen remodel — same layout. Every quantity and selected option must be confirmed before customer use.",
      "risk_level": "medium",
      "required_assembly_ids": [
        "mobilization_large",
        "temporary_dust_wall",
        "demo_cabinetry",
        "demo_countertop",
        "demo_flooring_resilient",
        "dumpster_large",
        "drywall_patch_large",
        "cabinet_semi_custom",
        "cabinet_hardware",
        "counter_quartz",
        "plumb_kitchen_sink",
        "plumb_dishwasher",
        "elec_appliance_connect",
        "elec_receptacle_new",
        "elec_light_fixture",
        "floor_lvp_install",
        "baseboard_install",
        "paint_wall_repaint",
        "paint_ceiling",
        "final_cleanup"
      ],
      "optional_assembly_ids": [
        "tile_wall_standard",
        "tile_grout_seal",
        "elec_dedicated_circuit",
        "floor_leveling_minor",
        "permit_allowance_minor",
        "cabinet_crown"
      ],
      "intake_question_ids": [
        "location",
        "occupied",
        "access",
        "dimensions",
        "finish_tier",
        "cabinet_length",
        "counter_area",
        "flooring_type",
        "electrical_changes",
        "customer_supplied",
        "permit_status",
        "hazardous_age"
      ],
      "estimate_policy": {
        "require_location": true,
        "show_assumptions": true,
        "show_allowances": true,
        "require_contractor_review": true,
        "prohibit_auto_send": true
      }
    },
    {
      "id": "kitchen_layout_change",
      "name": "Full Kitchen Remodel — Layout Change",
      "category": "Kitchen",
      "description": "Starting scope for full kitchen remodel — layout change. Every quantity and selected option must be confirmed before customer use.",
      "risk_level": "high",
      "required_assembly_ids": [
        "mobilization_large",
        "temporary_dust_wall",
        "demo_cabinetry",
        "demo_countertop",
        "demo_drywall",
        "demo_flooring_resilient",
        "dumpster_large",
        "frame_partition_2x4",
        "drywall_half_install",
        "drywall_finish_level4",
        "paint_new_drywall",
        "cabinet_semi_custom",
        "cabinet_hardware",
        "counter_quartz",
        "plumb_sink_rough",
        "plumb_kitchen_sink",
        "plumb_dishwasher",
        "elec_receptacle_new",
        "elec_dedicated_circuit",
        "elec_light_fixture",
        "floor_lvp_install",
        "baseboard_install",
        "final_cleanup",
        "permit_allowance_major"
      ],
      "optional_assembly_ids": [
        "structural_allowance",
        "hvac_register",
        "hvac_duct_run",
        "tile_wall_standard",
        "cabinet_crown",
        "floor_leveling_minor"
      ],
      "intake_question_ids": [
        "location",
        "occupied",
        "access",
        "dimensions",
        "layout_change",
        "structural_change",
        "finish_tier",
        "cabinet_length",
        "counter_area",
        "plumbing_move",
        "electrical_changes",
        "hvac_changes",
        "permit_status",
        "hazardous_age"
      ],
      "estimate_policy": {
        "require_location": true,
        "show_assumptions": true,
        "show_allowances": true,
        "require_contractor_review": true,
        "prohibit_auto_send": true
      }
    },
    {
      "id": "basement_finish",
      "name": "Unfinished Basement Build-Out",
      "category": "Interior Build-Out",
      "description": "Starting scope for unfinished basement build-out. Every quantity and selected option must be confirmed before customer use.",
      "risk_level": "high",
      "required_assembly_ids": [
        "mobilization_large",
        "floor_protection",
        "frame_partition_2x4",
        "frame_door_opening",
        "wall_blocking",
        "insulate_wall_batt",
        "drywall_half_install",
        "drywall_finish_level4",
        "paint_new_drywall",
        "paint_ceiling",
        "elec_receptacle_new",
        "elec_recessed_light",
        "elec_smoke_detector",
        "hvac_register",
        "door_interior_prehung",
        "casing_install",
        "baseboard_install",
        "floor_lvp_install",
        "final_cleanup",
        "permit_allowance_major"
      ],
      "optional_assembly_ids": [
        "plumb_allowance_unknown",
        "elec_panel_allowance",
        "hvac_duct_run",
        "floor_leveling_minor",
        "closet_shelving",
        "structural_allowance"
      ],
      "intake_question_ids": [
        "location",
        "access",
        "dimensions",
        "ceiling_height",
        "finish_tier",
        "structural_change",
        "electrical_changes",
        "hvac_changes",
        "flooring_type",
        "permit_status",
        "hazardous_age"
      ],
      "estimate_policy": {
        "require_location": true,
        "show_assumptions": true,
        "show_allowances": true,
        "require_contractor_review": true,
        "prohibit_auto_send": true
      }
    },
    {
      "id": "garage_finish",
      "name": "Garage Interior Finish",
      "category": "Interior Build-Out",
      "description": "Starting scope for garage interior finish. Every quantity and selected option must be confirmed before customer use.",
      "risk_level": "medium",
      "required_assembly_ids": [
        "mobilization_small",
        "frame_partition_2x4",
        "insulate_wall_batt",
        "insulate_ceiling_batt",
        "drywall_type_x_install",
        "drywall_finish_level4",
        "paint_new_drywall",
        "elec_receptacle_new",
        "elec_light_fixture",
        "final_cleanup"
      ],
      "optional_assembly_ids": [
        "hvac_mini_split",
        "door_interior_prehung",
        "permit_allowance_minor"
      ],
      "intake_question_ids": [
        "location",
        "dimensions",
        "ceiling_height",
        "finish_tier",
        "electrical_changes",
        "hvac_changes",
        "permit_status"
      ],
      "estimate_policy": {
        "require_location": true,
        "show_assumptions": true,
        "show_allowances": true,
        "require_contractor_review": true,
        "prohibit_auto_send": true
      }
    },
    {
      "id": "laundry_room_remodel",
      "name": "Laundry Room Remodel",
      "category": "Interior Remodel",
      "description": "Starting scope for laundry room remodel. Every quantity and selected option must be confirmed before customer use.",
      "risk_level": "medium",
      "required_assembly_ids": [
        "site_protection_basic",
        "demo_flooring_resilient",
        "drywall_patch_large",
        "paint_wall_repaint",
        "floor_lvp_install",
        "baseboard_install",
        "plumb_water_line",
        "plumb_drain_line",
        "elec_receptacle_new",
        "elec_dedicated_circuit",
        "final_cleanup"
      ],
      "optional_assembly_ids": [
        "cabinet_stock_wall",
        "counter_laminate",
        "floor_leveling_minor",
        "elec_light_fixture",
        "permit_allowance_minor"
      ],
      "intake_question_ids": [
        "location",
        "occupied",
        "dimensions",
        "layout_change",
        "flooring_type",
        "cabinet_length",
        "plumbing_move",
        "electrical_changes",
        "customer_supplied"
      ],
      "estimate_policy": {
        "require_location": true,
        "show_assumptions": true,
        "show_allowances": true,
        "require_contractor_review": true,
        "prohibit_auto_send": true
      }
    },
    {
      "id": "bedroom_refresh",
      "name": "Bedroom Refresh",
      "category": "Interior Remodel",
      "description": "Starting scope for bedroom refresh. Every quantity and selected option must be confirmed before customer use.",
      "risk_level": "low",
      "required_assembly_ids": [
        "site_protection_basic",
        "drywall_patch_small",
        "paint_wall_repaint",
        "paint_ceiling",
        "paint_trim",
        "final_cleanup"
      ],
      "optional_assembly_ids": [
        "floor_carpet_install",
        "floor_lvp_install",
        "baseboard_install",
        "door_interior_prehung",
        "closet_shelving",
        "elec_light_fixture"
      ],
      "intake_question_ids": [
        "location",
        "occupied",
        "dimensions",
        "ceiling_height",
        "paint_scope",
        "flooring_type",
        "finish_tier"
      ],
      "estimate_policy": {
        "require_location": true,
        "show_assumptions": true,
        "show_allowances": true,
        "require_contractor_review": true,
        "prohibit_auto_send": true
      }
    },
    {
      "id": "home_office_conversion",
      "name": "Home Office Conversion",
      "category": "Interior Remodel",
      "description": "Starting scope for home office conversion. Every quantity and selected option must be confirmed before customer use.",
      "risk_level": "medium",
      "required_assembly_ids": [
        "site_protection_basic",
        "paint_wall_repaint",
        "elec_receptacle_new",
        "elec_light_fixture",
        "final_cleanup"
      ],
      "optional_assembly_ids": [
        "frame_partition_2x4",
        "drywall_half_install",
        "drywall_finish_level4",
        "paint_new_drywall",
        "door_interior_prehung",
        "closet_shelving",
        "floor_lvp_install",
        "hvac_register"
      ],
      "intake_question_ids": [
        "location",
        "occupied",
        "dimensions",
        "layout_change",
        "electrical_changes",
        "hvac_changes",
        "flooring_type",
        "finish_tier"
      ],
      "estimate_policy": {
        "require_location": true,
        "show_assumptions": true,
        "show_allowances": true,
        "require_contractor_review": true,
        "prohibit_auto_send": true
      }
    },
    {
      "id": "whole_interior_paint",
      "name": "Whole-Home Interior Painting",
      "category": "Painting",
      "description": "Starting scope for whole-home interior painting. Every quantity and selected option must be confirmed before customer use.",
      "risk_level": "low",
      "required_assembly_ids": [
        "mobilization_small",
        "floor_protection",
        "paint_wall_repaint",
        "paint_ceiling",
        "paint_trim",
        "paint_door_slab",
        "daily_cleanup",
        "final_cleanup"
      ],
      "optional_assembly_ids": [
        "drywall_patch_small",
        "skim_coat_walls",
        "paint_cabinetry"
      ],
      "intake_question_ids": [
        "location",
        "occupied",
        "dimensions",
        "ceiling_height",
        "paint_scope",
        "substrate_condition",
        "hazardous_age",
        "schedule_constraint"
      ],
      "estimate_policy": {
        "require_location": true,
        "show_assumptions": true,
        "show_allowances": true,
        "require_contractor_review": true,
        "prohibit_auto_send": true
      }
    },
    {
      "id": "whole_home_flooring",
      "name": "Whole-Home Flooring Replacement",
      "category": "Flooring",
      "description": "Starting scope for whole-home flooring replacement. Every quantity and selected option must be confirmed before customer use.",
      "risk_level": "medium",
      "required_assembly_ids": [
        "mobilization_small",
        "floor_protection",
        "demo_flooring_carpet",
        "floor_underlayment",
        "floor_lvp_install",
        "baseboard_install",
        "dumpster_small",
        "final_cleanup"
      ],
      "optional_assembly_ids": [
        "demo_flooring_resilient",
        "demo_flooring_hardwood",
        "demo_tile_floor",
        "floor_leveling_minor",
        "subfloor_patch"
      ],
      "intake_question_ids": [
        "location",
        "occupied",
        "access",
        "floor_area",
        "flooring_type",
        "substrate_condition",
        "customer_supplied",
        "hazardous_age"
      ],
      "estimate_policy": {
        "require_location": true,
        "show_assumptions": true,
        "show_allowances": true,
        "require_contractor_review": true,
        "prohibit_auto_send": true
      }
    },
    {
      "id": "drywall_repair_repaint",
      "name": "Drywall Repair and Repaint",
      "category": "Drywall",
      "description": "Starting scope for drywall repair and repaint. Every quantity and selected option must be confirmed before customer use.",
      "risk_level": "low",
      "required_assembly_ids": [
        "site_protection_basic",
        "drywall_patch_large",
        "ceiling_texture_match",
        "paint_wall_repaint",
        "final_cleanup"
      ],
      "optional_assembly_ids": [
        "demo_drywall",
        "drywall_half_install",
        "drywall_finish_level4",
        "skim_coat_walls",
        "paint_ceiling"
      ],
      "intake_question_ids": [
        "location",
        "occupied",
        "wall_area",
        "substrate_condition",
        "paint_scope",
        "hazardous_age"
      ],
      "estimate_policy": {
        "require_location": true,
        "show_assumptions": true,
        "show_allowances": true,
        "require_contractor_review": true,
        "prohibit_auto_send": true
      }
    },
    {
      "id": "deck_new_wood",
      "name": "New Pressure-Treated Wood Deck",
      "category": "Exterior",
      "description": "Starting scope for new pressure-treated wood deck. Every quantity and selected option must be confirmed before customer use.",
      "risk_level": "high",
      "required_assembly_ids": [
        "mobilization_large",
        "deck_footing",
        "deck_pressure_treated",
        "deck_railing_wood",
        "deck_stairs",
        "final_cleanup",
        "permit_allowance_major"
      ],
      "optional_assembly_ids": [
        "stain_deck",
        "concrete_demo",
        "structural_allowance"
      ],
      "intake_question_ids": [
        "location",
        "access",
        "deck_area",
        "deck_material",
        "foundation_scope",
        "permit_status",
        "schedule_constraint"
      ],
      "estimate_policy": {
        "require_location": true,
        "show_assumptions": true,
        "show_allowances": true,
        "require_contractor_review": true,
        "prohibit_auto_send": true
      }
    },
    {
      "id": "deck_new_composite",
      "name": "New Composite Deck",
      "category": "Exterior",
      "description": "Starting scope for new composite deck. Every quantity and selected option must be confirmed before customer use.",
      "risk_level": "high",
      "required_assembly_ids": [
        "mobilization_large",
        "deck_footing",
        "deck_composite",
        "deck_railing_composite",
        "deck_stairs",
        "final_cleanup",
        "permit_allowance_major"
      ],
      "optional_assembly_ids": [
        "concrete_demo",
        "structural_allowance"
      ],
      "intake_question_ids": [
        "location",
        "access",
        "deck_area",
        "deck_material",
        "foundation_scope",
        "permit_status",
        "schedule_constraint"
      ],
      "estimate_policy": {
        "require_location": true,
        "show_assumptions": true,
        "show_allowances": true,
        "require_contractor_review": true,
        "prohibit_auto_send": true
      }
    },
    {
      "id": "deck_resurface",
      "name": "Deck Resurface",
      "category": "Exterior",
      "description": "Starting scope for deck resurface. Every quantity and selected option must be confirmed before customer use.",
      "risk_level": "medium",
      "required_assembly_ids": [
        "mobilization_small",
        "deck_pressure_treated",
        "deck_railing_wood",
        "final_cleanup"
      ],
      "optional_assembly_ids": [
        "deck_composite",
        "deck_railing_composite",
        "deck_stairs",
        "stain_deck",
        "structural_allowance"
      ],
      "intake_question_ids": [
        "location",
        "access",
        "deck_area",
        "deck_material",
        "substrate_condition",
        "permit_status"
      ],
      "estimate_policy": {
        "require_location": true,
        "show_assumptions": true,
        "show_allowances": true,
        "require_contractor_review": true,
        "prohibit_auto_send": true
      }
    },
    {
      "id": "window_replacement",
      "name": "Whole-Home Window Replacement",
      "category": "Openings",
      "description": "Starting scope for whole-home window replacement. Every quantity and selected option must be confirmed before customer use.",
      "risk_level": "medium",
      "required_assembly_ids": [
        "mobilization_small",
        "window_replacement_insert",
        "casing_install",
        "exterior_trim",
        "paint_trim",
        "final_cleanup"
      ],
      "optional_assembly_ids": [
        "window_new_construction",
        "frame_window_opening",
        "drywall_patch_large",
        "paint_wall_repaint"
      ],
      "intake_question_ids": [
        "location",
        "occupied",
        "access",
        "window_count",
        "finish_tier",
        "substrate_condition",
        "hazardous_age"
      ],
      "estimate_policy": {
        "require_location": true,
        "show_assumptions": true,
        "show_allowances": true,
        "require_contractor_review": true,
        "prohibit_auto_send": true
      }
    },
    {
      "id": "door_replacement_package",
      "name": "Interior Door Replacement Package",
      "category": "Openings",
      "description": "Starting scope for interior door replacement package. Every quantity and selected option must be confirmed before customer use.",
      "risk_level": "low",
      "required_assembly_ids": [
        "site_protection_basic",
        "demo_door",
        "door_interior_prehung",
        "casing_install",
        "door_hardware",
        "paint_door_slab",
        "paint_trim",
        "final_cleanup"
      ],
      "optional_assembly_ids": [
        "frame_door_opening",
        "door_bifold"
      ],
      "intake_question_ids": [
        "location",
        "occupied",
        "door_count",
        "finish_tier",
        "customer_supplied"
      ],
      "estimate_policy": {
        "require_location": true,
        "show_assumptions": true,
        "show_allowances": true,
        "require_contractor_review": true,
        "prohibit_auto_send": true
      }
    },
    {
      "id": "roof_asphalt_replacement",
      "name": "Asphalt Shingle Roof Replacement",
      "category": "Roofing",
      "description": "Starting scope for asphalt shingle roof replacement. Every quantity and selected option must be confirmed before customer use.",
      "risk_level": "high",
      "required_assembly_ids": [
        "mobilization_large",
        "demo_roofing_asphalt",
        "dumpster_large",
        "roof_underlayment",
        "roof_asphalt_shingle",
        "roof_flashing",
        "final_cleanup",
        "permit_allowance_minor"
      ],
      "optional_assembly_ids": [
        "roof_ice_water",
        "roof_deck_patch",
        "gutter_install"
      ],
      "intake_question_ids": [
        "location",
        "access",
        "roof_area",
        "stories",
        "substrate_condition",
        "finish_tier",
        "permit_status"
      ],
      "estimate_policy": {
        "require_location": true,
        "show_assumptions": true,
        "show_allowances": true,
        "require_contractor_review": true,
        "prohibit_auto_send": true
      }
    },
    {
      "id": "siding_replacement_vinyl",
      "name": "Vinyl Siding Replacement",
      "category": "Exterior",
      "description": "Starting scope for vinyl siding replacement. Every quantity and selected option must be confirmed before customer use.",
      "risk_level": "high",
      "required_assembly_ids": [
        "mobilization_large",
        "demo_siding",
        "dumpster_large",
        "housewrap",
        "siding_vinyl",
        "exterior_trim",
        "final_cleanup",
        "permit_allowance_minor"
      ],
      "optional_assembly_ids": [
        "siding_fiber_cement",
        "paint_exterior_wall",
        "structural_allowance"
      ],
      "intake_question_ids": [
        "location",
        "access",
        "stories",
        "dimensions",
        "substrate_condition",
        "finish_tier",
        "permit_status",
        "hazardous_age"
      ],
      "estimate_policy": {
        "require_location": true,
        "show_assumptions": true,
        "show_allowances": true,
        "require_contractor_review": true,
        "prohibit_auto_send": true
      }
    },
    {
      "id": "exterior_paint",
      "name": "Exterior House Painting",
      "category": "Painting",
      "description": "Starting scope for exterior house painting. Every quantity and selected option must be confirmed before customer use.",
      "risk_level": "medium",
      "required_assembly_ids": [
        "mobilization_small",
        "paint_exterior_wall",
        "paint_trim",
        "daily_cleanup",
        "final_cleanup"
      ],
      "optional_assembly_ids": [
        "exterior_trim",
        "masonry_repair"
      ],
      "intake_question_ids": [
        "location",
        "access",
        "stories",
        "dimensions",
        "substrate_condition",
        "finish_tier",
        "hazardous_age"
      ],
      "estimate_policy": {
        "require_location": true,
        "show_assumptions": true,
        "show_allowances": true,
        "require_contractor_review": true,
        "prohibit_auto_send": true
      }
    },
    {
      "id": "fence_wood_privacy",
      "name": "Wood Privacy Fence",
      "category": "Exterior",
      "description": "Starting scope for wood privacy fence. Every quantity and selected option must be confirmed before customer use.",
      "risk_level": "medium",
      "required_assembly_ids": [
        "mobilization_small",
        "fence_wood_privacy",
        "fence_gate",
        "final_cleanup"
      ],
      "optional_assembly_ids": [
        "concrete_demo",
        "permit_allowance_minor"
      ],
      "intake_question_ids": [
        "location",
        "access",
        "dimensions",
        "finish_tier",
        "permit_status"
      ],
      "estimate_policy": {
        "require_location": true,
        "show_assumptions": true,
        "show_allowances": true,
        "require_contractor_review": true,
        "prohibit_auto_send": true
      }
    },
    {
      "id": "rental_turnover",
      "name": "Residential Rental Turnover",
      "category": "Turnover",
      "description": "Starting scope for residential rental turnover. Every quantity and selected option must be confirmed before customer use.",
      "risk_level": "medium",
      "required_assembly_ids": [
        "mobilization_small",
        "drywall_patch_small",
        "paint_wall_repaint",
        "paint_ceiling",
        "paint_trim",
        "floor_lvp_install",
        "baseboard_install",
        "elec_receptacle_replace",
        "plumb_toilet_replace",
        "final_cleanup"
      ],
      "optional_assembly_ids": [
        "demo_flooring_carpet",
        "floor_carpet_install",
        "cabinet_hardware",
        "counter_laminate",
        "door_interior_prehung",
        "elec_light_fixture",
        "plumb_vanity_connect"
      ],
      "intake_question_ids": [
        "location",
        "access",
        "dimensions",
        "finish_tier",
        "demo_extent",
        "flooring_type",
        "paint_scope",
        "customer_supplied",
        "schedule_constraint"
      ],
      "estimate_policy": {
        "require_location": true,
        "show_assumptions": true,
        "show_allowances": true,
        "require_contractor_review": true,
        "prohibit_auto_send": true
      }
    },
    {
      "id": "room_addition_shell",
      "name": "Room Addition — Weather-Tight Shell",
      "category": "Addition",
      "description": "Starting scope for room addition — weather-tight shell. Every quantity and selected option must be confirmed before customer use.",
      "risk_level": "very_high",
      "required_assembly_ids": [
        "mobilization_large",
        "project_management",
        "permit_allowance_major",
        "structural_allowance",
        "footing_continuous",
        "foundation_wall_allowance",
        "frame_bearing_wall",
        "frame_window_opening",
        "frame_door_opening",
        "roof_underlayment",
        "roof_asphalt_shingle",
        "housewrap",
        "siding_vinyl",
        "window_new_construction",
        "door_exterior_prehung",
        "final_cleanup"
      ],
      "optional_assembly_ids": [
        "concrete_slab_4in",
        "siding_fiber_cement",
        "gutter_install",
        "roof_flashing"
      ],
      "intake_question_ids": [
        "location",
        "access",
        "dimensions",
        "structural_change",
        "foundation_scope",
        "finish_tier",
        "permit_status",
        "schedule_constraint"
      ],
      "estimate_policy": {
        "require_location": true,
        "show_assumptions": true,
        "show_allowances": true,
        "require_contractor_review": true,
        "prohibit_auto_send": true
      }
    },
    {
      "id": "room_addition_finished",
      "name": "Room Addition — Finished Interior",
      "category": "Addition",
      "description": "Starting scope for room addition — finished interior. Every quantity and selected option must be confirmed before customer use.",
      "risk_level": "very_high",
      "required_assembly_ids": [
        "mobilization_large",
        "project_management",
        "permit_allowance_major",
        "structural_allowance",
        "footing_continuous",
        "foundation_wall_allowance",
        "frame_bearing_wall",
        "frame_window_opening",
        "frame_door_opening",
        "insulate_wall_batt",
        "insulate_ceiling_batt",
        "drywall_half_install",
        "drywall_finish_level4",
        "paint_new_drywall",
        "paint_ceiling",
        "elec_receptacle_new",
        "elec_recessed_light",
        "hvac_duct_run",
        "floor_lvp_install",
        "baseboard_install",
        "roof_underlayment",
        "roof_asphalt_shingle",
        "housewrap",
        "siding_vinyl",
        "window_new_construction",
        "door_exterior_prehung",
        "final_cleanup"
      ],
      "optional_assembly_ids": [
        "plumb_allowance_unknown",
        "hvac_mini_split",
        "concrete_slab_4in",
        "siding_fiber_cement",
        "gutter_install"
      ],
      "intake_question_ids": [
        "location",
        "access",
        "dimensions",
        "ceiling_height",
        "structural_change",
        "foundation_scope",
        "finish_tier",
        "electrical_changes",
        "hvac_changes",
        "plumbing_move",
        "flooring_type",
        "permit_status",
        "schedule_constraint"
      ],
      "estimate_policy": {
        "require_location": true,
        "show_assumptions": true,
        "show_allowances": true,
        "require_contractor_review": true,
        "prohibit_auto_send": true
      }
    }
  ],
  "questions": [
    {
      "id": "location",
      "question": "Where is the project located?",
      "response_type": "postal_code",
      "options": [],
      "rationale": "Required for regional pricing and permits."
    },
    {
      "id": "occupied",
      "question": "Will the home be occupied during construction?",
      "response_type": "single",
      "options": [
        "Occupied",
        "Vacant"
      ],
      "rationale": "Changes protection, cleanup, and productivity."
    },
    {
      "id": "access",
      "question": "How difficult is access to the work area?",
      "response_type": "single",
      "options": [
        "Easy",
        "Standard",
        "Difficult",
        "Extreme"
      ],
      "rationale": "Changes labor and equipment."
    },
    {
      "id": "finish_tier",
      "question": "What finish level should be priced?",
      "response_type": "single",
      "options": [
        "Economy",
        "Standard",
        "Premium",
        "Luxury"
      ],
      "rationale": "Changes finish-material allowances."
    },
    {
      "id": "dimensions",
      "question": "What are the room or work-area dimensions?",
      "response_type": "measurement",
      "options": [],
      "rationale": "Drives quantities."
    },
    {
      "id": "ceiling_height",
      "question": "What is the ceiling height?",
      "response_type": "measurement",
      "options": [],
      "rationale": "Affects wall area and access."
    },
    {
      "id": "layout_change",
      "question": "Will the existing layout change?",
      "response_type": "boolean",
      "options": [],
      "rationale": "May trigger framing and utility relocation."
    },
    {
      "id": "structural_change",
      "question": "Are any bearing walls or structural openings changing?",
      "response_type": "boolean",
      "options": [],
      "rationale": "Requires engineering and site verification."
    },
    {
      "id": "demo_extent",
      "question": "What existing finishes and fixtures must be removed?",
      "response_type": "multi",
      "options": [
        "Flooring",
        "Walls",
        "Ceiling",
        "Cabinets",
        "Fixtures",
        "Other"
      ],
      "rationale": "Controls demolition and disposal."
    },
    {
      "id": "substrate_condition",
      "question": "What condition is the substrate or framing in?",
      "response_type": "single",
      "options": [
        "Sound",
        "Minor repair",
        "Unknown",
        "Known damage"
      ],
      "rationale": "Controls repair allowance."
    },
    {
      "id": "customer_supplied",
      "question": "Which finish materials or fixtures will the customer supply?",
      "response_type": "multi",
      "options": [
        "None",
        "Fixtures",
        "Flooring",
        "Tile",
        "Cabinets",
        "Countertops",
        "Appliances",
        "Other"
      ],
      "rationale": "Prevents duplicate material charges."
    },
    {
      "id": "permit_status",
      "question": "Should permit and inspection fees be included?",
      "response_type": "single",
      "options": [
        "Include allowance",
        "Known amount",
        "Exclude",
        "Unknown"
      ],
      "rationale": "Controls permit allowance."
    },
    {
      "id": "hazardous_age",
      "question": "Was the home built before 1978 or are hazardous materials suspected?",
      "response_type": "single",
      "options": [
        "No",
        "Yes",
        "Unknown"
      ],
      "rationale": "Triggers testing/remediation warning."
    },
    {
      "id": "floor_area",
      "question": "What floor area is affected?",
      "response_type": "measurement",
      "options": [],
      "rationale": "Drives flooring and floor protection."
    },
    {
      "id": "wall_area",
      "question": "What wall area is affected?",
      "response_type": "measurement",
      "options": [],
      "rationale": "Drives drywall, tile, and paint."
    },
    {
      "id": "cabinet_length",
      "question": "How many linear feet of cabinets are required?",
      "response_type": "measurement",
      "options": [],
      "rationale": "Drives cabinet allowance."
    },
    {
      "id": "counter_area",
      "question": "How many square feet of countertop are required?",
      "response_type": "measurement",
      "options": [],
      "rationale": "Drives countertop allowance."
    },
    {
      "id": "plumbing_move",
      "question": "Will plumbing fixtures move from their current locations?",
      "response_type": "boolean",
      "options": [],
      "rationale": "Triggers rough plumbing."
    },
    {
      "id": "electrical_changes",
      "question": "What electrical changes are required?",
      "response_type": "multi",
      "options": [
        "None",
        "Devices",
        "Lighting",
        "Dedicated circuits",
        "Panel/service",
        "Unknown"
      ],
      "rationale": "Controls electrical assemblies."
    },
    {
      "id": "hvac_changes",
      "question": "Are HVAC changes required?",
      "response_type": "single",
      "options": [
        "None",
        "Register move",
        "Duct changes",
        "Equipment",
        "Unknown"
      ],
      "rationale": "Controls HVAC allowance."
    },
    {
      "id": "shower_type",
      "question": "What shower or tub configuration is planned?",
      "response_type": "single",
      "options": [
        "Keep existing",
        "Tub replacement",
        "Prefabricated shower",
        "Tiled shower",
        "Tub/shower tile surround"
      ],
      "rationale": "Controls wet-area assemblies."
    },
    {
      "id": "tile_area",
      "question": "What floor and wall tile areas are planned?",
      "response_type": "measurement",
      "options": [],
      "rationale": "Drives tile quantities."
    },
    {
      "id": "tile_format",
      "question": "What tile format or pattern is planned?",
      "response_type": "single",
      "options": [
        "Standard",
        "Large format",
        "Mosaic",
        "Complex pattern",
        "Unknown"
      ],
      "rationale": "Changes tile productivity."
    },
    {
      "id": "flooring_type",
      "question": "What flooring is planned?",
      "response_type": "single",
      "options": [
        "LVP",
        "Laminate",
        "Engineered wood",
        "Solid hardwood",
        "Carpet",
        "Sheet vinyl",
        "Tile",
        "Refinish existing"
      ],
      "rationale": "Selects flooring assembly."
    },
    {
      "id": "paint_scope",
      "question": "Which surfaces will be painted?",
      "response_type": "multi",
      "options": [
        "Walls",
        "Ceilings",
        "Trim",
        "Doors",
        "Cabinets",
        "Exterior"
      ],
      "rationale": "Selects paint assemblies."
    },
    {
      "id": "door_count",
      "question": "How many doors or openings are affected?",
      "response_type": "number",
      "options": [],
      "rationale": "Drives door and casing quantities."
    },
    {
      "id": "window_count",
      "question": "How many windows are affected?",
      "response_type": "number",
      "options": [],
      "rationale": "Drives window quantities."
    },
    {
      "id": "roof_area",
      "question": "What is the roof area and pitch?",
      "response_type": "measurement",
      "options": [],
      "rationale": "Drives roofing and access factor."
    },
    {
      "id": "stories",
      "question": "How many stories must the crew access?",
      "response_type": "number",
      "options": [],
      "rationale": "Changes access and fall-protection requirements."
    },
    {
      "id": "deck_area",
      "question": "What are the deck dimensions and height?",
      "response_type": "measurement",
      "options": [],
      "rationale": "Drives decking, railing, stairs, and footings."
    },
    {
      "id": "deck_material",
      "question": "What deck material is planned?",
      "response_type": "single",
      "options": [
        "Pressure-treated wood",
        "Composite",
        "Other"
      ],
      "rationale": "Selects decking assembly."
    },
    {
      "id": "foundation_scope",
      "question": "What foundation or footing work is expected?",
      "response_type": "text",
      "options": [],
      "rationale": "Requires site and engineering confirmation."
    },
    {
      "id": "allowances",
      "question": "Which selections are not final and should remain allowances?",
      "response_type": "multi",
      "options": [
        "Fixtures",
        "Tile",
        "Flooring",
        "Cabinets",
        "Countertops",
        "Appliances",
        "Lighting",
        "Other"
      ],
      "rationale": "Prevents false precision."
    },
    {
      "id": "schedule_constraint",
      "question": "Are there phasing or completion-date constraints?",
      "response_type": "text",
      "options": [],
      "rationale": "May change mobilization and productivity."
    },
    {
      "id": "photos_available",
      "question": "Can you provide current-condition photos?",
      "response_type": "boolean",
      "options": [],
      "rationale": "Improves scope matching but not concealed-condition certainty."
    }
  ]
} as const;
