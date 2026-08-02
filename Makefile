GEM5_DIR   := third_party/gem5
GEM5_BUILD := $(GEM5_DIR)/build/RISCV/gem5.opt
CPU_CONFIG := src/dpi/src/se_trace_config.py

# Verilator 5.050 (git submodule, built from source into install/)
VERILATOR  ?= $(abspath third_party/verilator/install/bin/verilator)

# UVM library (chipsalliance/uvm-verilator submodule)
UVM_DIR    := third_party/uvm-verilator
UVM_SRC    := $(UVM_DIR)/src/uvm_pkg.sv

PICORV32_DIR := src/rtl/vendor/picorv32
SRAM_DIR     := src/rtl/adapter
PKG_DIR      := src/uvm/packages
TRACE_DIR    := sim/traces
SIM_DIR      := sim

RISCV_TOOL ?= riscv64-unknown-elf
RISCV_GCC  ?= $(RISCV_TOOL)-gcc
RISCV_OBJCOPY ?= $(RISCV_TOOL)-objcopy
RISCV_OBJDUMP ?= $(RISCV_TOOL)-objdump

TEST_NAME  ?= test_add
SW_DIR     := sw/custom_tests
TARGET_SRC := $(wildcard $(SW_DIR)/$(TEST_NAME).c $(SW_DIR)/$(TEST_NAME).S)
TARGET_ELF := $(SW_DIR)/$(TEST_NAME).elf
TARGET_HEX := $(SW_DIR)/$(TEST_NAME).hex
TARGET_DUMP := $(SW_DIR)/$(TEST_NAME).dump
TRACE_FILE := $(TRACE_DIR)/$(TEST_NAME).trace

NUM_INSTS ?= 10
VCD      ?= 0
VLT_FLAGS := --timing --cc --top-module tb_top \
             +define+RISCV_FORMAL \
             -Wno-fatal -Wno-UNOPTFLAT -Wno-WIDTH -Wno-CASEINCOMPLETE \
             -Wno-COMBDLY -Wno-MULTIDRIVEN -Wno-TIMESCALEMOD
ifeq ($(VCD),1)
VLT_FLAGS += --trace
endif

.PHONY: all clean distclean sw trace rtl diff uvm uvm-run

all: sw trace rtl

# --- Compile RISC-V test ---
sw: $(TARGET_ELF) $(TARGET_HEX) $(TARGET_DUMP)

$(TARGET_ELF): $(TARGET_SRC) | $(SW_DIR)
	$(RISCV_GCC) -march=rv32imc -mabi=ilp32 -nostdlib \
	  -nostartfiles -ffreestanding -x assembler-with-cpp \
	  -Wl,-Ttext=0x0 -Wl,-Map=$(SW_DIR)/$(TEST_NAME).map \
	  -o $@ $< -lgcc

$(TARGET_HEX): $(TARGET_ELF)
	$(RISCV_OBJCOPY) -O verilog $< $@

$(TARGET_DUMP): $(TARGET_ELF)
	$(RISCV_OBJDUMP) -d $< > $@

# --- Generate golden trace from gem5 ---
trace: $(TRACE_FILE)

$(TRACE_FILE): $(GEM5_BUILD) $(CPU_CONFIG) $(TARGET_ELF) | $(TRACE_DIR)
	python3 src/dpi/src/generate_trace.py \
	  $(GEM5_BUILD) $(CPU_CONFIG) $(TARGET_ELF) $@ $(NUM_INSTS)

# --- Build RTL simulation with DiffTest ---
rtl: $(SIM_DIR)/Vtb_top

$(SIM_DIR)/Vtb_top: $(SIM_DIR)/tb_top_diff.sv \
  $(PICORV32_DIR)/picorv32.v \
  $(SRAM_DIR)/picorv32_sram.sv \
  $(PKG_DIR)/dpi_bridge_pkg.sv \
  $(SIM_DIR)/sim_main.cpp
	cd $(SIM_DIR) && rm -rf obj_dir_diff && \
	$(VERILATOR) $(VLT_FLAGS) \
	  --Mdir obj_dir_diff \
	  --exe sim_main.cpp \
	  ../$(PKG_DIR)/dpi_bridge_pkg.sv \
	  tb_top_diff.sv \
	  ../$(PICORV32_DIR)/picorv32.v \
	  ../$(SRAM_DIR)/picorv32_sram.sv && \
	make -C obj_dir_diff -f Vtb_top.mk -j4

# --- Run simulation ---
diff: rtl trace
	cd $(SIM_DIR) && VCD=$(VCD) TRACE_PATH=$(abspath $(TRACE_FILE)) \
	  HEX_PATH=$(abspath $(TARGET_HEX)) ./obj_dir_diff/Vtb_top

# --- Build UVM testbench ---
UVM_TOP    := src/uvm/tests/tb_top.sv
UVM_FILES  := $(PKG_DIR)/dpi_bridge_pkg.sv \
              src/uvm/agent/trace_transaction.sv \
              src/uvm/agent/trace_monitor.sv \
              src/uvm/env/uvm_gem5_scoreboard.sv \
              src/uvm/env/uvm_gem5_env.sv \
              src/uvm/tests/test_hello.sv \
              src/rtl/adapter/cpu_trace_adapter_if.sv \
              $(UVM_TOP)

uvm: $(SIM_DIR)/Vtb_top_uvm

UVM_VLT_FLAGS := --vpi

$(SIM_DIR)/Vtb_top_uvm: $(UVM_FILES) \
  $(PICORV32_DIR)/picorv32.v \
  $(SRAM_DIR)/picorv32_sram.sv \
  $(SIM_DIR)/sim_main.cpp
	cd $(SIM_DIR) && rm -rf obj_dir_uvm && \
	$(VERILATOR) $(VLT_FLAGS) $(UVM_VLT_FLAGS) \
	  -I../$(UVM_DIR)/src \
	  -CFLAGS -I../$(UVM_DIR)/src/dpi \
	  -CFLAGS -DUVM_VIF \
	  --Mdir obj_dir_uvm \
	  --exe sim_main.cpp \
	  ../$(UVM_SRC) \
	  ../$(UVM_DIR)/src/dpi/uvm_dpi.cc \
	  $(addprefix ../,$(UVM_FILES)) \
	  ../$(PICORV32_DIR)/picorv32.v \
	  ../$(SRAM_DIR)/picorv32_sram.sv && \
	make -C obj_dir_uvm -f Vtb_top.mk -j4

uvm-run: uvm trace
	cd $(SIM_DIR) && VCD=$(VCD) TRACE_PATH=$(abspath $(TRACE_FILE)) \
	  HEX_PATH=$(abspath $(TARGET_HEX)) ./obj_dir_uvm/Vtb_top

# --- Clean ---
clean:
	rm -rf $(SIM_DIR)/obj_dir_diff $(SIM_DIR)/obj_dir_rtl $(SIM_DIR)/obj_dir_uvm
	rm -f $(SIM_DIR)/Vtb_top $(TRACE_FILE)

distclean: clean
	rm -f $(TARGET_ELF) $(TARGET_HEX) $(TARGET_DUMP) $(SW_DIR)/*.map
