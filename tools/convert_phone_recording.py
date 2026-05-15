# convert_phone_recording.py
# Converts phone sensor recordings into the CSV shape used by the Flutter tests.
# The input format is expected to look like the attached recordings in
# `phone_sensor_recordings/`, while the output matches the test fixtures:
# timestamp_ms,user_ax,user_ay,user_az,gyro_x,gyro_y,gyro_z.

from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable, Iterator, Sequence
import sys

OUTPUT_HEADER = [
    "timestamp_ms",
    "user_ax",
    "user_ay",
    "user_az",
    "gyro_x",
    "gyro_y",
    "gyro_z",
]

# The phone recordings in this workspace currently use these column names.
# We keep a small alias map so the converter remains useful if BeamNG exports
# or future recordings rename fields slightly.
COLUMN_ALIASES = {
    "timestamp": ("time", "timestamp", "timestamp_ms", "ts"),
    "user_ax": ("ax", "user_ax", "accel_x", "accelerometer_x"),
    "user_ay": ("ay", "user_ay", "accel_y", "accelerometer_y"),
    "user_az": ("az", "user_az", "accel_z", "accelerometer_z"),
    "gyro_x": ("wx", "gyro_x", "gyroscope_x", "rot_x"),
    "gyro_y": ("wy", "gyro_y", "gyroscope_y", "rot_y"),
    "gyro_z": ("wz", "gyro_z", "gyroscope_z", "rot_z"),
}


@dataclass(frozen=True)
class RecordingRow:
    """Represents one converted sensor sample.

    Attributes:
        timestamp_ms: Milliseconds from the first sample in the recording.
        user_ax/user_ay/user_az: Gravity-removed accelerometer values.
        gyro_x/gyro_y/gyro_z: Gyroscope values.
    """

    timestamp_ms: int
    user_ax: float
    user_ay: float
    user_az: float
    gyro_x: float
    gyro_y: float
    gyro_z: float


def normalize_column_name(name: str) -> str:
    """Normalize a CSV header to simplify alias matching."""

    return name.strip().lower().replace(" ", "_").replace("-", "_")


def resolve_columns(fieldnames: Sequence[str]) -> dict[str, str]:
    """Map expected output fields to the source CSV column names.

    Args:
        fieldnames: Header names discovered in the source CSV.

    Returns:
        A dictionary mapping the canonical output field names to the source
        column names.

    Raises:
        ValueError: If a required input column cannot be found.
    """

    normalized = {normalize_column_name(name): name for name in fieldnames}
    resolved: dict[str, str] = {}
    missing: list[str] = []

    for output_name, aliases in COLUMN_ALIASES.items():
        source_name = next(
            (normalized[normalize_column_name(alias)] for alias in aliases if normalize_column_name(alias) in normalized),
            None,
        )
        if source_name is None:
            missing.append(output_name)
        else:
            resolved[output_name] = source_name

    if missing:
        raise ValueError(
            "Missing required columns in source CSV: " + ", ".join(missing)
        )

    return resolved


def parse_iso_timestamp(value: str) -> datetime:
    """Parse the ISO timestamp used by the phone recordings."""

    cleaned = value.strip().replace("Z", "+00:00")
    parsed = datetime.fromisoformat(cleaned)
    if parsed.tzinfo is None:
        # Treat naive timestamps as UTC so the conversion stays deterministic.
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def iter_recording_rows(
    source_csv: Iterable[str],
    *,
    zero_start: bool = True,
) -> Iterator[RecordingRow]:
    """Yield converted rows from a phone recording CSV.

    Args:
        source_csv: Text lines from the phone recording file.
        zero_start: When true, subtract the first timestamp so the output starts
            at timestamp 0 ms, which is the format used by the Flutter tests.

    Yields:
        Converted recording rows in the test fixture format.
    """

    filtered_lines = (
        line for line in source_csv if line.strip() and not line.lstrip().startswith("#")
    )
    reader = csv.DictReader(filtered_lines)
    if reader.fieldnames is None:
        raise ValueError("Source CSV does not contain a header row")

    columns = resolve_columns(reader.fieldnames)
    first_timestamp: datetime | None = None

    for row in reader:
        source_timestamp = parse_iso_timestamp(row[columns["timestamp"]])
        if first_timestamp is None:
            first_timestamp = source_timestamp

        if zero_start:
            timestamp_ms = int(
                round((source_timestamp - first_timestamp).total_seconds() * 1000)
            )
        else:
            timestamp_ms = int(round(source_timestamp.timestamp() * 1000))

        yield RecordingRow(
            timestamp_ms=timestamp_ms,
            user_ax=float(row[columns["user_ax"]]),
            user_ay=float(row[columns["user_ay"]]),
            user_az=float(row[columns["user_az"]]),
            gyro_x=float(row[columns["gyro_x"]]),
            gyro_y=float(row[columns["gyro_y"]]),
            gyro_z=float(row[columns["gyro_z"]]),
        )


def convert_file(source_path: Path, output_path: Path, *, zero_start: bool = True) -> int:
    """Convert a phone recording CSV into the test fixture format.

    Args:
        source_path: Input phone recording CSV path.
        output_path: Destination CSV path.
        zero_start: When true, rebase timestamps so the first sample starts at 0.

    Returns:
        The number of converted samples written.
    """

    with source_path.open("r", encoding="utf-8-sig", newline="") as source_file:
        rows = list(iter_recording_rows(source_file, zero_start=zero_start))

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8", newline="") as output_file:
        writer = csv.writer(output_file)
        writer.writerow(OUTPUT_HEADER)
        for row in rows:
            writer.writerow(
                [
                    row.timestamp_ms,
                    row.user_ax,
                    row.user_ay,
                    row.user_az,
                    row.gyro_x,
                    row.gyro_y,
                    row.gyro_z,
                ]
            )

    return len(rows)


def build_argument_parser() -> argparse.ArgumentParser:
    """Create the command-line parser for the converter."""

    parser = argparse.ArgumentParser(
        description=(
            "Convert phone sensor recordings into the CSV format used by the "
            "crash-detection tests."
        )
    )
    parser.add_argument("input", type=Path, help="Path to the phone recording CSV")
    parser.add_argument(
        "output",
        type=Path,
        nargs="?",
        help=(
            "Optional output path. If omitted, the converted CSV is written to "
            "standard output."
        ),
    )
    parser.add_argument(
        "--absolute-time",
        action="store_true",
        help=(
            "Write epoch-based timestamps instead of rebasing the first sample "
            "to 0 ms."
        ),
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    """CLI entry point.

    Args:
        argv: Optional argument list for testability.

    Returns:
        A process exit code.
    """

    parser = build_argument_parser()
    args = parser.parse_args(argv)

    try:
        if args.output is None:
            with args.input.open("r", encoding="utf-8-sig", newline="") as source_file:
                rows = list(iter_recording_rows(source_file, zero_start=not args.absolute_time))
            writer = csv.writer(sys.stdout)
            writer.writerow(OUTPUT_HEADER)
            for row in rows:
                writer.writerow(
                    [
                        row.timestamp_ms,
                        row.user_ax,
                        row.user_ay,
                        row.user_az,
                        row.gyro_x,
                        row.gyro_y,
                        row.gyro_z,
                    ]
                )
        else:
            count = convert_file(args.input, args.output, zero_start=not args.absolute_time)
            print(f"Converted {count} samples -> {args.output}")
    except (OSError, ValueError, KeyError, csv.Error) as exc:
        print(f"Conversion failed: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

