#!/usr/bin/env python3
"""Tag and import the Repair 2026 Q3 costbook into Supabase.

The source workbook is opened read-only and is never modified. Use --dry-run to
validate and summarize all rows without making a network request.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from pathlib import Path
from typing import Any, Iterable

from openpyxl import load_workbook


CATALOG_VERSION = "repair-2026-q3"
PROCESS_ROLES = (
    ("hazard_screening", ("asbestos", "lead testing", "hazardous material", "mold test")),
    ("design_and_approval", ("permit", "engineering", "architect", "inspection fee")),
    ("utility_isolation", ("disconnect", "shut off", "isolate", "lockout")),
    ("disposal", ("disposal", "dump fee", "haul", "debris", "landfill")),
    ("cleanup", ("final clean", "cleanup", "clean up", "construction cleaning")),
    ("testing", ("testing", "test and balance", "pressure test", "commission")),
    ("finish_restoration", ("patch and paint", "finish repair", "restore finish")),
    ("moisture_control", ("waterproof", "shower pan", "moisture barrier", "uncoupling membrane")),
    ("weatherproofing", ("flashing", "weather barrier", "housewrap", "sealant", "caulking")),
    ("rough_in", ("rough-in", "rough in", "underground piping", "branch circuit wiring")),
    ("connection_and_startup", ("connect", "hookup", "start-up", "startup")),
    ("protection", ("temporary protection", "floor protection", "dust barrier", "protect existing")),
    ("preparation", ("preparation", "prepare", "underlayment", "leveling", "substrate", "prime")),
    ("removal", ("remove", "removal", "strip existing", "tear off")),
    ("demolition", ("demolition", "demolish", "sawcut")),
)

TRADE_KEYWORDS = (
    ("plumbing", ("plumb", "toilet", "water closet", "faucet", "lavatory", "sink", "bathtub", "shower", "water heater", "sewer", "drain", "pipe")),
    ("electrical", ("electric", "wiring", "receptacle", "outlet", "switch", "lighting", "light fixture", "panelboard", "circuit breaker")),
    ("hvac", ("hvac", "furnace", "air conditioning", "heat pump", "duct", "thermostat", "boiler", "fan coil")),
    ("painting", ("paint", "coating", "primer", "stain", "wall covering")),
    ("drywall", ("drywall", "gypsum", "wallboard", "sheetrock", "joint compound")),
    ("flooring", ("flooring", "floor covering", "carpet", "resilient", "vinyl plank", "hardwood floor", "laminate floor")),
    ("tile", ("ceramic tile", "porcelain tile", "stone tile", "tile setting", "grout")),
    ("cabinetry", ("cabinet", "vanity", "casework")),
    ("countertops", ("countertop", "counter top", "backsplash")),
    ("windows_doors", ("window", "glazing", "door", "lockset", "weatherstripping")),
    ("roofing", ("roof", "shingle", "underlayment", "gutter", "downspout")),
    ("siding", ("siding", "stucco", "exterior cladding", "soffit", "fascia")),
    ("framing", ("framing", "studs and plates", "joist", "rafter", "truss", "beam", "header", "column", "post")),
    ("finish_carpentry", ("molding", "baseboard", "crown", "chair rail", "trim board", "stair parts")),
    ("insulation", ("insulation", "batt or roll", "spray foam")),
    ("concrete", ("concrete", "masonry", "brick", "block wall", "footing", "foundation")),
    ("decking", ("deck", "porch", "railing")),
    ("fencing", ("fence", "chain link", "basketweave")),
    ("demolition", ("demolition", "demolish", "removal", "remove")),
)

OBJECT_KEYWORDS = (
    ("toilet", ("toilet", "water closet")),
    ("garbage_disposal", ("garbage disposer", "garbage disposal", "food waste disposer")),
    ("water_heater", ("water heater",)),
    ("dishwasher", ("dishwasher",)),
    ("faucet", ("faucet", "mixer valve")),
    ("bathtub", ("bathtub", "bath tub")),
    ("shower", ("shower", "shower receptor")),
    ("sink", ("sink", "lavatory")),
    ("cabinet", ("cabinet", "casework", "vanity")),
    ("countertop", ("countertop", "counter top")),
    ("drywall", ("drywall", "gypsum", "wallboard", "sheetrock")),
    ("paint", ("paint", "coating", "primer", "stain")),
    ("flooring", ("flooring", "floor covering", "carpet", "vinyl plank", "hardwood floor", "laminate floor")),
    ("tile", ("ceramic tile", "porcelain tile", "stone tile", "tile setting", "grout")),
    # Keep lighting before door so "indoor lighting" cannot be tagged as a door.
    ("lighting", ("lighting", "light fixture", "luminaire")),
    ("window", ("window", "glazing")),
    ("door", ("door", "lockset")),
    ("roof", ("roof", "shingle", "gutter", "downspout")),
    ("siding", ("siding", "stucco", "cladding", "soffit", "fascia")),
    ("framing", ("framing", "studs and plates", "joist", "rafter", "truss", "beam", "header")),
    ("trim", ("molding", "baseboard", "crown", "chair rail", "trim board")),
    ("insulation", ("insulation", "batt or roll", "spray foam")),
    ("concrete", ("concrete", "masonry", "brick", "footing", "foundation")),
    ("deck", ("deck", "porch", "railing")),
    ("fence", ("fence", "chain link", "basketweave")),
    ("outlet", ("receptacle", "outlet", "switch")),
    ("electrical_panel", ("panelboard", "circuit breaker", "electrical panel")),
    ("hvac_equipment", ("furnace", "air conditioning", "heat pump", "boiler", "fan coil")),
    ("ductwork", ("duct", "register", "grille")),
    ("plumbing_pipe", ("pipe", "piping", "water line", "drain line", "sewer")),
)

MATERIALS = (
    "acrylic", "aluminum", "brick", "ceramic", "concrete", "copper",
    "engineered wood", "fiber cement", "fiberglass", "granite", "hardwood",
    "laminate", "marble", "porcelain", "pvc", "quartz", "redwood", "steel",
    "stone", "vinyl", "wood",
)


def number(value: Any) -> float:
    if isinstance(value, (int, float)):
        return round(float(value), 4)
    return 0.0


def contains_any(text: str, phrases: Iterable[str]) -> bool:
    return any(phrase in text for phrase in phrases)


def classify(text: str, rules: Iterable[tuple[str, tuple[str, ...]]], fallback: str) -> tuple[str, bool]:
    for value, keywords in rules:
        if contains_any(text, keywords):
            return value, True
    return fallback, False


def infer_process_role(text: str) -> tuple[str, bool]:
    return classify(text, PROCESS_ROLES, "primary_work")


def infer_action(text: str, process_role: str) -> str:
    if process_role in {"removal", "demolition"}:
        return "demolish"
    if contains_any(text, ("diagnose", "troubleshoot", "investigate")):
        return "diagnose"
    if contains_any(text, ("maintenance", "maintain", "service ")):
        return "maintain"
    if contains_any(text, ("repair", "patch", "refinish", "restore")):
        return "repair"
    if contains_any(text, ("replace", "replacement")):
        return "replace"
    return "install"


def infer_attributes(text: str) -> dict[str, str | bool]:
    attributes: dict[str, str | bool] = {}
    for material in MATERIALS:
        if material in text:
            attributes["material"] = material
            break
    for grade in ("economy", "standard", "premium", "luxury", "commercial"):
        if grade in text:
            attributes["grade"] = grade
            break
    if "grade" not in attributes:
        if contains_any(text, ("average", "builder grade")):
            attributes["grade"] = "standard"
        elif contains_any(text, ("high grade", "high quality")):
            attributes["grade"] = "premium"
    if contains_any(text, ("two piece", "two-piece")):
        attributes["fixture_type"] = "two_piece"
    elif contains_any(text, ("one piece", "one-piece")):
        attributes["fixture_type"] = "one_piece"
    thickness = re.search(r"\b(1/8|1/4|3/8|1/2|5/8|3/4|1)\s*(?:inch|in\.?|\")", text)
    if thickness:
        attributes["thickness"] = f"{thickness.group(1)} inch"
    size = re.search(r"\b(\d+(?:\.\d+)?)\s*(?:inch|in\.?|\")\b", text)
    if size:
        attributes["size"] = f"{size.group(1)} inch"
    if "small volume" in text:
        attributes["volume_tier"] = "small"
    elif "large volume" in text:
        attributes["volume_tier"] = "large"
    if contains_any(text, ("owner furnished", "owner supplied", "customer supplied")):
        attributes["customer_supply"] = True
    if "glue down" in text:
        attributes["installation_method"] = "glue_down"
    elif "floating" in text:
        attributes["installation_method"] = "floating"
    elif "nail" in text:
        attributes["installation_method"] = "nailed"
    return attributes


def tag_row(values: tuple[Any, ...], source_row: int, catalog_version: str) -> dict[str, Any] | None:
    category = str(values[0] or "").strip()
    description = str(values[1] or "").strip()
    if not category and not description:
        return None
    text = re.sub(r"\s+", " ", f"{category} {description}".lower()).strip()
    process_role, role_match = infer_process_role(text)
    trade, trade_match = classify(text, TRADE_KEYWORDS, "general")
    object_key, object_match = classify(text, OBJECT_KEYWORDS, "other")
    if object_key == "toilet" and contains_any(
        text,
        ("toilet accessory", "toilet room accessor", "toilet roll holder", "toilet tissue", "paper holder", "paper dispenser", "partition", "grab bar"),
    ):
        object_key, object_match = "other", False
    match_count = sum((role_match, trade_match, object_match))
    confidence = (0.35, 0.55, 0.75, 0.9)[match_count]
    direct_cost = number(values[4])
    residential_eligible = direct_cost >= 0 and not contains_any(
        text,
        ("commercial", "industrial", "institutional", "high rise", "high-rise", "airport", "hospital"),
    )
    return {
        "catalog_version": catalog_version,
        "source_row": source_row,
        "category": category,
        "description": description,
        "material_cost": number(values[2]),
        "labor_cost": number(values[3]),
        "direct_cost": direct_cost,
        "equipment_cost": number(values[6]),
        "unit": str(values[7] or "").strip() or "Ea",
        "crew_code": str(values[9] or "").strip(),
        "trade": trade,
        "action": infer_action(text, process_role),
        "object_key": object_key,
        "process_role": process_role,
        "attributes": infer_attributes(text),
        "residential_eligible": residential_eligible,
        "tag_confidence": confidence,
    }


def read_rows(workbook_path: Path, catalog_version: str) -> list[dict[str, Any]]:
    workbook = load_workbook(workbook_path, read_only=True, data_only=True)
    sheet = workbook["Costbook Export"]
    rows = []
    for source_row, values in enumerate(sheet.iter_rows(min_row=2, values_only=True), start=2):
        tagged = tag_row(values, source_row, catalog_version)
        if tagged:
            rows.append(tagged)
    workbook.close()
    return rows


def import_batch(url: str, key: str, rows: list[dict[str, Any]]) -> None:
    endpoint = url.rstrip("/") + "/rest/v1/estimator_cost_items?" + urllib.parse.urlencode({
        "on_conflict": "catalog_version,source_row"
    })
    request = urllib.request.Request(
        endpoint,
        data=json.dumps(rows, separators=(",", ":")).encode("utf-8"),
        method="POST",
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Prefer": "resolution=merge-duplicates,return=minimal",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            if response.status not in (200, 201, 204):
                raise RuntimeError(f"Unexpected Supabase status {response.status}")
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")[:1000]
        raise RuntimeError(f"Supabase import failed ({error.code}): {body}") from error


def batch_sql(rows: list[dict[str, Any]]) -> str:
    encoded = base64.b64encode(
        json.dumps(rows, separators=(",", ":")).encode("utf-8")
    ).decode("ascii")
    return f"""with payload as (
  select convert_from(decode('{encoded}', 'base64'), 'utf8')::jsonb as rows
)
insert into public.estimator_cost_items (
  catalog_version, source_row, category, description, material_cost, labor_cost,
  equipment_cost, direct_cost, unit, crew_code, trade, action, object_key,
  process_role, attributes, residential_eligible, tag_confidence
)
select
  row.catalog_version, row.source_row, row.category, row.description,
  row.material_cost, row.labor_cost, row.equipment_cost, row.direct_cost,
  row.unit, row.crew_code, row.trade, row.action, row.object_key,
  row.process_role, row.attributes, row.residential_eligible, row.tag_confidence
