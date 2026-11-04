#!/usr/bin/env python3
"""
Step-Function Attenuation Correlation Module for SatComHub.

This module ingests the main program's factor correlation input JSON (conforming to
Section 4 of README.md) together with an Excel (.xlsx) lookup table defining
step-function attenuation thresholds (in dB) for each environmental factor.

Step-Function Rule:
    Given sorted threshold pairs (T_0, A_0), (T_1, A_1), ..., (T_{k-1}, A_{k-1}):
    - For value < T_0:               attenuation = 0.0 dB
    - For T_i <= value < T_{i+1}:    attenuation = A_i (previous threshold's attenuation)
    - For value >= T_{k-1}:          attenuation = A_{k-1}

    Example:
        Table has: 5 mm/m^2 -> 1 dB, 20 mm/m^2 -> 4 dB
        - value = 0..4.99  -> 0.0 dB
        - value = 5.0      -> 1.0 dB
        - value = 5..19.99 -> 1.0 dB (all values before 20 mm/m^2 take previous 1 dB)
        - value >= 20.0    -> 4.0 dB

Dynamic Factor Validation Rules:
    1. If any factor from the main program input JSON (`factors_list`) is missing from
       the Excel table, the module returns an error message in the output JSON (`status = 1`).
    2. If the factor names in the main program input JSON and the Excel table are not
       identical (e.g., casing differences such as 'Rain_density' vs 'rain_density', or
       the Excel table defines additional factors not present in the input JSON, or
       `factors_list` is empty), a warning message is included in the output JSON.

Usage (CLI):
    python3 modules/step_correlation.py --excel modules/attenuation_table.xlsx < input.json
    python3 modules/step_correlation.py -i input.json -e modules/attenuation_table.xlsx -o output.json
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import sys
import xml.etree.ElementTree as ET
import zipfile
from typing import Any, Dict, List, Optional, Tuple


DEFAULT_EXCEL_FILENAME = "attenuation_table.xlsx"


def _col_letters_to_index(cell_ref: str) -> int:
    """Convert an Excel cell reference like 'A1' or 'BC12' to a 0-based column index."""
    match = re.match(r"^([A-Za-z]+)", cell_ref.strip())
    if not match:
        return 0
    letters = match.group(1).upper()
    col_idx = 0
    for ch in letters:
        col_idx = col_idx * 26 + (ord(ch) - ord("A") + 1)
    return col_idx - 1


def create_default_attenuation_excel(filepath: str) -> None:
    """
    Create a standards-compliant Office Open XML (.xlsx) workbook containing
    the default step-function attenuation lookup table for `rain_density`.
    Uses only Python's standard library (`zipfile`), requiring no third-party packages.
    """
    os.makedirs(os.path.dirname(os.path.abspath(filepath)), exist_ok=True)

    # Default step-function table rows: (factor_name, factor_units, value, attenuation_db)
    rows = [
        ("factor_name", "factor_units", "value", "attenuation_db"),
        ("rain_density", "mm/m^2", 5.0, 1.0),
        ("rain_density", "mm/m^2", 20.0, 4.0),
        ("rain_density", "mm/m^2", 50.0, 8.5),
        ("rain_density", "mm/m^2", 100.0, 15.0),
    ]

    content_types_xml = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
</Types>"""

    rels_xml = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>"""

    workbook_xml = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
          xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="AttenuationTable" sheetId="1" r:id="rId1"/>
  </sheets>
</workbook>"""

    workbook_rels_xml = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>
