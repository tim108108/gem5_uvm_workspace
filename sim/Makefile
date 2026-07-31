WORKSPACE := /workspace/gem5_uvm_workspace
GEM5 := $(WORKSPACE)/third_party/gem5/build/RISCV/gem5.opt
CONFIG := $(WORKSPACE)/src/dpi/src/se_trace_config.py
GEN_TRACE := $(WORKSPACE)/src/dpi/src/generate_trace.py
DPI_SRC := $(WORKSPACE)/src/dpi/src/gem5_wrapper.cpp
DPI_INC := $(WORKSPACE)/src/dpi/include
ELF_DIR := $(WORKSPACE)/sw/custom_tests
TRACE_DIR := $(WORKSPACE)/sim/traces
OBJ_DIR := $(WORKSPACE)/sim/obj

RISCV_CC := riscv64-unknown-elf-gcc

.PHONY: all clean elf trace test

all: trace

$(ELF_DIR)/%.elf: $(ELF_DIR)/%.S
	$(RISCV_CC) -nostdlib -Wl,-Bstatic -o $@ $<

elf: $(ELF_DIR)/test_add.elf

$(TRACE_DIR)/%.trace: $(ELF_DIR)/%.elf | $(TRACE_DIR)
	python3 $(GEN_TRACE) $(GEM5) $(CONFIG) $< $@ 100000

$(TRACE_DIR):
	mkdir -p $(TRACE_DIR)

trace: $(TRACE_DIR)/test_add.trace

test: trace
	python3 -c "import struct; \
	  f=open('$(TRACE_DIR)/test_add.trace','rb'); \
	  [ exec('d=f.read(31); \
	    pc,ins,we,ra,rd,mem,ma=struct.unpack(\"<QIBBQBQ\",d); \
	    print(f\"PC=0x{pc:016x} we={we} ra={ra} rd=0x{rd:016x}\")') \
	    for d in iter(lambda: f.read(31), b'') if len(d)==31 ]"

clean:
	rm -rf $(TRACE_DIR) $(OBJ_DIR)
