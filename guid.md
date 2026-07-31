已重新為您排整這份 **RISC-V CPU Co-Verification (gem5 + UVM)** 規範文件。使用標準的 Markdown 結構（包含標題、程式碼區塊與 ASCII 架構圖）以確保閱讀與複製時格式正確。

---

# Agent Execution Guide: RISC-V CPU Co-Verification Framework (gem5 + UVM)

## 1. Project Goal & System Architecture

### Core Objective

Build an automated, cycle-accurate/instruction-accurate CPU co-verification platform. The framework connects an open-source RISC-V RTL core (DUT) with the gem5 simulation engine (Golden Reference Model) via SystemVerilog DPI-C and UVM, enabling automated **step-by-step lockstep comparison** (DiffTest).

### High-Level Architecture

```text
                         +-----------------------------------------------+
                         |                 UVM Testbench                 |
                         |                                               |
  +-------------------+  |  +-----------------------------------------+  |
  |  ELF / Hex Image  |  |  | UVM Monitor                             |  |
  |  (riscv-tests)    |──┼─>| - Monitors RTL Commit/RVFI signals      |  |
  +---------┬---------+  |  | - Captures PC, Reg Writeback, Mem Ops   |  |
            │            |  +--------------------+--------------------+  |
            │            |                       │                       |
            ▼            |                       │ (Passes via DPI-C)    |
    +---------------+    |                       ▼                       |
    | Open-Source   |    |  +-----------------------------------------+  |
    | RISC-V Core   |────┼─>| DPI-C Bridge / Scoreboard             |  |
    | (DUT)         |    |  | dpi_gem5_step_and_compare()           |  |
    +---------------+    |  +--------------------+--------------------+  |
                         +-----------------------|-----------------------+
                                                 │
                                                 ▼
                         +-----------------------------------------------+
                         |          gem5 Engine (C++ Library)            |
                         |                                               |
                         | - Executes 1 instruction (SE Mode)            |
                         | - Returns Golden PC / Reg State               |
                         +-----------------------------------------------+

```

---

## 2. Directory Structure Blueprint

Generate and strictly maintain the following directory layout:

```text
tb_gem5_uvm_workspace/
├── docs/                           # Architecture docs & DPI interface spec
├── sim/                            # Simulation execution directory
│   ├── Makefile                    # Unified build & run control
│   └── scripts/                    # Automation scripts (Python/Bash)
├── sw/                             # SW binaries executed by CPU
│   ├── common/                     # Cross-ISA linker scripts, CRT0
│   ├── riscv/                      # RISC-V compiler toolchain setup & riscv-tests
│   └── custom_tests/               # Custom assembly / C tests
├── src/                            # Source code
│   ├── rtl/                        # Design Under Test (DUT)
│   │   ├── adapter/                # RTL Signal -> Standard Trace Adapter
│   │   │   └── picorv32_adapter.sv
│   │   └── vendor/                 # Third-party CPU RTL (e.g., PicoRV32)
│   ├── dpi/                        # DPI-C Cross-Language Bridge (C/C++)
│   │   ├── include/
│   │   │   ├── dpi_types.h         # Generic instruction commit data structure
│   │   │   └── dpi_bridge.h        # DPI exported C prototypes
│   │   └── src/
│   │       ├── dpi_bridge.cpp      # DPI entrypoint implementations
│   │       └── gem5_wrapper.cpp    # gem5 C++ Engine controller
│   └── uvm/                        # UVM Testbench Environment
│       ├── env/                    # UVM Environment & Scoreboard
│       ├── agent/                  # Trace Agent, Monitor, Drivers
│       │   ├── trace_monitor.sv
│       │   └── trace_transaction.sv
│       └── tests/                  # UVM Testcases
└── third_party/                    # External dependencies
    └── gem5/                       # gem5 source code (Git Submodule)

```

---

## 3. Implementation Steps for AI Agent

### Phase 1: Environment & Dependency Setup

1. **System Dependencies**: Ensure the following Linux packages are installed:
* **Build & Compilers**: `build-essential`, `clang`, `gcc-10+`, `g++-10+`, `scons`, `m4`
* **Libraries**: `zlib1g-dev`, `python3-dev`, `libprotobuf-dev`, `protobuf-compiler`, `libgoogle-perftools-dev`, `libboost-all-dev`


2. **gem5 Submodule Initialization (Stable Release)**:
* Clone gem5 repository and checkout the official **`stable`** branch:
```bash
git clone -b stable https://github.com/gem5/gem5.git third_party/gem5

```


* Verify standalone build:
```bash
cd third_party/gem5 && scons build/RISCV/gem5.opt -j$(nproc)

```





---

### Phase 2: Interface Abstraction Layer Setup

#### Step 1: Create `src/dpi/include/dpi_types.h`

Define an ISA-agnostic instruction commit structure:

```cpp
#ifndef DPI_TYPES_H
#define DPI_TYPES_H

#include <cstdint>

typedef struct {
    uint64_t pc;            // Instruction Address (supports 32b/64b)
    uint32_t instr_bytes;   // Instruction Machine Code
    uint8_t  reg_write_en;  // Register write enable
    uint8_t  reg_addr;      // Destination register index
    uint64_t reg_data;      // Written data value
    uint8_t  is_mem_op;     // Memory operation flag
    uint64_t mem_addr;      // Memory address (optional)
} generic_commit_t;

#endif // DPI_TYPES_H

```

