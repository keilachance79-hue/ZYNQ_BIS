"""Cross-check simulation CSV, analytic sine convention, and synthesized timing."""
import csv
import hashlib
import json
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BINS = [2,3,7,11,19,37,61,113,199]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    reports = ROOT/'build/reports'
    fixtures = ROOT/'build/fixtures'
    target = ROOT/'verification'
    target.mkdir(exist_ok=True)
    ref = json.loads((fixtures/'reference.json').read_text())
    for name in ('input', 'expected', 'core'):
        assert sha(fixtures/f'{name}.hex') == ref[f'{name}_sha256'], name
    assert sha(ROOT.parent/'Phase3/verification/nine_bins.csv') == ref['phase3_csv_sha256']
    log = (reports/'polar_sim.log').read_text(errors='replace')
    match = re.search(r'PHASE4_POLAR_PASS frames=(\d+) records=(\d+) core_results=(\d+) max_cycles=(\d+)', log)
    if not match or re.search(r'Fatal:|Error:', log):
        raise RuntimeError('No clean simulation PASS')
    frames, records, calls, cycles = map(int, match.groups())
    assert (frames, records, calls) == (ref['frames'], ref['records'], ref['cordic_calls'])
    rows = list(csv.DictReader((reports/'polar_results.csv').open(newline='')))
    expected = [int(s,16) for s in (fixtures/'expected.hex').read_text().split()]
    inputs = [int(s,16) for s in (fixtures/'input.hex').read_text().split()]
    assert len(rows) == records
    def s32(x):
        x &= 0xffffffff
        return x-(1<<32) if x & (1<<31) else x
    for n, (row, word) in enumerate(zip(rows, expected)):
        actual = tuple(map(int, row.values()))
        golden = (1000+n//9, BINS[n%9], word>>256, (word>>128)&0xffffffff,
                  s32(word>>160), (word>>192)&0xffffffff, s32(word>>224))
        assert actual == golden, (n, actual, golden)
    # Independent expected phases for the nine quantized sine fixtures from Phase3.
    # FFT forward sign implies arg(X[k]) = initial sine phase - pi/2.
    phase3 = json.loads((ROOT.parent/'Phase3/verification/digital_result.json').read_text())
    sine_amp_errors, sine_phase_errors = [], []
    for j, bin_number in enumerate(BINS):
        assert phase3['reference']['frames'][2+j]['name'] == f'sine_bin_{bin_number}'
        row = rows[(2+j)*9+j]
        for ch, amplitude, phi in [('v',12000+j*1500,.37*j-.8), ('i',24000-j*1700,-.21*j+.6)]:
            sine_amp_errors.append(abs(int(row[f'{ch}_amp_q14'])/(1<<14)-amplitude))
            sine_phase_errors.append(abs(math.remainder(int(row[f'{ch}_phase_q29'])/(1<<29)+math.pi/2-phi,2*math.pi)))
    assert max(sine_amp_errors) < .05
    assert max(sine_phase_errors) < 1e-5
    same_phase = []
    for n, word in enumerate(inputs):
        v = (s32(word),s32(word>>32)); i = (s32(word>>64),s32(word>>96))
        if v == i and v != (0,0) and int(rows[n]['flags']) == 0x11:
            difference = math.remainder((int(rows[n]['v_phase_q29'])-int(rows[n]['i_phase_q29']))/(1<<29),2*math.pi)
            assert difference == 0
            same_phase.append(n)
    assert same_phase
    config = (reports/'cordic_config.txt').read_text()
    required = {'Functional_Selection':'Translate','Architectural_Configuration':'Word_Serial',
                'Data_Format':'SignedFraction','Phase_Format':'Radians','Input_Width':'32','Output_Width':'32',
                'Coarse_Rotation':'true','Compensation_Scaling':'LUT_based','Round_Mode':'Nearest_Even',
                'Iterations':'0','Precision':'0','ARESETN':'true','flow_control':'Blocking','out_tready':'true'}
    for key, value in required.items():
        assert f'CONFIG.{key} = {value}' in config.splitlines(), key
    synth_log = (ROOT/'synth.log').read_text(errors='replace')
    assert 'PHASE4_SYNTH_PASS' in synth_log and not re.search(r'^ERROR:',synth_log,re.M)
    timing = (reports/'timing_synth.rpt').read_text(errors='replace')
    summary = re.search(r'WNS\(ns\).*?\n\s*-+.*?\n\s*([-\d.]+)\s+([-\d.]+)\s+\d+\s+\d+\s+([-\d.]+)',timing,re.S)
    assert summary
    wns, tns, whs = map(float,summary.groups())
    utilization = (reports/'utilization_synth.rpt').read_text()
    resources = {}
    for key, label in [('lut','Slice LUTs*'),('ff','Slice Registers'),('dsp','DSPs'),('bram_tile','Block RAM Tile')]:
        resources[key] = float(re.search(r'\| '+re.escape(label)+r'\s*\|\s*([\d.]+)',utilization).group(1))
    sources = {p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes().replace(b'\r\n',b'\n')).hexdigest() for folder in ('rtl','sim','scripts','constraints')
               for p in sorted((ROOT/folder).glob('*')) if p.is_file()}
    result = {'stage':'Phase4 digital CORDIC subsystem','date':'2026-10-08','simulation':'PASS',
              'vendor_bit_exact':'PASS','exported_csv':'PASS','sine_convention':'PASS',
              'synthesis_out_of_context':'PASS','internal_timing':'PASS' if wns>=0 and whs>=0 else 'FAIL',
              'wns_ns':wns,'tns_ns':tns,'whs_ns':whs,'resources':resources,
              'frames':frames,'vi_records':records,'core_outputs_compared':calls,
              'max_simulation_frame_cycles':cycles,'target_clock_hz':100000000,
              'sine_amplitude_max_error_adc_codes':max(sine_amp_errors),
              'sine_initial_phase_max_error_rad':max(sine_phase_errors),
              'sine_amplitude_budget_adc_codes':.05,'sine_phase_budget_rad':1e-5,
              'same_phase_record_indices':same_phase,
              'board_implementation':'NOT_RUN','live_phase2_phase3_phase4_rtl':'NOT_RUN',
              'ps_dma':'NOT_RUN','bench':'NOT_RUN','tools':{'vivado':'2020.2','python':sys.version.split()[0]},
              'source_sha256_lf':sources,'reference':ref}
    for name in ('cordic_config.txt','polar_results.csv','utilization_synth.rpt','timing_synth.rpt','drc_synth.rpt'):
        (target/name).write_bytes((reports/name).read_bytes())
    (target/'simulation_summary.txt').write_text(match.group(0)+'\n',encoding='utf-8')
    (target/'digital_result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ('source_sha256_lf','reference')}))
    if wns<0 or whs<0:
        raise RuntimeError('Internal timing not met; evidence retained')


if __name__ == '__main__':
    main()
