#!/usr/bin/env bash
# PCCX(TM) — reusable AI accelerator project.
# SPDX-FileCopyrightText: 2026 Hyun Woo Kim
# SPDX-License-Identifier: Apache-2.0

# Guard against committing heavyweight artifacts, private paths, or secrets.

set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MAX_TRACKED_BYTES="${PCCX_ARTIFACT_MAX_TRACKED_BYTES:-10485760}"

failures=0

report_failure() {
    printf '%s\n' "$*"
    failures=$((failures + 1))
}

mapfile -t files < <(
    cd "$ROOT_DIR"
    {
        git ls-files
        git ls-files --others --exclude-standard
    } | sort -u
)

for path in "${files[@]}"; do
    [[ -f "$ROOT_DIR/$path" ]] || continue
    case "$path" in
        hw/build/*|hw/sim/work/*|.git/*)
            continue
            ;;
        *.bit|*.xclbin|*.safetensors|*.gguf|*.pt|*.pth|*.onnx|*.ckpt|*.npy|*.npz)
            report_failure "PROHIBITED_ARTIFACT=$path"
            ;;
        *.bin)
            case "$path" in
                scripts/*|tools/*)
                    ;;
                *)
                    report_failure "PROHIBITED_BIN_ARTIFACT=$path"
                    ;;
            esac
            ;;
    esac

    size="$(wc -c <"$ROOT_DIR/$path")"
    if (( size > MAX_TRACKED_BYTES )); then
        report_failure "LARGE_TRACKED_FILE=$path bytes=$size"
    fi
done

if git -C "$ROOT_DIR" grep -n -I -E '/home/[^[:space:])"]+' -- \
    . \
    ':(exclude)scripts/v002/artifact-safety-check.sh' \
    ':(exclude).gitignore' \
    ':(exclude)docs/internal/**' \
    ':(exclude)docs/evidence/**' \
    ':(exclude)evidence/v002/FINAL_CANDIDATE_SUMMARY.md' \
    ':(exclude)hw/build/**' \
    ':(exclude)hw/sim/work/**'; then
    report_failure "PRIVATE_ABSOLUTE_PATH_FOUND"
fi

if git -C "$ROOT_DIR" grep -n -I -E 'BEGIN (RSA|OPENSSH|EC|DSA) PRIVATE KEY|ghp_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|HF_[A-Za-z0-9_]{20,}' -- \
    . \
    ':(exclude)hw/build/**' \
    ':(exclude)hw/sim/work/**'; then
    report_failure "SECRET_PATTERN_FOUND"
fi

if (( failures )); then
    echo "ARTIFACT_SAFETY=FAIL"
    exit 1
fi

echo "ARTIFACT_SAFETY=PASS"
