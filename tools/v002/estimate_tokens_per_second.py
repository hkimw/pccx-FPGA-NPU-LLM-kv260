#!/usr/bin/env python3
# PCCX(TM) — reusable AI accelerator project.
# SPDX-FileCopyrightText: 2026 Hyun Woo Kim
# SPDX-License-Identifier: Apache-2.0

"""Estimate measured throughput from runtime evidence when complete enough."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


NUMBER_RE = re.compile(r"^[0-9]+(\.[0-9]+)?$")


def parse_key_value(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if "=" not in line or line.lstrip().startswith("#"):
            continue
        key, value = line.split("=", 1)
        data[key.strip()] = value.strip()
    return data


def numeric(value: str | None) -> float | None:
    if value is None or value in {"", "unknown", "null", "None"}:
        return None
    if not NUMBER_RE.match(value):
        return None
    return float(value)


def estimate(data: dict[str, str], source: Path) -> dict[str, Any]:
    token_count = numeric(data.get("token_count") or data.get("TOKEN_COUNT"))
    elapsed_sec = numeric(data.get("elapsed_sec") or data.get("ELAPSED_SEC"))
    reported_tps = numeric(data.get("tok_per_sec") or data.get("TOK_PER_SEC"))

    required_evidence = {
        "git_commit": data.get("git_commit") or data.get("GIT_COMMIT"),
        "bitstream_sha256": data.get("bitstream_sha256") or data.get("BITSTREAM_SHA256"),
        "model_manifest": data.get("model_manifest") or data.get("MODEL_MANIFEST"),
        "command_line": data.get("command_line") or data.get("COMMAND_LINE"),
    }
    missing = [
        key
        for key, value in required_evidence.items()
        if value is None or value == "" or value == "unknown"
    ]

    measured: float | None = None
    status = "MEASUREMENT_NOT_AVAILABLE"
    reason = "runtime evidence does not include token count and elapsed seconds"

    if token_count is not None and elapsed_sec is not None and elapsed_sec > 0:
        measured = token_count / elapsed_sec
        reason = ""
        status = "MEASUREMENT_EVIDENCE_INCOMPLETE" if missing else "MEASUREMENT_AVAILABLE"
    elif reported_tps is not None:
        measured = reported_tps
        reason = ""
        status = "MEASUREMENT_EVIDENCE_INCOMPLETE" if missing else "MEASUREMENT_AVAILABLE"

    if missing and measured is not None:
        reason = "missing required evidence fields: " + ", ".join(missing)
        measured_output: float | None = None
    else:
        measured_output = measured

    return {
        "schema_version": 1,
        "source": str(source),
        "status": status,
        "reason": reason,
        "target_tokens_per_second": 20,
        "measured_tokens_per_second": (
            round(measured_output, 3) if measured_output is not None else None
        ),
        "raw_token_count": int(token_count) if token_count is not None else None,
        "raw_elapsed_sec": elapsed_sec,
        "required_evidence_missing": missing,
        "unsupported_claims": {
            "twenty_tokens_per_second_achieved": False,
            "kv260_inference_success": False,
        },
    }


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Estimate measured tok/s only when runtime evidence is complete."
    )
    parser.add_argument("--input", required=True, type=Path, help="summary.txt or key=value evidence file")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if not args.input.is_file():
        print(
            json.dumps(
                {
                    "schema_version": 1,
                    "source": str(args.input),
                    "status": "MEASUREMENT_NOT_AVAILABLE",
                    "reason": "input evidence file not found",
                    "target_tokens_per_second": 20,
                    "measured_tokens_per_second": None,
                },
                indent=2,
                sort_keys=True,
            )
        )
        return 2

    payload = estimate(parse_key_value(args.input), args.input)
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if payload["status"] == "MEASUREMENT_AVAILABLE" else 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
