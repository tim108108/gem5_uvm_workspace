# RISC-V CPU Co-Verification Framework

PicoRV32 (RTL DUT) 與 gem5 (golden model) 的鎖步比較驗證平台。
透過 DPI-C 橋接，在 Verilator 模擬中逐指令比對 RVFI 訊號。

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
  sw/test_mem.S
       │
       ▼ riscv64-unknown-elf-gcc -march=rv32imc -Ttext=0x0
  sw/test_mem.elf ──objcopy──► sw/test_mem.hex
       │
       ├──► gem5 SE mode (golden) ──Exec debug log──► generate_trace.py
       │    RiscvAtomicSimpleCPU                        │
       │    RiscvISA(riscv_type="RV32")                  │
       │    --debug-flags=Exec,ExecResult                 │
       │                                                 ▼
       │                                          sim/traces/test_mem.trace
       │                                           (binary golden reference)
       │
       └──► Verilator 5.032 ──► sim/tb_top_diff.sv
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
| **diff** | `sim/` | Verilator 模擬 + DPI-C 鎖步比較 |

---

## 目錄結構

```
├── Makefile                    # 統一建置 (make sw|trace|rtl|diff)
├── guid.md                     # 舊版 UVM 規劃文件 (僅供參考)
├── readme.md                   # 本文件
│
├── sim/                        # 模擬執行目錄
│   ├── tb_top_diff.sv          # DiffTest testbench (PicoRV32 + SRAM + 比較邏輯)
│   ├── tb_top_rtl.sv           # 純 RTL testbench (無比較)
│   ├── sim_main.cpp            # Verilator C++ wrapper + DPI-C 實現
│   └── traces/                 # 二進位 golden trace 輸出
│
├── src/
│   ├── dpi/src/
│   │   ├── generate_trace.py   # gem5 Exec log → 二進位 trace
│   │   └── se_trace_config.py  # gem5 SE mode 組態 (RV32)
│   │
│   ├── rtl/
│   │   ├── adapter/
│   │   │   └── picorv32_sram.sv  # Byte-wide SRAM 模型
│   │   └── vendor/
│   │       └── picorv32/         # PicoRV32 RTL 原始碼
│   │
│   └── uvm/packages/
│       └── dpi_bridge_pkg.sv     # DPI-C function import package
│
├── sw/
│   └── custom_tests/
│       ├── test_add.S          # 基本加法測試
│       ├── test_mem.S          # 記憶體存取測試
│       ├── test_*.S            # 未來新增測試
│       └── *.hex / .elf / .dump / .map  (編譯產物)
│
└── third_party/
    └── gem5/                   # gem5 v25.1.0.1 (git submodule)
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
| `dpi_get_trace_path()` | 無 (SV 呼叫) | 讀取 `TRACE_PATH` env var |
| `dpi_get_hex_path()` | 無 (SV 呼叫) | 讀取 `HEX_PATH` env var |

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
| Verilator | 5.032 | RTL 模擬器 |
| gem5 | v25.1.0.1 | `scons build/RISCV/gem5.opt -j1` |
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

1. **UVM 不相容**: Verilator 5.032 + chipsalliance/uvm-verilator 觸發 `REFDTYPE` 內部錯誤 (`uvm_phase_hopper.svh:57`)。目前使用輕量 DPI-C 框架取代 UVM。

2. **Trace 相依性**: `Makefile` 的 `$(TRACE_FILE)` 相依於 `gem5.opt`, `config.py`, `.elf`，但**不包含** `generate_trace.py` 本身。修改腳本後需手動 `rm -f sim/traces/*.trace`。

3. **單線程建置 gem5**: GCC 15.2.0 + `-jN` (N>1) 會觸發內部編譯器錯誤，現行使用 `-j1`。

4. **無交換空間**: 容器環境無 swap，大量記憶體使用可能導致 OOM。

5. **僅支援 PicoRV32**: SRAM adapter 與 PicoRV32 的原生記憶體介面綁定。更換 DUT 需修改 `tb_top_diff.sv` 與 adapter。