</Relationships>"""

    shared_strings: List[str] = []
    shared_index: Dict[str, int] = {}

    def get_shared_str_idx(val: str) -> int:
        if val not in shared_index:
            shared_index[val] = len(shared_strings)
            shared_strings.append(val)
        return shared_index[val]

    sheet_rows_xml: List[str] = []
    col_letters = ["A", "B", "C", "D"]

    for r_idx, row in enumerate(rows, start=1):
        cells_xml: List[str] = []
        for c_idx, cell_val in enumerate(row):
            coord = f"{col_letters[c_idx]}{r_idx}"
            if isinstance(cell_val, (int, float)):
                cells_xml.append(f'<c r="{coord}"><v>{cell_val}</v></c>')
            else:
                s_idx = get_shared_str_idx(str(cell_val))
                cells_xml.append(f'<c r="{coord}" t="s"><v>{s_idx}</v></c>')
        sheet_rows_xml.append(f'<row r="{r_idx}">{"".join(cells_xml)}</row>')

    sheet1_xml = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\n'
        "  <sheetData>\n    "
        + "\n    ".join(sheet_rows_xml)
        + "\n  </sheetData>\n</worksheet>"
    )

    si_items = "".join(f"<si><t>{s}</t></si>" for s in shared_strings)
    shared_strings_xml = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        f'<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="{len(shared_strings)}" uniqueCount="{len(shared_strings)}">'
        f"{si_items}</sst>"
    )

    with zipfile.ZipFile(filepath, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("[Content_Types].xml", content_types_xml)
        zf.writestr("_rels/.rels", rels_xml)
        zf.writestr("xl/workbook.xml", workbook_xml)
        zf.writestr("xl/_rels/workbook.xml.rels", workbook_rels_xml)
        zf.writestr("xl/sharedStrings.xml", shared_strings_xml)
        zf.writestr("xl/worksheets/sheet1.xml", sheet1_xml)


def read_xlsx_sheets(filepath: str) -> Dict[str, List[List[Any]]]:
    """
    Read all worksheets from an Excel `.xlsx` file into a dictionary mapping
    sheet_name -> list of rows (each row is a list of cell values).
    Works using pure Python standard library (`zipfile` + `xml.etree.ElementTree`).
    """
    sheets_data: Dict[str, List[List[Any]]] = {}

    with zipfile.ZipFile(filepath, "r") as zf:
        namelist = set(zf.namelist())

        # 1. Load shared strings table if present
        shared_strings: List[str] = []
        if "xl/sharedStrings.xml" in namelist:
            sst_root = ET.fromstring(zf.read("xl/sharedStrings.xml"))
            for si in sst_root.iter():
                if si.tag.endswith("}si") or si.tag == "si":
                    texts = [
                        t.text or ""
                        for t in si.iter()
                        if t.tag.endswith("}t") or t.tag == "t"
                    ]
                    shared_strings.append("".join(texts))

        # 2. Map sheet names to worksheet XML paths
        sheet_targets: List[Tuple[str, str]] = []
        if "xl/workbook.xml" in namelist:
            wb_root = ET.fromstring(zf.read("xl/workbook.xml"))
            rels_map: Dict[str, str] = {}
            if "xl/_rels/workbook.xml.rels" in namelist:
                rels_root = ET.fromstring(zf.read("xl/_rels/workbook.xml.rels"))
                for rel in rels_root.iter():
                    if rel.tag.endswith("}Relationship") or rel.tag == "Relationship":
                        r_id = rel.attrib.get("Id", "")
                        target = rel.attrib.get("Target", "")
                        if r_id and target:
                            if not target.startswith("xl/"):
                                target = "xl/" + target.lstrip("/")
                            rels_map[r_id] = target

            sheet_idx = 1
            for elem in wb_root.iter():
                if elem.tag.endswith("}sheet") or elem.tag == "sheet":
                    name = elem.attrib.get("name", f"Sheet{sheet_idx}")
                    r_id = ""
                    for k, v in elem.attrib.items():
                        if k.endswith("}id") or k == "r:id":
                            r_id = v
                            break
                    target_path = rels_map.get(r_id, f"xl/worksheets/sheet{sheet_idx}.xml")
                    if target_path in namelist:
                        sheet_targets.append((name, target_path))
                    sheet_idx += 1

        if not sheet_targets:
            for item in sorted(namelist):
                if item.startswith("xl/worksheets/sheet") and item.endswith(".xml"):
                    sheet_targets.append((os.path.splitext(os.path.basename(item))[0], item))

        # 3. Parse each worksheet's rows and cells
        for sheet_name, xml_path in sheet_targets:
            ws_root = ET.fromstring(zf.read(xml_path))
            rows_list: List[List[Any]] = []

            for row_elem in ws_root.iter():
                if not (row_elem.tag.endswith("}row") or row_elem.tag == "row"):
                    continue

                row_cells: Dict[int, Any] = {}
                max_col = -1
                next_seq_col = 0

                for cell in row_elem:
                    if not (cell.tag.endswith("}c") or cell.tag == "c"):
                        continue

                    ref = cell.attrib.get("r", "")
                    col_idx = _col_letters_to_index(ref) if ref else next_seq_col
                    next_seq_col = col_idx + 1
                    if col_idx > max_col:
                        max_col = col_idx

                    cell_type = cell.attrib.get("t", "")
                    raw_val: Optional[str] = None

                    if cell_type == "inlineStr":
                        texts = [
                            t.text or ""
                            for t in cell.iter()
                            if t.tag.endswith("}t") or t.tag == "t"
                        ]
                        raw_val = "".join(texts)
                    else:
                        for child in cell:
                            if child.tag.endswith("}v") or child.tag == "v":
                                raw_val = child.text
                                break

                    if raw_val is None:
                        val: Any = ""
                    elif cell_type == "s":
                        try:
                            s_idx = int(raw_val)
                            val = shared_strings[s_idx] if 0 <= s_idx < len(shared_strings) else raw_val
                        except ValueError:
                            val = raw_val
                    elif cell_type in ("str", "inlineStr"):
                        val = str(raw_val)
                    else:
                        try:
                            num = float(raw_val)
                            val = int(num) if num.is_integer() else num
                        except ValueError:
                            val = raw_val

                    row_cells[col_idx] = val

                if max_col >= 0:
                    row_vec = [row_cells.get(c, "") for c in range(max_col + 1)]
                    if any(str(v).strip() != "" for v in row_vec):
                        rows_list.append(row_vec)

            if rows_list:
                sheets_data[sheet_name] = rows_list

    return sheets_data


def _try_float(val: Any) -> Optional[float]:
    if val is None or str(val).strip() == "":
        return None
    try:
        return float(str(val).strip().replace(",", "."))
    except ValueError:
        return None


def parse_excel_factor_tables(filepath: str) -> Dict[str, List[Tuple[float, float]]]:
    """
    Parse an Excel (.xlsx) or CSV file into a mapping:
        { factor_name: [(threshold_value, attenuation_db), ...] }
    where each list of tuples is sorted ascending by `threshold_value`.

    Supports three flexible Excel table layouts:
    1. Row-oriented table with headers:
       `factor_name` | (`factor_units`) | `value` (or `threshold`) | `attenuation_db`
    2. Column-paired table where pairs of columns represent:
       `<factor_name>` | `attenuation_db` (or `<factor_name>_attenuation`)
    3. Multi-sheet workbook where each worksheet name is `<factor_name>` and
       contains two numeric columns: `value` | `attenuation_db`.
    """
    if not os.path.exists(filepath):
        raise FileNotFoundError(f"Excel table file not found: {filepath}")

    ext = os.path.splitext(filepath)[1].lower()
    sheets: Dict[str, List[List[Any]]] = {}

    if ext == ".csv":
        with open(filepath, "r", encoding="utf-8") as f:
            reader = csv.reader(f)
            rows = [r for r in reader if any(c.strip() for c in r)]
            sheets["Sheet1"] = rows
    else:
        sheets = read_xlsx_sheets(filepath)

    factor_tables: Dict[str, List[Tuple[float, float]]] = {}

    for sheet_name, rows in sheets.items():
        if not rows:
            continue

        headers = [str(h).strip() for h in rows[0]]
        headers_lower = [h.lower() for h in headers]

        # Check Layout 1: Long table with `factor_name`, `value`, `attenuation` columns
        factor_col = -1
        val_col = -1
        atten_col = -1

        for idx, h_low in enumerate(headers_lower):
            if h_low in ("factor_name", "factor", "name", "parameter"):
                factor_col = idx
            elif h_low in ("value", "factor_value", "threshold", "level", "density", "input"):
                val_col = idx
            elif "attenuation" in h_low or h_low in ("db", "loss_db", "loss"):
                atten_col = idx

        if factor_col >= 0 and val_col >= 0 and atten_col >= 0:
            for r in rows[1:]:
                if max(factor_col, val_col, atten_col) >= len(r):
                    continue
                f_name = str(r[factor_col]).strip()
                t_val = _try_float(r[val_col])
                a_val = _try_float(r[atten_col])
                if f_name and t_val is not None and a_val is not None:
                    factor_tables.setdefault(f_name, []).append((t_val, a_val))
            continue

        # Check Layout 2: Paired columns [ `<factor_name>`, `attenuation_db`, ... ]
        if len(headers) >= 2:
            paired_found = False
            col = 0
            while col + 1 < len(headers):
                h1 = headers[col]
                h2_low = headers_lower[col + 1]
                if h1 and ("attenuation" in h2_low or h2_low in ("db", "loss_db", "loss")):
                    paired_found = True
                    for r in rows[1:]:
                        if col + 1 >= len(r):
                            continue
                        t_val = _try_float(r[col])
                        a_val = _try_float(r[col + 1])
                        if t_val is not None and a_val is not None:
                            factor_tables.setdefault(h1, []).append((t_val, a_val))
                    col += 2
                else:
                    col += 1
            if paired_found:
                continue

        # Check Layout 3: 2-column sheet where sheet_name or first header is the factor name
        if len(headers) >= 2:
            inferred_factor = (
                headers[0]
                if headers_lower[0] not in ("value", "threshold", "level", "input")
                else sheet_name
            )
            for r in rows[1:]:
                if len(r) < 2:
                    continue
                t_val = _try_float(r[0])
                a_val = _try_float(r[1])
                if t_val is not None and a_val is not None:
                    factor_tables.setdefault(inferred_factor, []).append((t_val, a_val))

    # Sort each factor's thresholds ascending by threshold value
    for f_name, pairs in factor_tables.items():
        pairs.sort(key=lambda item: item[0])

    return factor_tables


def evaluate_step_attenuation(
    value: float,
    thresholds: List[Tuple[float, float]],
) -> float:
    """
    Evaluate step-function attenuation (dB) for a given factor value.

    Given sorted thresholds `[(t_0, a_0), (t_1, a_1), ...]`:
    - If value < t_0: returns 0.0 dB
    - If t_i <= value < t_{i+1}: returns a_i (previous threshold's attenuation)
    - If value >= t_{last}: returns a_{last}
    """
    attenuation = 0.0
    for thresh_val, atten_db in thresholds:
        if value >= thresh_val:
            attenuation = atten_db
        else:
            break
    return attenuation


def run_step_correlation(
    input_data: Dict[str, Any],
    excel_path: str,
) -> Dict[str, Any]:
    """
    Correlate session factor values against the Excel step-function table and return
    the output JSON dictionary conforming to Section 4 of README.md.
    """
    try:
        excel_tables = parse_excel_factor_tables(excel_path)
    except Exception as exc:
        return {
            "total_attenuation_db_list": [],
            "sample_count": 0,
            "status": 1,
            "message": f"Error reading Excel table '{excel_path}': {exc}",
        }

    factors_list = input_data.get("factors_list", [])
    requested_samples = int(
        input_data.get("samples_count", input_data.get("sample_count", 0))
    )

    if not isinstance(factors_list, list):
        return {
            "total_attenuation_db_list": [],
            "sample_count": 0,
            "status": 1,
            "message": "Error: 'factors_list' in input JSON must be a list.",
        }

    excel_factor_names = list(excel_tables.keys())
    excel_lower_map: Dict[str, str] = {k.lower(): k for k in excel_factor_names}

    json_factor_names: List[str] = []
    missing_factors: List[str] = []
    casing_mismatch_warnings: List[str] = []
    resolved_factors: List[Tuple[Dict[str, Any], str]] = []

    for factor_obj in factors_list:
        if not isinstance(factor_obj, dict):
            continue
        f_name = str(factor_obj.get("factor_name", "")).strip()
        if not f_name:
            continue
        json_factor_names.append(f_name)

        if f_name in excel_tables:
            resolved_factors.append((factor_obj, f_name))
        elif f_name.lower() in excel_lower_map:
            matched_excel_name = excel_lower_map[f_name.lower()]
            casing_mismatch_warnings.append(
                f"'{f_name}' (JSON) != '{matched_excel_name}' (Excel)"
            )
            resolved_factors.append((factor_obj, matched_excel_name))
        else:
            missing_factors.append(f_name)

    # Rule 1: If any factors from main program JSON were not in the Excel table -> return error
    if missing_factors:
        return {
            "total_attenuation_db_list": [],
            "sample_count": 0,
            "status": 1,
            "message": (
                f"Error: Factor(s) {missing_factors} from main program JSON were not found "
                f"in Excel table (available Excel factors: {excel_factor_names})."
            ),
        }

    # Determine sample count N
    if requested_samples <= 0 and resolved_factors:
        first_vals = resolved_factors[0][0].get("values", [])
        if isinstance(first_vals, list):
            requested_samples = len(first_vals)

    # Check if factor names in main program JSON and Excel table are identical
    warnings: List[str] = []
    if not json_factor_names:
        warnings.append(
            f"No factors were provided in main program JSON 'factors_list' "
            f"(Excel table expects: {excel_factor_names})."
        )
    else:
        if casing_mismatch_warnings:
            warnings.append(
                "Factor names in main program JSON and Excel table are not identical in casing: "
                + ", ".join(casing_mismatch_warnings)
            )
        used_excel_names = {excel_key for _, excel_key in resolved_factors}
        unused_excel_factors = [
            k for k in excel_factor_names if k not in used_excel_names
        ]
        if unused_excel_factors:
            warnings.append(
                f"Factor names in main program JSON {json_factor_names} and Excel table "
                f"{excel_factor_names} are not identical (Excel factors not in JSON: {unused_excel_factors})."
            )

    total_attenuation_db: List[float] = [0.0] * max(0, requested_samples)

    for factor_obj, excel_key in resolved_factors:
        thresholds = excel_tables.get(excel_key, [])
        raw_values = factor_obj.get("values", [])
        if not isinstance(raw_values, list):
            continue

        if requested_samples <= 0:
            requested_samples = len(raw_values)
            total_attenuation_db = [0.0] * requested_samples

        for i in range(requested_samples):
            val = 0.0
            if i < len(raw_values):
                parsed_v = _try_float(raw_values[i])
                if parsed_v is not None:
                    val = parsed_v
            atten = evaluate_step_attenuation(val, thresholds)
            total_attenuation_db[i] = round(total_attenuation_db[i] + atten, 3)

    if warnings:
        status_message = "Warning: " + " | ".join(warnings)
    else:
        status_message = "Finished"

    return {
        "total_attenuation_db_list": total_attenuation_db,
        "sample_count": requested_samples,
        "status": 0,
        "message": status_message,
    }


def main() -> int:
    fallback_excel = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), DEFAULT_EXCEL_FILENAME
    )
    default_excel = os.environ.get("SATCOMHUB_EXCEL_PATH", "").strip() or fallback_excel

    parser = argparse.ArgumentParser(
        description="SatComHub Step-Function Factor Correlation Module"
    )
    parser.add_argument(
        "-i", "--input",
        type=str,
        default=None,
        help="Path to correlation input JSON file (reads from stdin if omitted).",
    )
    parser.add_argument(
        "-e", "--excel",
        type=str,
        default=default_excel,
        help=f"Path to Excel (.xlsx) factor attenuation table (default: {default_excel}).",
    )
    parser.add_argument(
        "-o", "--output",
        type=str,
        default=None,
        help="Path to output JSON file (writes to stdout if omitted).",
    )
    parser.add_argument(
        "--indent",
        type=int,
        default=4,
        help="JSON output indentation level (default: 4).",
    )
    args = parser.parse_args()

    # Ensure default Excel file exists if default path is used
    if not os.path.exists(args.excel) and os.path.basename(args.excel) == DEFAULT_EXCEL_FILENAME:
        try:
            create_default_attenuation_excel(args.excel)
        except Exception:
            pass

    try:
        if args.input:
            with open(args.input, "r", encoding="utf-8") as f:
                raw_text = f.read()
        else:
            raw_text = sys.stdin.read()

        input_data = json.loads(raw_text)
    except Exception as exc:
        err_out = {
            "total_attenuation_db_list": [],
            "sample_count": 0,
            "status": 1,
            "message": f"Error parsing correlation input JSON: {exc}",
        }
        sys.stdout.write(json.dumps(err_out, indent=args.indent) + "\n")
        return 0

    result = run_step_correlation(input_data, args.excel)
    output_json = json.dumps(result, indent=args.indent)

    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(output_json + "\n")
    else:
        sys.stdout.write(output_json + "\n")

    return 0


if __name__ == "__main__":
    sys.exit(main())
