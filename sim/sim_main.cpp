#include <verilated.h>
#if VM_TRACE_VCD
#include <verilated_vcd_c.h>
#endif
#include "Vtb_top.h"
#include "Vtb_top___024root.h"
#include <cstdio>
#include <cstring>
#include <cstdlib>

// --- DPI-C bridge for DiffTest ---

typedef struct {
    unsigned long long pc;
    unsigned int insn;
    unsigned char we;
    unsigned char ra;
    unsigned long long rd;
} commit_t;

static commit_t* g_trace;
static int g_entries;
static int g_idx;

extern "C" void dpi_gem5_init(const char* trace_path) {
    FILE* f = fopen(trace_path, "rb");
    if (!f) { fprintf(stderr, "[DPI] Cannot open %s\n", trace_path); exit(1); }
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    g_entries = sz / 31;
    g_trace = (commit_t*)calloc(g_entries, sizeof(commit_t));
    for (int i = 0; i < g_entries; i++) {
        unsigned char buf[31];
        if (fread(buf, 1, 31, f) != 31) break;
        memcpy(&g_trace[i].pc, buf, 8);
        memcpy(&g_trace[i].insn, buf+8, 4);
        g_trace[i].we = buf[12];
        g_trace[i].ra = buf[13];
        memcpy(&g_trace[i].rd, buf+14, 8);
    }
    fclose(f);
    g_idx = 0;
    printf("[DPI] Loaded %d trace entries\n", g_entries);
}

extern "C" int dpi_gem5_step_and_compare(
    unsigned long long pc,
    unsigned char we,
    unsigned char ra,
    unsigned long long rd
) {
    if (g_idx >= g_entries) return 0;
    commit_t* g = &g_trace[g_idx];
    int fail = 0;
    if (pc != g->pc) fail = 1;
    if (we != g->we) fail = 1;
    if (ra != g->ra) fail = 1;
    if (g->we && rd != g->rd) fail = 1;
    if (fail) {
        printf("[DPI FAIL] entry %d: PC=0x%08llx (exp 0x%08llx) ra=%d (exp %d) rd=0x%08llx (exp 0x%08llx) we=%d (exp %d)\n",
            g_idx, pc, g->pc, ra, g->ra, rd, g->rd, we, g->we);
    }
    g_idx++;
    return fail;
}

extern "C" int dpi_gem5_get_remaining() {
    return g_entries - g_idx;
}

extern "C" int dpi_total_entries() {
    return g_entries;
}

extern "C" const char* dpi_get_trace_path() {
    const char* path = getenv("TRACE_PATH");
    return path ? path : "/workspace/gem5_uvm_workspace/sim/traces/test_add.trace";
}

extern "C" const char* dpi_get_hex_path() {
    const char* path = getenv("HEX_PATH");
    return path ? path : "";
}

// --- Simulation main ---

vluint64_t main_time = 0;
double sc_time_stamp() { return main_time; }

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    const char* vcd_env = getenv("VCD");
    int do_vcd = vcd_env && atoi(vcd_env);

#if VM_TRACE_VCD
    Verilated::traceEverOn(do_vcd);
    VerilatedVcdC* tfp = nullptr;
    if (do_vcd) {
        tfp = new VerilatedVcdC;
    }
#else
    if (do_vcd) {
        fprintf(stderr, "[SIM] VCD requested but not compiled in (need --trace)\n");
    }
#endif

    Vtb_top* top = new Vtb_top;
    auto* r = top->rootp;

#if VM_TRACE_VCD
    if (tfp) {
        top->trace(tfp, 99);
        tfp->open("dump.vcd");
    }
#endif

    r->tb_top__DOT__clk = 0;
    r->tb_top__DOT__resetn = 0;
    top->eval();
#if VM_TRACE_VCD
    if (tfp) tfp->dump(main_time);
#endif

    for (int i = 0; i < 10; i++) {
        r->tb_top__DOT__clk = !r->tb_top__DOT__clk;
        top->eval();
        main_time++;
#if VM_TRACE_VCD
        if (tfp) tfp->dump(main_time);
#endif
    }
    r->tb_top__DOT__resetn = 1;

    while (!Verilated::gotFinish() && main_time < 50000) {
        r->tb_top__DOT__clk = !r->tb_top__DOT__clk;
        top->eval();
        main_time++;
#if VM_TRACE_VCD
        if (tfp) tfp->dump(main_time);
#endif
    }

    top->final();
#if VM_TRACE_VCD
    if (tfp) tfp->close();
#endif
    delete top;
    printf("[SIM] Done at %lu\n", (unsigned long)main_time);
    return 0;
}
