"""Aggregate consented device reports, one CSV row per shared snapshot."""

import argparse
import csv
from collections import defaultdict
from datetime import datetime, timedelta, timezone

WINDOW = timedelta(days=7)


def aggregate(rows, cutoff):
    reports = defaultdict(list)
    for participant, first, second, observed in rows:
        if first > observed or (second and not first < second <= observed):
            raise ValueError(f"Invalid chronology for {participant}")
        if observed <= cutoff:
            reports[participant].append((first, second, observed))

    eligible = known = returned = 0
    for participant, snapshots in reports.items():
        first = snapshots[0][0]
        if any(start != first for start, _, _ in snapshots):
            raise ValueError(f"First session changed for {participant}")
        deadline = first + WINDOW
        if deadline > cutoff:
            continue
        eligible += 1
        reused = any(second and second <= deadline for _, second, _ in snapshots)
        returned += int(reused)
        known += int(reused or any(observed >= deadline for _, _, observed in snapshots))
    return eligible, known, returned


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv_file")
    parser.add_argument("--as-of", default=datetime.now(timezone.utc).isoformat())
    args = parser.parse_args()
    with open(args.csv_file, newline="", encoding="utf-8-sig") as data:
        rows = [
            (row["participant"], datetime.fromisoformat(row["first_start"]),
             datetime.fromisoformat(row["second_start"]) if row["second_start"] else None,
             datetime.fromisoformat(row["observed_at"]))
            for row in csv.DictReader(data)
        ]
    eligible, known, returned = aggregate(rows, datetime.fromisoformat(args.as_of))
    rate = f"{returned / known:.1%}" if known else "집계 불가"
    print(f"7일 재사용률 {rate} ({returned}/{known})")
    print(f"확인된 결과 {known}명 | 7일 경과 {eligible}명 | 결과 미확인 {eligible - known}명")


if __name__ == "__main__":
    main()
