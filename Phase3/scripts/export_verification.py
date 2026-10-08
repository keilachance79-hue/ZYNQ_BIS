"""Validate and export compact evidence; generated IP/runtime binaries stay local."""
import hashlib
import json
import re
import sys
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[1]


def main():
    reports = ROOT / 'build/reports'
    target = ROOT / 'verification'
    target.mkdir(exist_ok=True)
    log = (reports/'fft_sim.log').read_text(errors='replace')
    match = re.search(r'PHASE3_FFT_PASS frames=(\d+) complex_outputs=(\d+) selected_pairs=(\d+) max_cycles=(\d+)', log)
    if not match or re.search(r'Fatal:|Error:', log):
        raise RuntimeError('No clean simulation PASS')
    frames, complex_outputs, pairs, cycles = map(int, match.groups())
    reference = json.loads((ROOT/'build/fixtures/reference.json').read_text())
    for name in ('input', 'golden'):
        if hashlib.sha256((ROOT/f'build/fixtures/{name}.hex').read_bytes()).hexdigest() != reference[f'{name}_sha256']:
            raise ValueError(f'{name} fixtures changed since model generation')
    config = (reports/'fft_config.txt').read_text()
    for key, value in {'transform_length': '2048', 'implementation_options': 'pipelined_streaming_io',
                       'input_width': '16', 'phase_factor_width': '24', 'scaling_options': 'unscaled',
                       'rounding_modes': 'convergent_rounding', 'output_ordering': 'natural_order',
                       'xk_index': 'true', 'aresetn': 'true', 'throttle_scheme': 'nonrealtime'}.items():
        if f'CONFIG.{key} = {value}' not in config.splitlines():
            raise ValueError(f'FFT configuration does not match reference: {key}')
    if frames != len(reference['frames']) or complex_outputs != frames*4096 or pairs != frames*9:
        raise ValueError('Simulation/reference coverage mismatch')
    raw = ROOT.parent/'Phase2/build/reports/raw_capture.csv'
    if hashlib.sha256(raw.read_bytes()).hexdigest() != reference['phase2_raw_sha256']:
        raise ValueError('Phase2 raw file changed since fixture generation')
    # Check exported wire-format integers independently of the SV scoreboard.
    values = np.genfromtxt(reports/'nine_bins.csv', delimiter=',', names=True, dtype=np.int64)
    golden = [int(s, 16) for s in (ROOT/'build/fixtures/golden.hex').read_text().split()]
    if len(values) != pairs:
        raise ValueError('Wrong selected-bin row count')
    def signed32(x):
        x &= 0xffffffff
        return x-(1<<32) if x&(1<<31) else x
    for i, row in enumerate(values):
        frame, slot = divmod(i, 9)
        bin_number = reference['bins'][slot]
        vr = golden[frame*4096+bin_number]
        ir = golden[frame*4096+2048+bin_number]
        expected = (100+frame, bin_number, signed32(vr), signed32(vr>>32), signed32(ir), signed32(ir>>32))
        if tuple(row) != expected:
            raise ValueError(f'Nine-bin CSV mismatch row {i}')
    synth_log = (ROOT/'synth.log').read_text(errors='replace')
    if 'PHASE3_SYNTH_PASS' not in synth_log or re.search(r'^ERROR:', synth_log, re.M):
        raise RuntimeError('Synthesis not complete or errored')
    timing = (reports/'timing_synth.rpt').read_text(errors='replace')
    summary = re.search(r'WNS\(ns\).*?\n\s*-+.*?\n\s*([-\d.]+)\s+([-\d.]+)\s+\d+\s+\d+\s+([-\d.]+)', timing, re.S)
    if not summary:
        raise ValueError('Timing summary not found')
    wns, tns, whs = map(float, summary.groups())
    sources = {}
    for folder in ('rtl', 'sim', 'scripts', 'constraints'):
        for file in sorted((ROOT/folder).glob('*')):
            if file.is_file():
                sources[file.relative_to(ROOT).as_posix()] = hashlib.sha256(file.read_bytes()).hexdigest()
    result = {'stage': 'Phase3 digital FFT subsystem', 'date': '2026-10-08',
              'simulation': 'PASS', 'vendor_bit_exact': 'PASS', 'selected_bin_csv': 'PASS',
              'synthesis_out_of_context': 'PASS', 'wns_ns': wns, 'tns_ns': tns, 'whs_ns': whs,
              'internal_timing': 'PASS' if wns>=0 and whs>=0 else 'FAIL',
              'board_implementation': 'NOT_RUN', 'phase2_live_rtl_integration': 'NOT_RUN',
              'ps_dma': 'NOT_RUN', 'bench': 'NOT_RUN',
              'frames': frames, 'complex_outputs_compared': complex_outputs, 'selected_vi_pairs': pairs,
              'max_simulation_frame_cycles': cycles, 'target_clock_hz': 100000000,
              'tools': {'vivado': '2020.2', 'python': sys.version.split()[0], 'numpy': np.__version__},
              'source_sha256': sources, 'reference': reference}
    for name in ('fft_config.txt','nine_bins.csv','utilization_synth.rpt','timing_synth.rpt','drc_synth.rpt'):
        (target/name).write_bytes((reports/name).read_bytes())
    markers = [line for line in log.splitlines() if 'FRAME_PASS' in line or 'PHASE3_FFT_PASS' in line]
    (target/'simulation_summary.txt').write_text('\n'.join(markers)+'\n', encoding='utf-8')
    (target/'digital_result.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({k: result[k] for k in ('simulation','vendor_bit_exact','frames','complex_outputs_compared','selected_vi_pairs','wns_ns','whs_ns','internal_timing')}))
    if wns<0 or whs<0:
        raise RuntimeError('Internal target timing not met; evidence retained')


if __name__ == '__main__':
    main()
