#!/usr/bin/env bash
# PCCX(TM) — reusable AI accelerator project.
# SPDX-FileCopyrightText: 2026 Hyun Woo Kim
# SPDX-License-Identifier: Apache-2.0

# Scan source/docs for unsupported public claims.

set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

PATTERN='KV260 inference works|20 tok/s achieved|timing closed|production-ready|stable release|Gemma 3N E4B runs on KV260'

if git -C "$ROOT_DIR" grep -n -I -i -E "$PATTERN" -- \
    . \
    ':(exclude)scripts/v002/claim-scan.sh' \
    ':(exclude)hw/build/**' \
    ':(exclude)hw/sim/work/**' \
    ':(exclude).git/**'; then
    echo "UNSUPPORTED_CLAIM_FOUND"
    exit 1
fi

echo "UNSUPPORTED_CLAIM_FOUND=no"
