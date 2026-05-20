from __future__ import annotations

import numpy as np
import pytest

from sw.runtime.gemma import ops
import sw.runtime.npu as npu_module


def _weights32() -> np.ndarray:
    return ((np.arange(32 * 32, dtype=np.int16) % 16) - 8).reshape(32, 32).astype(np.int8)


def _activations32() -> np.ndarray:
    return (((np.arange(32 * 32, dtype=np.int16) * 3) % 256) - 128).reshape(32, 32).astype(np.int8)


def test_matmul_int4_int8_reference_matches_numpy_exactly() -> None:
    weights = _weights32()
    activations = _activations32()

    expected = activations.astype(np.int32) @ weights.astype(np.int32)

    np.testing.assert_array_equal(
        ops.matmul_int4_int8_reference(weights, activations),
        expected,
    )


def test_matmul_int4_int8_uses_npu_runtime_and_compares_reference(monkeypatch) -> None:
    weights = _weights32()
    activations = _activations32()
    expected = ops.matmul_int4_int8_reference(weights, activations)
    calls = []

    def fake_matmul(W: np.ndarray, X: np.ndarray) -> np.ndarray:
        calls.append((np.asarray(W).copy(), np.asarray(X).copy()))
        return expected

    monkeypatch.setattr(npu_module, "npu_matmul_int4_int8", fake_matmul)

    out = ops.matmul_int4_int8(weights, activations, backend="npu")

    np.testing.assert_array_equal(out, expected)
    assert len(calls) == 1
    np.testing.assert_array_equal(calls[0][0], weights)
    np.testing.assert_array_equal(calls[0][1], activations)


def test_matmul_int4_int8_raises_on_npu_reference_mismatch(monkeypatch) -> None:
    weights = _weights32()
    activations = _activations32()
    wrong = ops.matmul_int4_int8_reference(weights, activations).copy()
    wrong[0, 0] += 1

    monkeypatch.setattr(npu_module, "npu_matmul_int4_int8", lambda W, X: wrong)

    with pytest.raises(AssertionError, match="did not match NumPy reference"):
        ops.matmul_int4_int8(weights, activations, backend="npu")


def test_matmul_int4_int8_reference_backend_is_dev_only(monkeypatch) -> None:
    weights = np.array([[1, -2], [3, -4]], dtype=np.int8)
    activations = np.array([[5, -6], [7, -8]], dtype=np.int8)
    expected = activations.astype(np.int32) @ weights.astype(np.int32)

    monkeypatch.delenv("PCCX_DEV_MODE", raising=False)
    with pytest.raises(RuntimeError, match="PCCX_DEV_MODE=1"):
        ops.matmul_int4_int8(weights, activations, backend="cpu")

    monkeypatch.setenv("PCCX_DEV_MODE", "1")
    np.testing.assert_array_equal(
        ops.matmul_int4_int8(weights, activations, backend="cpu"),
        expected,
    )


def test_matmul_int4_int8_auto_uses_reference_only_in_dev_mode(monkeypatch) -> None:
    weights = np.array([[1, -2], [3, -4]], dtype=np.int8)
    activations = np.array([[5, -6], [7, -8]], dtype=np.int8)
    expected = activations.astype(np.int32) @ weights.astype(np.int32)

    def broken_matmul(W: np.ndarray, X: np.ndarray) -> np.ndarray:
        raise RuntimeError("not configured")

    monkeypatch.setattr(npu_module, "npu_matmul_int4_int8", broken_matmul)

    monkeypatch.delenv("PCCX_DEV_MODE", raising=False)
    with pytest.raises(RuntimeError, match="NPU matmul dispatch failed"):
        ops.matmul_int4_int8(weights, activations, backend="auto")

    monkeypatch.setenv("PCCX_DEV_MODE", "1")
    np.testing.assert_array_equal(
        ops.matmul_int4_int8(weights, activations, backend="auto"),
        expected,
    )
