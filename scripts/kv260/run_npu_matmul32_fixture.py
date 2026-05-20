#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys
import time

import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from sw.runtime.gemma.ops import matmul_int4_int8, matmul_int4_int8_reference


def fixture_tensors() -> tuple[np.ndarray, np.ndarray]:
    weights = ((np.arange(32 * 32, dtype=np.int16) % 16) - 8).reshape(32, 32)
    activations = (((np.arange(32 * 32, dtype=np.int16) * 3) % 256) - 128).reshape(32, 32)
    return weights.astype(np.int8), activations.astype(np.int8)


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the Stage 1 NPU matmul32 fixture")
    parser.add_argument("--backend", choices=("auto", "npu", "cpu"), default="npu")
    args = parser.parse_args()

    weights, activations = fixture_tensors()
    reference = matmul_int4_int8_reference(weights, activations)
    started = time.perf_counter()
    result = matmul_int4_int8(weights, activations, backend=args.backend)
    elapsed_sec = time.perf_counter() - started
    match = np.array_equal(result, reference)
    if not match:
        raise SystemExit("matmul32 fixture mismatch")

    digest = hashlib.sha256()
    digest.update(weights.tobytes())
    digest.update(activations.tobytes())
    digest.update(reference.astype("<i4", copy=False).tobytes())
    print(
        json.dumps(
            {
                "backend_requested": args.backend,
                "bit_for_bit_match": True,
                "elapsed_sec": round(elapsed_sec, 6),
                "fixture_sha256": digest.hexdigest(),
                "shape": [32, 32],
            },
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
