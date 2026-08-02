# RISC-V CPU Co-Verification Framework

PicoRV32 (RTL DUT) 與 gem5 (golden model) 的鎖步比較驗證平台。
透過 DPI-C 橋接，在 Verilator 模擬中逐指令比對 RVFI 訊號，提供 **DiffTest** 與 **UVM** 兩種測試平台。

---

## 目錄

- [架構總覽](#架構總覽)
- [目錄結構](#目錄結構)
- [快速開始](#快速開始)
- [可配置變數](#可配置變數)
- [測試案例](#測試案例)
- [DPI-C 橋接介面](#dpi-c-橋接介面)
- [如何新增測試](#如何新增測試)
- [實作條件](#實作條件)
- [已知限制](#已知限制)

---

## 架構總覽

```
  sw/custom_tests/test_mem.S
       │
       ▼ riscv64-unknown-elf-gcc -march=rv32imc -Ttext=0x0
  sw/custom_tests/test_mem.elf ──objcopy──► sw/custom_tests/test_mem.hex
       │
       ├──► gem5 SE mode (golden) ──Exec debug log──► generate_trace.py
       │    RiscvAtomicSimpleCPU                        │
       │    RiscvISA(riscv_type="RV32")                  │
       │    --debug-flags=Exec,ExecResult                 │
       │                                                 ▼
       │                                          sim/traces/test_mem.trace
       │                                           (binary golden reference)
       │
       └──► Verilator 5.050 ──► sim/tb_top_diff.sv
            ┌───────────────────┐
            │ PicoRV32 DUT     │── rvfi_valid ──┐
            │ (RV32IMC)        │── rvfi_rd_addr  │
            │                   │── rvfi_rd_wdata ├──► DPI-C compare
            │ SRAM (32KB)      │── rvfi_pc_rdata │   dpi_gem5_step_and_compare()
            │ $readmemh(.hex)  │                 │
            └───────────────────┘                 └──► PASS / FAIL
                                                     自動終止 (dpi_total_entries)
```

**三層流水線**:

| 層 | 目錄 | 說明 |
|----|------|------|
| **sw** | `sw/custom_tests/` | RISC-V 測試程式 (assembly), 連結至 0x0 |
| **trace** | `src/dpi/src/` | gem5 執行 + 日誌解析 → 二進位 golden trace |
| **diff** | `sim/` `src/uvm/` | Verilator 模擬 + DPI-C 鎖步比較 (DiffTest / UVM) |

**雙測試平台** (共用同一條 golden trace 與 DPI-C 橋接):

| 平台 | 指令 | 說明 |
|------|------|------|
| DiffTest | `make diff` | 輕量 testbench `sim/tb_top_diff.sv`，直接以 RVFI 訊號比對 |
| UVM | `make uvm-run` | 標準 UVM testbench `src/uvm/tests/tb_top.sv` (uvm-verilator library) |

**UVM 流程**: `trace_monitor` 捕捉 DUT 的 RVFI commit → 包成 `trace_transaction` → 送往 `uvm_gem5_scoreboard` 呼叫 `dpi_gem5_step_and_compare()` 逐筆與 golden trace 比對 → 比對完所有 entries 後觸發 `uvm_diff_done` 事件自動結束模擬。

---

## 目錄結構

```
├── Makefile                    # 統一建置 (make sw|trace|rtl|diff|uvm|uvm-run)
├── guid.md                     # 舊版 UVM 規劃文件 (僅供參考)
├── readme.md                   # 本文件
│
├── sim/                        # 模擬執行目錄
│   ├── Makefile                # (舊版, 僅供參考)
│   ├── tb_top_diff.sv          # DiffTest testbench (PicoRV32 + SRAM + 比較邏輯)
│   ├── tb_top_rtl.sv           # 純 RTL testbench (無比較)
│   ├── tb_top_uvm.sv           # 舊版 UVM testbench (已由 src/uvm/tests/tb_top.sv 取代)
│   ├── sim_main.cpp            # Verilator C++ wrapper + DPI-C 實現
│   └── traces/                 # 二進位 golden trace 輸出
│
├── src/
│   ├── dpi/
│   │   ├── include/            # dpi_types.h / dpi_bridge.h
│   │   └── src/
│   │       ├── generate_trace.py   # gem5 Exec log → 二進位 trace
│   │       ├── se_trace_config.py  # gem5 SE mode 組態 (RV32)
│   │       └── elf2hex.sh          # ELF → verilog hex 轉換
│   │
│   ├── rtl/
│   │   ├── adapter/
│   │   │   ├── picorv32_sram.sv    # Byte-wide SRAM 模型
│   │   │   ├── picorv32_adapter.sv # RVFI → 標準 trace bus
│   │   │   └── cpu_trace_adapter_if.sv  # UVM virtual interface 定義
│   │   └── vendor/
│   │       └── picorv32/           # PicoRV32 RTL 原始碼
│   │
│   └── uvm/
│       ├── packages/
│       │   └── dpi_bridge_pkg.sv   # DPI-C function import package
│       ├── agent/
│       │   ├── trace_transaction.sv    # commit 交易物件
│       │   └── trace_monitor.sv        # RVFI → transaction
│       ├── env/
│       │   ├── uvm_gem5_env.sv         # UVM environment
│       │   └── uvm_gem5_scoreboard.sv  # DPI-C 鎖步比較 scoreboard
│       └── tests/
│           ├── tb_top.sv              # UVM testbench top (含 DUT / SRAM)
│           └── test_hello.sv          # 範例 testcase
│
├── sw/
│   └── custom_tests/
│       ├── test_add.S          # 基本加法測試
│       ├── test_mem.S          # 記憶體存取測試
│       ├── test_*.S            # 未來新增測試
│       └── *.hex / .elf / .dump / .map  (編譯產物, 不入 git)
│
└── third_party/                # 皆為 git submodule
    ├── gem5/                   # gem5 v25.1.0 (golden model)
    ├── verilator/              # Verilator 5.050 (自建至 install/)
    └── uvm-verilator/          # chipsalliance UVM library
```

---

## 快速開始

```bash
# 基本加法測試 (11 條指令)
make TEST_NAME=test_add NUM_INSTS=30 diff

# 記憶體測試 (31 條指令)
make TEST_NAME=test_mem NUM_INSTS=30 diff

# 產生 VCD 波形
make TEST_NAME=test_mem NUM_INSTS=30 VCD=1 diff
# → sim/dump.vcd

# 僅編譯軟體
make TEST_NAME=test_mem sw

# 僅產生 golden trace
make TEST_NAME=test_mem NUM_INSTS=30 trace

# 僅建置 RTL 模擬器
make TEST_NAME=test_mem rtl

# 建置 UVM testbench
make TEST_NAME=test_add uvm

# 執行 UVM 鎖步比較 (會先 rm -rf obj_dir_uvm 再重編)
make TEST_NAME=test_add NUM_INSTS=30 uvm-run

# 清理建置產物
make clean
make distclean   # 含 .elf / .hex / .dump
```

### 執行結果範例

```
$ make TEST_NAME=test_mem NUM_INSTS=30 diff

[DPI] Loaded 31 trace entries
[DiffTest] Golden trace loaded, starting RTL comparison...
[SRAM] Loaded .../test_mem.hex, first bytes: 17 11 00 00
[DiffTest] PASS: 31 / 31 entries matched, 31 RVFI events
[SIM] Done at 379
```

### UVM 執行結果範例

```
$ make TEST_NAME=test_add NUM_INSTS=30 uvm-run

[SRAM] Loaded .../test_add.hex, first bytes: 15 45 8d 45
UVM_INFO .../uvm_root.svh(476) @ 0: reporter [UVM/RELNOTES]
  ... (UVM library 版權宣告, 以 +UVM_NO_RELNOTES 關閉)
UVM_INFO @ 0: reporter [RNTST] Running test test_hello...
UVM_INFO ../src/uvm/tests/test_hello.sv(12) @ 0: uvm_test_top [BUILD] UVM test_hello building...
[DPI] Loaded 31 trace entries
UVM_INFO ../src/uvm/env/uvm_gem5_scoreboard.sv(25) @ 0: uvm_test_top.env.scb [SCOREBOARD] Golden trace loaded via DPI-C
UVM_INFO ../src/uvm/tests/test_hello.sv(16) @ 0: uvm_test_top [RUN] UVM test running, DPI-C comparison active...
UVM_INFO ../src/uvm/agent/trace_monitor.sv(29) @ 26: uvm_test_top.env.mon [MONITOR] Commit: PC=0x0 Reg[10]=0x5 @ 0
UVM_INFO ../src/uvm/agent/trace_monitor.sv(29) @ 34: uvm_test_top.env.mon [MONITOR] Commit: PC=0x2 Reg[11]=0x3 @ 0
UVM_INFO ../src/uvm/agent/trace_monitor.sv(29) @ 42: uvm_test_top.env.mon [MONITOR] Commit: PC=0x4 Reg[12]=0x8 @ 0
UVM_INFO ../src/uvm/agent/trace_monitor.sv(29) @ 48: uvm_test_top.env.mon [MONITOR] Commit: PC=0x8 Reg[13]=0x0 @ 0
UVM_INFO ../src/uvm/agent/trace_monitor.sv(29) @ 56: uvm_test_top.env.mon [MONITOR] Commit: PC=0xa Reg[0]=0x0 @ 0
... (無窮迴圈內 PC 停於 0xa, 共 31 筆)
[UVM Scoreboard] PASS: 31 / 31 entries matched
UVM_INFO ../src/uvm/tests/test_hello.sv(18) @ 264: uvm_test_top [RUN] UVM diff comparison done, checking results...
--- UVM Report Summary ---
** Report counts by severity
UVM_INFO :   37
UVM_WARNING :    0
UVM_ERROR :    0
UVM_FATAL :    0
** Report counts by id
[BUILD] 1 [MONITOR] 31 [RNTST] 1 [RUN] 2 [SCOREBOARD] 1 [UVM/RELNOTES] 1
../third_party/uvm-verilator/src/base/uvm_root.svh:633: Verilog $finish
[SIM] Done at 265
```

---

## 可配置變數

| 變數 | 預設值 | 說明 |
|------|--------|------|
| `TEST_NAME` | `test_add` | 測試名稱，對應 `sw/custom_tests/<name>.S` |
| `NUM_INSTS` | `10` | gem5 最大指令數 (trace 筆數) |
| `VCD` | `0` | 設為 `1` 啟用 VCD 波形輸出 |
| `TRACE_PATH` | (自動) | golden trace 檔案路徑，預設由 `TEST_NAME` 推導 |
| `HEX_PATH` | (自動) |  SRAM 初始化 hex 路徑，預設由 `TEST_NAME` 推導 |
| `RISCV_TOOL` | `riscv64-unknown-elf` | RISC-V toolchain prefix |

---

## 測試案例

### test_add.S — 基本加法

- **指令數**: 11 (含無窮迴圈)
- **測試項目**: `auipc`, `addi`, `lui`, `c.j`, `c.add`
- **行為**: 計算 5 + 3 = 8 → a2=8, a3=0 (迴圈計數器)

### test_mem.S — 記憶體存取

- **指令數**: 31
- **測試項目**:

| 類別 | 指令 | 數量 |
|------|------|------|
| 定址 | `auipc`, `addi` | 2 |
| 載入常數 | `lui`, `addi`, `li` | 9 |
| 字組存取 | `sw`, `lw` | 6 |
| 位元組存取 | `sb`, `lb` | 6 |
| 半字存取 | `sh`, `lhu`, `lh` | 3 |
| 累加驗證 | `add` (壓縮/非壓縮) | 5 |

### 新增測試待辦

- `test_muldiv.S` — 乘除法 (`MUL`, `DIVU`, `REMU`)
- `test_csr.S` — CSR 存取 (`CSRRW`, `CSRRS`, `CSRRC`)
- `test_irq.S` — 中斷處理

---

## DPI-C 橋接介面

### 函式一覽

| C 函式 | SV 匯入 | 說明 |
|--------|---------|------|
| `dpi_gem5_init(path)` | `dpi_bridge_pkg` | 載入 golden trace 至記憶體 |
| `dpi_gem5_step_and_compare(pc, we, ra, rd)` | `dpi_bridge_pkg` | 比對一筆 RVFI commit vs golden，回傳 0=OK / 1=FAIL |
| `dpi_total_entries()` | `dpi_bridge_pkg` | 回傳 golden trace 總筆數，用於自動停止 |
| `dpi_get_trace_path()` | `dpi_bridge_pkg` | 讀取 `TRACE_PATH` env var |
| `dpi_get_hex_path()` | `picorv32_sram.sv` (直接 import) | 讀取 `HEX_PATH` env var |

### trace 二進位格式

每個 entry 31 bytes, little-endian:

```
Offset  Size  Type        Field
0       8     uint64_t    pc
8       4     uint32_t    insn (保留, 未使用)
12      1     uint8_t     we   (write enable)
13      1     uint8_t     ra   (register address)
14      8     uint64_t    rd   (register data)
22      1     uint8_t     0 (保留)
23      8     uint64_t    0 (保留)
```

產生方式:

```python
pkt = struct.pack('<QIBBQBQ', pc, 0, we, ra, rd, 0, 0)
```

---

## 如何新增測試

三步驟:

1. **寫測試程式** `sw/custom_tests/test_xxx.S`:

```asm
.section .text
.globl _start
_start:
    li   a0, 42
    li   a1, 10
    add  a2, a0, a1    # a2 = 52
loop:
    j loop
```

2. **產生 trace + 執行比較**:

```bash
make TEST_NAME=test_xxx NUM_INSTS=??? diff
```

`NUM_INSTS` 需大於或等於 `test_xxx.S` 的有效指令數。若 golden trace 筆數過少，比對完所有 entry 後即停止；若過多則模擬逾時 (100000 cycle)。

3. **確認比較通過**: 輸出 `PASS: N / N entries matched`

---

## 實作條件

### 工具鏈

| 工具 | 版本 | 說明 |
|------|------|------|
| OS | Ubuntu 26.04 | x86_64, 無 swap |
| GCC | 15.2.0 | 宿主編譯器 |
| Verilator | 5.050 | RTL 模擬器 (git submodule, 自建: `cd third_party/verilator && autoconf && ./configure --prefix=$PWD/install && make -j4 && make install`) |
| gem5 | v25.1.0 | `scons build/RISCV/gem5.opt -j1` (git submodule) |
| RISC-V GCC | riscv64-unknown-elf | `-march=rv32imc -mabi=ilp32` |

### PicoRV32 配置

```systemverilog
picorv32 #(
    .PROGADDR_RESET(32'h0000_0000),   // 程式起始位址
    .STACKADDR(32'h0000_FFFF),        // 堆疊指標初始值
    .COMPRESSED_ISA(1),               // 支援 C 擴展
    .ENABLE_MUL(1),                   // 支援乘法
    .ENABLE_DIV(1),                   // 支援除法
    .ENABLE_IRQ(1),                   // 支援中斷
    .ENABLE_TRACE(1)                  // 啟用 RVFI
)
```

### SRAM 配置

- Byte-wide `reg [7:0] mem_bytes[0:32767]`
- 32KB 容量 (8192 × 4 bytes)
- `$readmemh` 載入測試二進位
- 路徑由 `HEX_PATH` env var 動態傳入

### gem5 配置

- AtomicSimpleCPU, RV32 (RiscvISA)
- Syscall Emulation (SE) mode
- `--debug-flags=Exec,ExecResult`
- 透過 `max_insts_any_thread` 控制執行長度

### Verilator 編譯旗標

```
--timing --cc --top-module tb_top
+define+RISCV_FORMAL
-Wno-fatal -Wno-UNOPTFLAT -Wno-WIDTH ...
```

---

## 已知限制

1. **UVM 相容性**: 舊版 Verilator 5.032 + chipsalliance/uvm-verilator 會觸發 `REFDTYPE` 內部錯誤 (`uvm_phase_hopper.svh:57`)。改用 **Verilator 5.050** (submodule) 後 UVM 已可正常執行 (`make uvm-run`，實測 31/31 PASS)。首次建置需先編譯 Verilator (見[工具鏈](#工具鏈))。

2. **Trace 相依性**: `Makefile` 的 `$(TRACE_FILE)` 相依於 `gem5.opt`, `config.py`, `.elf`，但**不包含** `generate_trace.py` 本身。修改腳本後需手動 `rm -f sim/traces/*.trace`。

3. **單線程建置 gem5**: GCC 15.2.0 + `-jN` (N>1) 會觸發內部編譯器錯誤，現行使用 `-j1`。

4. **無交換空間**: 容器環境無 swap，大量記憶體使用可能導致 OOM。

5. **僅支援 PicoRV32**: SRAM adapter 與 PicoRV32 的原生記憶體介面綁定。更換 DUT 需修改 `tb_top_diff.sv` 與 adapter。