#### Step 2: Create `src/rtl/adapter/picorv32_adapter.sv`

Map specific CPU trace ports (e.g., PicoRV32 RVFI) to a standardized trace bus:

```systemverilog
module cpu_trace_adapter (
    input  logic        clk,
    // PicoRV32 RVFI Interface
    input  logic        rvfi_valid,
    input  logic [31:0] rvfi_pc_rdata,
    input  logic [ 4:0] rvfi_rd_addr,
    input  logic [31:0] rvfi_rd_wdata,
    // Unified Generic Trace Bus
    output logic        gen_commit_valid,
    output logic [63:0] gen_pc,
    output logic [ 5:0] gen_reg_addr,
    output logic [63:0] gen_reg_data
);
    assign gen_commit_valid = rvfi_valid;
    assign gen_pc           = {32'b0, rvfi_pc_rdata};
    assign gen_reg_addr     = {1'b0, rvfi_rd_addr};
    assign gen_reg_data     = {32'b0, rvfi_rd_wdata};
endmodule

```

---

### Phase 3: DPI-C & gem5 Bridge Implementation

#### Create `src/dpi/src/gem5_wrapper.cpp`

Implement the gem5 execution controller and C-DPI interface wrapper:

```cpp
#include "dpi_types.h"
#include <iostream>

class Gem5Engine {
public:
    Gem5Engine(const char* elf_path) {
        // Initialize gem5 in Syscall Emulation (SE) mode with ELF binary
    }
    
    void step() {
        // Step gem5 by 1 instruction
    }

    generic_commit_t get_golden_commit() {
        generic_commit_t golden;
        // Populate golden commit state from gem5 ThreadContext
        return golden;
    }
};

static Gem5Engine* g_engine = nullptr;

extern "C" {
    void dpi_gem5_init(const char* elf_path) {
        g_engine = new Gem5Engine(elf_path);
    }

    int dpi_gem5_step_and_compare(const generic_commit_t* rtl_commit) {
        if (!g_engine) return -1;

        g_engine->step();
        generic_commit_t golden = g_engine->get_golden_commit();

        // Check PC mismatch
        if (rtl_commit->pc != golden.pc) {
            std::cerr << "[DiffTest ERROR] PC Mismatch! RTL PC: 0x" << std::hex << rtl_commit->pc
                      << " | Golden PC: 0x" << golden.pc << std::endl;
            return 1; // Failure
        }

        // Check Register Writeback mismatch
        if (rtl_commit->reg_write_en && (rtl_commit->reg_data != golden.reg_data)) {
            std::cerr << "[DiffTest ERROR] Reg Data Mismatch @ Reg[" << (int)rtl_commit->reg_addr 
                      << "] RTL: 0x" << std::hex << rtl_commit->reg_data
                      << " | Golden: 0x" << golden.reg_data << std::endl;
            return 1; // Failure
        }

        return 0; // Match Success
    }
}

```

---

### Phase 4: UVM Scoreboard Integration

#### Create `src/uvm/env/uvm_gem5_scoreboard.sv`

Connect UVM Monitor transactions to the DPI comparison engine:

```systemverilog
import uvm_pkg::*;
`include "uvm_macros.svh"

// DPI Import Declarations
import "DPI-C" function void dpi_gem5_init(string elf_path);
import "DPI-C" function int  dpi_gem5_step_and_compare(input bit [511:0] packed_commit);

class uvm_gem5_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(uvm_gem5_scoreboard)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        dpi_gem5_init("sw/custom_tests/hello.elf");
    endfunction

    virtual function void write_rtl_commit(trace_transaction txn);
        int status;
        // Pack transaction into C-struct compatible layout and send to DPI
        status = dpi_gem5_step_and_compare(txn.pack_to_dpi());

        if (status != 0) begin
            `uvm_error("DIFFTEST_MISMATCH", "RTL state diverged from gem5 Golden Model!")
        end else begin
            `uvm_info("DIFFTEST_MATCH", $sformatf("Commit PC: 0x%0h MATCHED", txn.pc), UVM_HIGH)
        end
    endfunction
endclass

```

---

## 4. Verification & Migration Guidelines

### Verification Checklist

1. **Compilation Test**: Build gem5 (`RISCV`) on `stable` branch and compile C++ DPI source into shared library (`.so`).
2. **Sanity Check**: Run `riscv-tests` (e.g., `rv32ui-p-add`) through Verilator/VCS + UVM Testbench.
3. **Fault Injection Verification**: Intentionally modify an ALU instruction result in the RTL source code to ensure the Scoreboard triggers `DIFFTEST_MISMATCH` and halts simulation immediately.

### Migration Rulebook (e.g., RV32 -> RV64 or ARM)

When migrating to a different CPU or ISA, the agent **MUST NOT** modify the UVM Scoreboard or DPI Bridge logic. Only execute the following 3 steps:

1. **RTL Adapter**: Create `src/rtl/adapter/<new_cpu>_adapter.sv` to map the new CPU's trace signals to `generic_commit_t`.
2. **gem5 Engine**: Rebuild gem5 for the target architecture (e.g., `scons build/ARM/gem5.opt`).
3. **Software Toolchain**: Recompile test ELF binaries using the corresponding target ISA toolchain (`sw/`).
