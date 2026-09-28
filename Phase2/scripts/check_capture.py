"""Validate raw debug transport and reference FFT, with explicit ADC code units."""
from pathlib import Path
import argparse
import hashlib
import json
import numpy as np
from analyze_raw import analyze

ROOT=Path(__file__).resolve().parents[1]

def signed_ramp(t,channel):
    code=(t*(17 if channel==0 else 29)+(123 if channel==0 else 4567))%65536
    for k,v in enumerate(([0,32768,65535] if channel==0 else [65535,0,32768])):
        code[t%2048==k]=v
    return code-32768

def main(capture,output):
    rows=np.genfromtxt(capture,delimiter=',',names=True,dtype=np.int64)
    output.mkdir(parents=True,exist_ok=True)
    cfg=json.loads((ROOT/'generated/fixture_config.json').read_text())
    golden=[np.array([int(x,16)-32768 for x in (ROOT/'generated'/f'input_{ch}.hex').read_text().split()]) for ch in ['a','b']]
    results=[]; fft_results=[]
    keys=np.unique(np.column_stack([rows['session'],rows['frame_id']]),axis=0)
    for session,frame_id in keys:
        f=rows[(rows['session']==session)&(rows['frame_id']==frame_id)]
        assert len(f)==cfg['n'] and np.array_equal(f['index'],np.arange(cfg['n']))
        assert np.all(f['start_tick']==f['start_tick'][0]) and f['start_tick'][0]%2048==0
        assert len(np.unique(f['mode']))==1
        samples=np.column_stack([f['v_signed'],f['i_signed']])
        if f['mode'][0]==0:
            tick=f['start_tick']+f['index']
            expected=np.column_stack([signed_ramp(tick,0),signed_ramp(tick,1)])
        else:
            expected=np.column_stack(golden)
        assert np.array_equal(samples,expected)
        # Exact raw S2MM payload contract: little-endian int16 V then int16 I.
        # This is a debug file export, not a claim of a running PS/DMA stack.
        payload=samples.astype('<i2').tobytes()
        assert len(payload)==8192
        filename=f'raw_s{session}_f{frame_id}.bin'
        (output/filename).write_bytes(payload)
        decoded=np.frombuffer(payload,dtype='<i2').reshape(-1,2)
        assert np.array_equal(samples,decoded)
        results.append(dict(session=int(session),frame_id=int(frame_id),start_tick=int(f['start_tick'][0]),
                            samples=len(f),bytes=len(payload),file=filename,sha256=hashlib.sha256(payload).hexdigest()))
        if f['mode'][0]==1:
            public_result=analyze(output/filename)
            assert [t['bin'] for t in public_result['tones']]==cfg['bins']
            assert all(t['ratio_valid'] and abs(t['ratio_magnitude']-2)<.001 and
                       abs(t['ratio_phase_rad']-.3)<.001 for t in public_result['tones'])
            q=np.array(cfg['bins']); x=np.fft.rfft(decoded,axis=0)[q]; ratio=x[:,0]/x[:,1]
            amplitude_error=np.max(np.abs(np.abs(ratio)-2))
            phase_error=np.max(np.abs(np.angle(np.exp(1j*(np.angle(ratio)-.3)))))
            assert amplitude_error<.001 and phase_error<.001
            fft_results.append(dict(frame_id=int(frame_id),frequencies_hz=(q*cfg['fs_hz']/cfg['n']).tolist(),
                                    ratio_magnitude=np.abs(ratio).tolist(),ratio_phase_rad=np.angle(ratio).tolist(),
                                    max_magnitude_error=float(amplitude_error),max_phase_error_rad=float(phase_error)))
    assert len(keys)==4 and len(fft_results)==1
    assert set(int(k[1]) for k in keys)=={10,11,20,81}
    result=dict(status='PASS',paired_samples=len(rows),frames=results,fft=fft_results,
                hardware_ps_dma='NOT_RUN',units='signed ADC codes; ratio is not calibrated ohms')
    (ROOT/'verification').mkdir(exist_ok=True)
    (ROOT/'verification/capture_check.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8',newline='\n')
    print(f'PHASE2_REFERENCE_PASS: frames={len(keys)} pairs={len(rows)}; max ratio error={amplitude_error:.8g}; max phase error={phase_error:.8g} rad')

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--capture',type=Path,default=ROOT/'build/reports/raw_capture.csv')
    p.add_argument('--output',type=Path,default=ROOT/'build/raw')
    a=p.parse_args();main(a.capture,a.output)
