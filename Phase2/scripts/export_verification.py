"""Export evidence with digital prototype and hardware acceptance kept separate."""
from pathlib import Path
import hashlib
import json
import platform
import re
import numpy as np

ROOT=Path(__file__).resolve().parents[1]

def main():
    source=ROOT/'build/reports'; out=ROOT/'verification'; out.mkdir(exist_ok=True)
    sim=(source/'capture.log').read_text()
    assert 'PHASE2_CAPTURE_PASS:' in sim and not re.search(r'Fatal:|Error:',sim)
    marker=next(x for x in sim.splitlines() if x.startswith('PHASE2_CAPTURE_PASS:'))
    synth=(ROOT/'build_synth.log').read_text()
    assert '\nPHASE2_SYNTH_PASS:' in synth and not re.search(r'^ERROR:|^CRITICAL WARNING:',synth,re.M)
    assert 'not a valid startpoint' not in synth
    timing=(source/'timing_synth.rpt').read_text()
    assert 'All user specified timing constraints are met.' in timing
    assert 'checking no_clock (0)' in timing and 'checking unconstrained_internal_endpoints (0)' in timing
    drc=(source/'drc_synth.rpt').read_text()
    drcs=re.findall(r'^([A-Z][A-Z0-9]*-\d+)#\d+\s+(\w+)',drc,re.M)
    assert all(rule in ['PLIO-6','ZPS7-1'] and severity=='Warning' for rule,severity in drcs),drcs
    cdc=(source/'cdc_synth.rpt').read_text()
    cdc_summary=re.findall(r'^(CDC-\d+)\s+(Info|Warning|Critical)\s+(\d+)\s+(.+)$',cdc,re.M)
    assert cdc_summary and all(rule in ['CDC-3','CDC-6','CDC-26'] and sev!='Critical' for rule,sev,_,_ in cdc_summary)
    check=json.loads((out/'capture_check.json').read_text()); assert check['status']=='PASS'
    pins=(out/'package_pins.txt').read_text()
    assert 'U18 IO_L12P_T1_MRCC_34' in pins
    assert 'W8 IO_L15N_T2_DQS_13' in pins and 'U8 IO_L17N_T2_13' in pins
    for name in ['timing_synth','utilization_synth','cdc_synth','drc_synth','bus_skew_synth']:
        (out/(name+'.rpt')).write_text((source/(name+'.rpt')).read_text(),encoding='utf-8',newline='\n')
    hashes={}
    for folder in ['rtl','sim','scripts','constraints','generated']:
        for p in sorted((ROOT/folder).rglob('*')):
            if p.is_file() and '__pycache__' not in p.parts:
                hashes[p.relative_to(ROOT).as_posix()]=hashlib.sha256(p.read_bytes()).hexdigest()
    result=dict(stage='Phase2 digital prototype',simulation='PASS',reference_export_fft='PASS',
                synthesis_out_of_context='PASS',synthetic_constraints_timing='PASS',
                board_cdc_timing='NOT_SIGNED_OFF',board_implementation='NOT_RUN',
                ps_dma='NOT_RUN',bench='NOT_RUN',simulation_marker=marker,
                tools=dict(vivado='2020.2',python=platform.python_version(),numpy=np.__version__),
                cdc_findings=cdc_summary,drc_warning_counts={k:sum(x[0]==k for x in drcs) for k in ['PLIO-6','ZPS7-1']},
                capture_sha256=hashlib.sha256((source/'raw_capture.csv').read_bytes()).hexdigest(),
                input_sha256=hashes,
                phase1_reference_sha256=hashlib.sha256((ROOT.parent/'Phase1/snapshot/Phase1/generated/waveform_report.json').read_bytes()).hexdigest(),
                unresolved=['non-clock-capable DCO pins','ADC clock electrical driver and U13 pulldown',
                            'RBIAS value and ADC B nets','calibrated per-channel epoch and DAC phase origin',
                            'board clock/reset timing, PS7 platform and actual raw transport'])
    (out/'digital_result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8',newline='\n')
    print('PHASE2_EVIDENCE_PASS: prototype only; board acceptance pending')

if __name__=='__main__': main()