from payload
cross join lateral jsonb_to_recordset(payload.rows) as row(
  catalog_version text, source_row integer, category text, description text,
  material_cost numeric, labor_cost numeric, equipment_cost numeric,
  direct_cost numeric, unit text, crew_code text, trade text, action text,
  object_key text, process_role text, attributes jsonb,
  residential_eligible boolean, tag_confidence numeric
)
on conflict (catalog_version, source_row) do update set
  category = excluded.category,
  description = excluded.description,
  material_cost = excluded.material_cost,
  labor_cost = excluded.labor_cost,
  equipment_cost = excluded.equipment_cost,
  direct_cost = excluded.direct_cost,
  unit = excluded.unit,
  crew_code = excluded.crew_code,
  trade = excluded.trade,
  action = excluded.action,
  object_key = excluded.object_key,
  process_role = excluded.process_role,
  attributes = excluded.attributes,
  residential_eligible = excluded.residential_eligible,
  tag_confidence = excluded.tag_confidence,
  updated_at = now();
"""


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("workbook", type=Path)
    parser.add_argument("--catalog-version", default=CATALOG_VERSION)
    parser.add_argument("--batch-size", type=int, default=250)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--sql-directory", type=Path)
    args = parser.parse_args()
    if args.batch_size < 1 or args.batch_size > 500:
        parser.error("--batch-size must be between 1 and 500")

    rows = read_rows(args.workbook, args.catalog_version)
    if len(rows) != 12_107:
        raise RuntimeError(f"Expected 12,107 cost rows, found {len(rows):,}")
    summary = {
        "catalog_version": args.catalog_version,
        "rows": len(rows),
        "residential_rows": sum(bool(row["residential_eligible"]) for row in rows),
        "deduction_rows_excluded": sum(row["direct_cost"] < 0 for row in rows),
        "trades": Counter(row["trade"] for row in rows).most_common(),
        "objects": Counter(row["object_key"] for row in rows).most_common(30),
        "process_roles": Counter(row["process_role"] for row in rows).most_common(),
    }
    if args.dry_run:
        print(json.dumps(summary, indent=2))
        return
    if args.sql_directory:
        args.sql_directory.mkdir(parents=True, exist_ok=True)
        for batch_number, start in enumerate(range(0, len(rows), args.batch_size), start=1):
            path = args.sql_directory / f"catalog-{batch_number:03d}.sql"
            path.write_text(batch_sql(rows[start : start + args.batch_size]))
        print(json.dumps({
            **summary,
            "sql_batches": (len(rows) + args.batch_size - 1) // args.batch_size,
            "sql_directory": str(args.sql_directory),
        }, indent=2))
        return

    supabase_url = os.environ.get("SUPABASE_URL", "").strip()
    service_key = (
        os.environ.get("SUPABASE_SECRET_KEY", "").strip()
        or os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    )
    if not supabase_url or not service_key:
        raise RuntimeError(
            "Set SUPABASE_URL and SUPABASE_SECRET_KEY (or SUPABASE_SERVICE_ROLE_KEY)."
        )
    for start in range(0, len(rows), args.batch_size):
        import_batch(supabase_url, service_key, rows[start : start + args.batch_size])
        print(f"Imported {min(start + args.batch_size, len(rows)):,}/{len(rows):,}", file=sys.stderr)
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
