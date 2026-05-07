#!/usr/bin/env bash
# PCCX(TM) — reusable AI accelerator project.
# SPDX-FileCopyrightText: 2026 Hyun Woo Kim
# SPDX-License-Identifier: Apache-2.0

# Produce a bounded throughput report from KV260/runtime evidence.

set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INPUT=""

usage() {
    cat <<'USAGE'
usage: scripts/v002/run-throughput-report.sh [--input <summary.txt>]

Options:
  --input <path>  runtime evidence summary to parse
  -h, --help      print this help
USAGE
}

while (($#)); do
    case "$1" in
        --input)
            if (($# < 2)); then
                echo "error: --input requires a path" >&2
                exit 2
            fi
            INPUT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "error: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ -z "$INPUT" ]]; then
    INPUT="$(find "$ROOT_DIR/docs/evidence/kv260-gemma3n-e4b" -mindepth 2 -maxdepth 2 -name summary.txt 2>/dev/null | sort | tail -n 1 || true)"
fi

if [[ -z "$INPUT" ]]; then
    python3 "$ROOT_DIR/tools/v002/estimate_tokens_per_second.py" --input "$ROOT_DIR/docs/evidence/kv260-gemma3n-e4b/MISSING_SUMMARY.txt"
    exit $?
fi

python3 "$ROOT_DIR/tools/v002/estimate_tokens_per_second.py" --input "$INPUT"
