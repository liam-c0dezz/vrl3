"""Read the repair costbook into a small JSON payload for local smoke tests.

The workbook is opened read-only. This script never saves or modifies it.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from openpyxl import load_workbook


def number(value: object) -> float:
    if isinstance(value, (int, float)):
        return float(value)
    return 0.0


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("workbook", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    workbook = load_workbook(args.workbook, read_only=True, data_only=True)
    sheet = workbook["Costbook Export"]
    rows = []
    for source_row, values in enumerate(
        sheet.iter_rows(min_row=2, values_only=True), start=2
    ):
        category, description = values[0], values[1]
        if not category and not description:
            continue
        rows.append(
            {
                "sourceRow": source_row,
                "category": str(category or "").strip(),
                "description": str(description or "").strip(),
                "materialCost": number(values[2]),
                "laborCost": number(values[3]),
                "directCost": number(values[4]),
                "equipmentCost": number(values[6]),
                "unit": str(values[7] or "").strip(),
                "crewCode": str(values[9] or "").strip(),
            }
        )

    payload = {
        "source": args.workbook.name,
        "sheet": sheet.title,
        "rowCount": len(rows),
        "rows": rows,
    }
    args.output.write_text(json.dumps(payload, separators=(",", ":")))
    print(json.dumps({"output": str(args.output), "rowCount": len(rows)}))


if __name__ == "__main__":
    main()
