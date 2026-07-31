import m5, sys, os
from m5.objects import *

binary = sys.argv[1]
max_insts = int(sys.argv[2]) if len(sys.argv) > 2 else 100000

system = System()
system.clk_domain = SrcClockDomain()
system.clk_domain.clock = "1GHz"
system.clk_domain.voltage_domain = VoltageDomain()
system.mem_mode = "atomic"
system.mem_ranges = [AddrRange("512MiB")]
system.cpu = RiscvAtomicSimpleCPU()
system.cpu.isa = RiscvISA(riscv_type="RV32")

system.membus = SystemXBar()
system.cpu.icache_port = system.membus.cpu_side_ports
system.cpu.dcache_port = system.membus.cpu_side_ports
system.cpu.createInterruptController()

system.mem_ctrl = MemCtrl()
system.mem_ctrl.dram = DDR3_1600_8x8()
system.mem_ctrl.dram.range = system.mem_ranges[0]
system.mem_ctrl.port = system.membus.mem_side_ports
system.system_port = system.membus.cpu_side_ports

system.workload = SEWorkload.init_compatible(binary)
process = Process()
process.cmd = [binary]
system.cpu.workload = process
system.cpu.createThreads()

root = Root(full_system=False, system=system)
system.cpu.max_insts_any_thread = max_insts
m5.instantiate()

exit_event = m5.simulate()
cause = exit_event.getCause()
print(f"@@DONE@@ cause={cause}")
