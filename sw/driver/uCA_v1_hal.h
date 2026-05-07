// PCCX(TM) — reusable AI accelerator project.
// SPDX-FileCopyrightText: 2026 Hyun Woo Kim
// SPDX-License-Identifier: Apache-2.0

// ===| uCA HAL (Hardware Abstraction Layer) |=====================================
// Low-level AXI-Lite MMIO register access for the uCA NPU.
// This layer owns all physical address reads/writes.
// Nothing above this layer should touch hardware addresses directly.
//
// uCA: micro Compute Architecture — the FPGA NPU driver stack.
// Target: Kria KV260 bare-metal (no OS, no mmap)
// Interface: AXI-Lite (HPM port) at UCA_MMIO_BASE_ADDR
// ================================================================================

#ifndef UCA_V1_HAL_H
#define UCA_V1_HAL_H

#include <stdint.h>

// ===| MMIO Base Address |=======================================================
// Must match the AXI-Lite slave address assigned in the Vivado block design.
#define UCA_MMIO_BASE_ADDR  0xA0000000UL

// ===| Register Offsets |========================================================
// All offsets are byte offsets from UCA_MMIO_BASE_ADDR.
// The 64-bit instruction register is split into two 32-bit words.
// Write LO first; writing HI triggers the NPU instruction latch.
#define UCA_REG_INSTR_LO    0x00  // [31:0]  lower 32 bits of 64-bit VLIW instruction
#define UCA_REG_INSTR_HI    0x04  // [63:32] upper 32 bits; writing this latches the instruction
#define UCA_REG_STATUS      0x08  // [31:0]  NPU status (read-only)

// ===| Status Register Bit Fields |==============================================
#define UCA_STAT_BUSY       (1U << 0)  // NPU is executing — do not issue new instruction
#define UCA_STAT_DONE       (1U << 1)  // Last operation completed successfully

// ===| HAL Init / Teardown |=====================================================
int  uca_hal_init(void);    // Set MMIO base pointer and verify hardware presence
void uca_hal_deinit(void);  // Nullify MMIO base pointer

// ===| Raw Register Access |=====================================================
void     uca_hal_write32(uint32_t offset, uint32_t val);
uint32_t uca_hal_read32(uint32_t offset);

// ===| Instruction Issue |=======================================================
// Writes a 64-bit VLIW instruction to the NPU (LO then HI).
// Caller must ensure the NPU is idle (UCA_STAT_BUSY == 0) before calling.
void uca_hal_issue_instr(uint64_t instr);

// ===| Status Polling |==========================================================
uint32_t uca_hal_read_status(void);
int      uca_hal_wait_idle(uint32_t timeout_us);  // 0 = success, -1 = timeout

#endif // UCA_V1_HAL_H
