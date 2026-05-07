// PCCX(TM) — reusable AI accelerator project.
// SPDX-FileCopyrightText: 2026 Hyun Woo Kim
// SPDX-License-Identifier: Apache-2.0

// ===| uCA HAL Implementation |==================================================
// AXI-Lite MMIO access for bare-metal KV260.
// Direct pointer-based memory-mapped I/O — no OS, no mmap, no syscalls.
// ================================================================================

#include "uCA_v1_hal.h"
#include <stddef.h>

// ===| MMIO Base Pointer |=======================================================
// Volatile: prevents the compiler from optimizing away HW reads/writes.
static volatile uint32_t *g_mmio_base = NULL;

// ===| HAL Init / Teardown |=====================================================
int uca_hal_init(void) {
    // On bare-metal KV260, physical addresses are directly accessible.
    g_mmio_base = (volatile uint32_t *)UCA_MMIO_BASE_ADDR;

    // Sanity check: status register reads all-ones on an unconnected AXI bus.
    uint32_t stat = uca_hal_read32(UCA_REG_STATUS);
    if (stat == 0xFFFFFFFFU) {
        return -1;  // Hardware not responding
    }
    return 0;
}

void uca_hal_deinit(void) {
    g_mmio_base = NULL;
}

// ===| Raw Register Access |=====================================================
void uca_hal_write32(uint32_t offset, uint32_t val) {
    g_mmio_base[offset / 4] = val;
}

uint32_t uca_hal_read32(uint32_t offset) {
    return g_mmio_base[offset / 4];
}

// ===| Instruction Issue |=======================================================
void uca_hal_issue_instr(uint64_t instr) {
    // Write lower word first.
    // Writing the upper word triggers the NPU instruction latch (ISA §8).
    uca_hal_write32(UCA_REG_INSTR_LO, (uint32_t)(instr & 0xFFFFFFFFULL));
    uca_hal_write32(UCA_REG_INSTR_HI, (uint32_t)(instr >> 32));
}

// ===| Status Polling |==========================================================
uint32_t uca_hal_read_status(void) {
    return uca_hal_read32(UCA_REG_STATUS);
}

int uca_hal_wait_idle(uint32_t timeout_us) {
    // Bare-metal busy-wait.
    // TODO: replace with a hardware timer once a timer driver is available.
    uint32_t count = timeout_us * 400;  // ~1 iteration per ns at 400 MHz estimate
    while (count--) {
        if (!(uca_hal_read_status() & UCA_STAT_BUSY)) {
            return 0;  // Idle
        }
    }
    return -1;  // Timeout
}
