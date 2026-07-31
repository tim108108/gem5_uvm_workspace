#!/usr/bin/env python3
"""Post-process gem5 Exec debug log into binary golden trace."""

import re
import sys
import struct
import subprocess
import os

RV_REG_NAMES = {
    'zero': 0, 'ra': 1, 'sp': 2, 'gp': 3, 'tp': 4,
    't0': 5, 't1': 6, 't2': 7,
    's0': 8, 'fp': 8, 's1': 9,
    'a0': 10, 'a1': 11, 'a2': 12, 'a3': 13,
    'a4': 14, 'a5': 15, 'a6': 16, 'a7': 17,
    's2': 18, 's3': 19, 's4': 20, 's5': 21,
    's6': 22, 's7': 23, 's8': 24, 's9': 25,
    's10': 26, 's11': 27,
    't3': 28, 't4': 29, 't5': 30, 't6': 31,
}

REG_NAME_RE = re.compile(r'\b(' + '|'.join(RV_REG_NAMES.keys()) + r')\b')

LINE_PC = r'(?:0x(?P<pc_hex>[0-9a-fA-F]+)|(?P<pc_dec>\d+))'

LINE_RE = re.compile(
    r'^\s*(?P<tick>\d+):\s+\S+:\s+T\d+\s*:\s+'
    + LINE_PC +
    r'(?:\s+@\S+)?\s*:\s+'
    r'(?P<disasm>[^:]+?)'
    r'(?:\s*:\s+\S+(?:\s+\S+)*)?'
    r'\s*:\s+D=0x(?P<data>[0-9a-fA-F]+)'
    r'(?:\s+\S+=0x[0-9a-fA-F]+)*'
    r'\s*$'
)

LINE_RE_NODATA = re.compile(
    r'^\s*(?P<tick>\d+):\s+\S+:\s+T\d+\s*:\s+'
    + LINE_PC +
    r'(?:\s+@\S+)?\s*:\s+'
    r'(?P<disasm>[^:]+?)'
    r'(?:\s*:\s+\S+(?:\s+\S+)*)?'
    r'\s*$'
)

def _parse_pc(m):
    if m.group('pc_hex') is not None:
        return int(m.group('pc_hex'), 16)
    return int(m.group('pc_dec'))

def parse_line(line):
    m = LINE_RE.match(line)
    if m:
        pc = _parse_pc(m)
        disasm = m.group('disasm').strip()
        data = int(m.group('data'), 16)

        opcode = disasm.split()[0] if disasm else ''
        is_store = opcode in ('sb', 'sh', 'sw', 'c_sb', 'c_sh', 'c_sw', 'c_swsp')

        reg_we = 0
        reg_addr = 0
        if not is_store:
            reg_match = REG_NAME_RE.search(disasm)
            if reg_match:
                reg_addr = RV_REG_NAMES[reg_match.group(1)]
                if reg_addr != 0:
                    reg_we = 1

        return (pc, reg_we, reg_addr, data)

    m = LINE_RE_NODATA.match(line)
    if m:
        pc = _parse_pc(m)
        return (pc, 0, 0, 0)

    return None

def generate(gem5_path, config_path, elf_path, output_path, max_insts=100000):
    tmp_log = f'/tmp/gem5_{os.getpid()}.debug.log'

    try:
        subprocess.run(
            [gem5_path, '--debug-flags=Exec,ExecResult',
             f'--debug-file={tmp_log}',
             config_path, elf_path, str(max_insts)],
            capture_output=True, check=True
        )
    except subprocess.CalledProcessError as e:
        print(f"gem5 error: {e.stderr.decode()}", file=sys.stderr)
        return 0

    count = 0
    with open(output_path, 'wb') as fout, open(tmp_log) as fin:
        for line in fin:
            result = parse_line(line)
            if result is None:
                continue
            pc, reg_we, reg_addr, reg_data = result
            pkt = struct.pack('<QIBBQBQ',
                pc, 0, reg_we, reg_addr, reg_data, 0, 0)
            fout.write(pkt)
            count += 1

    os.unlink(f'/tmp/gem5_{os.getpid()}.debug.log')
    print(f"Generated {count} trace entries -> {output_path}", file=sys.stderr)
    return count

if __name__ == '__main__':
    if len(sys.argv) < 5:
        print(f"Usage: {sys.argv[0]} <gem5.opt> <config.py> <elf> <output.trace> [max_insts]", file=sys.stderr)
        sys.exit(1)
    generate(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4],
             int(sys.argv[5]) if len(sys.argv) > 5 else 100000)
