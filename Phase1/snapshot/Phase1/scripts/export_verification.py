"""Archive checked digital evidence; never labels OOC results as board signoff."""
from pathlib import Path
import hashlib
import json
import platform
import re
import shutil
import numpy as np

ROOT = Path(__file__).resolve().parents[1]


def main():
    reports = ROOT / 'build/reports'
    target = ROOT / 'verification'
    target.mkdir(exist_ok=True)
    markers = {}
    for name, marker in [('tb_dac_player', 'PHASE1_PLAYER_PASS'),
                         ('tb_phase1_dac', 'PHASE1_TOP_PASS')]:
        log = (reports / (name + '.log')).read_text()
        assert marker in log and not re.search(r'Fatal:|Error:', log), name
        markers[name] = next(line for line in log.splitlines() if marker in line)
    synth = (ROOT / 'build_synth.log').read_text()
    assert 'PHASE1_SYNTH_PASS' in synth and not re.search(r'^ERROR:', synth, re.M)
    drc = (reports / 'drc_synth.rpt').read_text()
    violations = re.findall(r'^([A-Z][A-Z0-9]*-\d+)#\d+\s+(\w+)', drc, re.M)
    assert all(rule == 'ZPS7-1' and severity == 'Warning' for rule, severity in violations), violations
    timing = (reports / 'timing_synth.rpt').read_text()
    assert 'All user specified timing constraints are met.' in timing
    assert 'checking no_clock (0)' in timing
    assert 'checking unconstrained_internal_endpoints (0)' in timing
    check = json.loads((target / 'waveform_check.json').read_text())
    assert check['status'] == 'PASS' and check['capture_epochs'] == 2
    assert check['reproducible_exports']
    for name in ['utilization_synth', 'clocks_synth', 'timing_synth', 'cdc_synth', 'drc_synth']:
        shutil.copyfile(reports / (name + '.rpt'), target / (name + '.rpt'))
    hashes = {}
    for folder in ['rtl', 'sim', 'scripts', 'constraints', 'generated']:
        for path in sorted((ROOT / folder).rglob('*')):
            if path.is_file() and '__pycache__' not in path.parts:
                hashes[path.relative_to(ROOT).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    hashes['config.json'] = hashlib.sha256((ROOT / 'config.json').read_bytes()).hexdigest()
    result = dict(simulation='PASS', synthesis_out_of_context='PASS',
                  board_implementation='NOT_RUN', bench_measurement='NOT_RUN',
                  part='xc7z020clg400-2', reference_clock_hz=50000000,
                  python=platform.python_version(), numpy=np.__version__,
                  vivado='2020.2', simulation_markers=markers,
                  allowed_ooc_drc=violations,
                  capture_sha256=hashlib.sha256((reports / 'dac_capture.csv').read_bytes()).hexdigest(),
                  waveform_check=check, input_sha256=hashes,
                  limitations=['PACKAGE_PIN and bank VCCO not confirmed',
                               'PCB skew and oscillator jitter not budgeted',
                               'PS7 integration required before Zynq board implementation',
                               'OOC clock-source location, reset and debug I/O timing pending'])
    (target / 'digital_result.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print('PHASE1_EVIDENCE_PASS: simulation and OOC synthesis; board acceptance pending')


if __name__ == '__main__':
    main()
