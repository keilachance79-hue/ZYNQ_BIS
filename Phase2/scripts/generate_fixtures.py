"""Generate ADC-only simulation fixtures from the archived Phase1 spectrum."""
from pathlib import Path
import json
import numpy as np

ROOT = Path(__file__).resolve().parents[1]

def main():
    r=json.loads((ROOT.parent/'Phase1/snapshot/Phase1/generated/waveform_report.json').read_text())
    n=2048; q=np.array(r['config']['bins']); p=np.array(r['phases_sine_rad'])
    angle=2*np.pi*q[:,None]*np.arange(n)/n+p[:,None]
    # Known per-tone V/I ratio: magnitude 2, phase +0.3 rad. ADC code units.
    v=np.rint(np.sum(1700*np.sin(angle+.3),axis=0)).astype(np.int64)
    i=np.rint(np.sum(850*np.sin(angle),axis=0)).astype(np.int64)
    out=ROOT/'generated'; out.mkdir(exist_ok=True)
    for name,x in [('input_a',v),('input_b',i)]:
        assert np.all((x>=-32768)&(x<=32767))
        (out/(name+'.hex')).write_text(''.join(f'{c+32768:04x}\n' for c in x),encoding='ascii',newline='\n')
    report=dict(n=n,fs_hz=10240000,bins=q.tolist(),voltage_peak_codes=1700,
                current_peak_codes=850,ratio_magnitude=2,ratio_phase_rad=.3,
                note='Synthetic ADC inputs, not ohms or measured hardware')
    (out/'fixture_config.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8',newline='\n')
    print('PHASE2_FIXTURES_PASS')

if __name__=='__main__': main()
