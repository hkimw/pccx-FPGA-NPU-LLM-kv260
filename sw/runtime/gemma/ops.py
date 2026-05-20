"""NumPy Gemma 3N E4B primitive operations.

Depends on Core Secrets 1-7: no RMSNorm plus-one, tanh AltUp routing,
unscaled attention helpers, RoPE theta cycling, Gaussian Top-K FFN sparsity,
and LAuReL/PLE scaling rules.
"""
from __future__ import annotations

import os

import numpy as np

from .arch import GemmaArch
from .core_secrets import (
    ALTUP_ROUTER_SCALE_DIM,
    GAUSSIAN_TOPK_SIGMA,
    LAUREL_SCALE,
)


_TRUTHY = {"1", "true", "yes", "on"}


def rms_norm(x: np.ndarray, gamma: np.ndarray | None = None, *, eps: float = 1e-6) -> np.ndarray:
    x_f32 = np.asarray(x, dtype=np.float32)
    rms = np.sqrt(np.mean(x_f32 * x_f32, axis=-1, keepdims=True) + eps)
    out = x_f32 / rms
    if gamma is not None:
        out = out * np.asarray(gamma, dtype=np.float32)
    return np.asarray(out, dtype=np.float32)


def gelu(x: np.ndarray) -> np.ndarray:
    x_f32 = np.asarray(x, dtype=np.float32)
    return 0.5 * x_f32 * (1.0 + np.tanh(np.sqrt(2.0 / np.pi) * (x_f32 + 0.044715 * x_f32 ** 3)))


def gaussian_topk(x: np.ndarray) -> np.ndarray:
    x_f32 = np.asarray(x, dtype=np.float32)
    threshold = float(np.mean(x_f32) + GAUSSIAN_TOPK_SIGMA * np.std(x_f32))
    return np.where(x_f32 >= threshold, x_f32, 0.0).astype(np.float32)


def gaussian_topk_gelu(x: np.ndarray) -> np.ndarray:
    return gelu(gaussian_topk(x))


def softmax(x: np.ndarray) -> np.ndarray:
    x_f32 = np.asarray(x, dtype=np.float32)
    shifted = x_f32 - np.max(x_f32, axis=-1, keepdims=True)
    exp = np.exp(shifted)
    return exp / np.sum(exp, axis=-1, keepdims=True)


def rope_rotate(x: np.ndarray, *, layer_idx: int, pos: int, arch: GemmaArch) -> np.ndarray:
    x_f32 = np.asarray(x, dtype=np.float32)
    original_shape = x_f32.shape
    heads = x_f32.reshape(-1, arch.head_dim)
    even = heads[:, 0::2]
    odd = heads[:, 1::2]
    inv_freq = 1.0 / (
        arch.rope_theta(layer_idx)
        ** (np.arange(0, arch.head_dim, 2, dtype=np.float32) / float(arch.head_dim))
    )
    angle = float(pos) * inv_freq
    cos = np.cos(angle)
    sin = np.sin(angle)
    rotated = np.empty_like(heads)
    rotated[:, 0::2] = even * cos - odd * sin
    rotated[:, 1::2] = even * sin + odd * cos
    return rotated.reshape(original_shape)


def laurel_add(attn_output: np.ndarray, laurel_output: np.ndarray) -> np.ndarray:
    return (np.asarray(attn_output, dtype=np.float32) + np.asarray(laurel_output, dtype=np.float32)) * LAUREL_SCALE


def altup_route(x: np.ndarray, w_norm: np.ndarray, w_router: np.ndarray) -> np.ndarray:
    x_n = rms_norm(x, w_norm) / ALTUP_ROUTER_SCALE_DIM
    return np.tanh(np.dot(x_n, np.asarray(w_router, dtype=np.float32))).astype(np.float32)


def matmul_int4_int8_reference(weights: np.ndarray, activations: np.ndarray) -> np.ndarray:
    """Signed INT4 x signed INT8 reference for one matrix multiply."""
    weights_i8 = _as_int4_matrix(weights)
    activations_i8 = _as_int8_matrix(activations)
    if weights_i8.shape[0] != activations_i8.shape[1]:
        raise ValueError(
            "matmul shape mismatch: activations must be [M, K] and weights [K, N]"
        )
    return np.matmul(
        activations_i8.astype(np.int32),
        weights_i8.astype(np.int32),
    ).astype(np.int32)


def matmul_int4_int8(
    weights: np.ndarray,
    activations: np.ndarray,
    *,
    backend: str = "auto",
    compare_reference: bool = True,
) -> np.ndarray:
    """Dispatch Stage 1 signed INT4 x signed INT8 matmul through the NPU."""
    requested = str(backend or "auto").strip().lower()
    reference = matmul_int4_int8_reference(weights, activations)
    if requested == "cpu":
        if _dev_fallback_allowed():
            return reference
        raise RuntimeError("backend='cpu' is only allowed when PCCX_DEV_MODE=1")

    try:
        from sw.runtime.npu import npu_matmul_int4_int8
    except Exception as exc:
        if requested == "auto" and _dev_fallback_allowed():
            return reference
        raise RuntimeError(f"NPU matmul runtime is unavailable: {exc}") from exc

    try:
        result = np.asarray(
            npu_matmul_int4_int8(weights, activations),
            dtype=np.int32,
        )
    except Exception as exc:
        if requested == "auto" and _dev_fallback_allowed():
            return reference
        raise RuntimeError(f"NPU matmul dispatch failed: {exc}") from exc
    if compare_reference and not np.array_equal(result, reference):
        raise AssertionError("NPU matmul result did not match NumPy reference")
    return result


def _as_int4_matrix(value: np.ndarray) -> np.ndarray:
    arr = np.asarray(value)
    if arr.ndim != 2:
        raise ValueError("INT4 weights must be a rank-2 matrix")
    rounded = np.rint(arr.astype(np.float32))
    if not np.array_equal(rounded, arr.astype(np.float32)):
        raise ValueError("INT4 weights must contain integer values")
    out = rounded.astype(np.int8)
    if np.any(out < -8) or np.any(out > 7):
        raise ValueError("INT4 weights must be in [-8, 7]")
    return np.ascontiguousarray(out)


def _as_int8_matrix(value: np.ndarray) -> np.ndarray:
    arr = np.asarray(value)
    if arr.ndim != 2:
        raise ValueError("INT8 activations must be a rank-2 matrix")
    rounded = np.rint(arr.astype(np.float32))
    if not np.array_equal(rounded, arr.astype(np.float32)):
        raise ValueError("INT8 activations must contain integer values")
    out = rounded.astype(np.int16)
    if np.any(out < -128) or np.any(out > 127):
        raise ValueError("INT8 activations must be in [-128, 127]")
    return np.ascontiguousarray(out.astype(np.int8))


def _dev_fallback_allowed() -> bool:
    return os.getenv("PCCX_DEV_MODE", "").strip().lower() in _TRUTHY
