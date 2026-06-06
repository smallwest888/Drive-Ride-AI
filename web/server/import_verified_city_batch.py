#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import sqlite3
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Import verified city parking TSV files into prparking.db."
    )
    parser.add_argument(
        "--db",
        required=True,
        help="Path to target SQLite database.",
    )
    parser.add_argument(
        "--source-dir",
        required=True,
        help="Directory containing *_parking_lots_verified.tsv files.",
    )
    parser.add_argument(
        "--mode",
        choices=["missing-only", "replace"],
        default="missing-only",
        help="missing-only: import cities not already present; replace: delete and reimport matched cities.",
    )
    return parser.parse_args()


def to_int(value: str | None) -> int:
    value = (value or "").strip()
    return int(value) if value else 0


def to_float(value: str | None) -> float | None:
    value = (value or "").strip()
    return float(value) if value else None


def to_bool(value: str | None) -> int:
    return 1 if (value or "").strip().lower() in {"yes", "true", "1"} else 0


def load_city_rows(tsv_path: Path) -> list[dict[str, str]]:
    with tsv_path.open(encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter="\t")
        return list(reader)


def import_city(
    conn: sqlite3.Connection, city: str, rows: list[dict[str, str]], replace: bool
) -> tuple[int, int]:
    cur = conn.cursor()
    cur.execute("SELECT COUNT(*) FROM PRParkings WHERE city = ?", (city,))
    before = cur.fetchone()[0]

    if replace and before:
        cur.execute("DELETE FROM PRParkings WHERE city = ?", (city,))

    if before and not replace:
        return before, 0

    inserted = 0
    sql = """
        INSERT INTO PRParkings (
            name, address, latitude, longitude, totalSpaces, pricePerHour,
            city, facilities, publicTransport, operatingHours, contactPhone,
            notes, isActive, createdAt, updatedAt
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'))
    """
    for row in rows:
        cur.execute(
            sql,
            (
                row["停车场名称"].strip(),
                row["地址"].strip(),
                to_float(row["纬度"]),
                to_float(row["经度"]),
                to_int(row["总车位数"]),
                to_float(row["每小时价格(€)"]),
                row["城市"].strip(),
                (row.get("设施") or "").strip(),
                (row.get("公共交通") or "").strip(),
                (row.get("营业时间") or "").strip(),
                (row.get("联系电话") or "").strip(),
                (row.get("备注") or "").strip(),
                to_bool(row.get("是否活跃")),
            ),
        )
        inserted += 1

    return before, inserted


def main() -> None:
    args = parse_args()
    db_path = Path(args.db)
    source_dir = Path(args.source_dir)

    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA foreign_keys = ON")

    imported_cities: list[tuple[str, int, int]] = []
    skipped_cities: list[tuple[str, int]] = []

    try:
        for tsv_path in sorted(source_dir.glob("*_parking_lots_verified.tsv")):
            rows = load_city_rows(tsv_path)
            if not rows:
                continue
            city = rows[0]["城市"].strip()
            before, inserted = import_city(
                conn, city, rows, replace=(args.mode == "replace")
            )
            if inserted:
                imported_cities.append((city, before, inserted))
            else:
                skipped_cities.append((city, before))

        conn.commit()

        cur = conn.cursor()
        cur.execute("SELECT COUNT(*), COUNT(DISTINCT city) FROM PRParkings")
        total_rows, total_cities = cur.fetchone()

        print(f"Imported cities: {len(imported_cities)}")
        for city, before, inserted in imported_cities:
            print(f"IMPORTED\t{city}\tbefore={before}\tinserted={inserted}")

        print(f"Skipped cities: {len(skipped_cities)}")
        for city, before in skipped_cities:
            print(f"SKIPPED\t{city}\texisting={before}")

        print(f"TOTAL\trows={total_rows}\tcities={total_cities}")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
