"""Decode one 8192-byte V/I debug payload and report nine-bin reference FFT."""
from pathlib import Path
import argparse
import json
import numpy as np

def analyze(path):
    payload=Path(path).read_bytes()
    if len(payload)!=8192: raise ValueError('Expected exactly 2048 little-endian int16 V/I pairs (8192 bytes)')
    samples=np.frombuffer(payload,dtype='<i2').reshape(2048,2)
    bins=np.array([2,3,7,11,19,37,61,113,199])
    coeff=np.fft.rfft(samples,axis=0)[bins]
    result=[]
    for q,(v,i) in zip(bins,coeff):
        # A digital validity threshold only, not a calibrated current noise floor.
        ratio=None if abs(i)<1e-12 else v/i
        result.append(dict(bin=int(q),frequency_hz=int(q*5000),
            v_re=float(v.real),v_im=float(v.imag),i_re=float(i.real),i_im=float(i.imag),
            v_peak_codes=float(2*abs(v)/2048),i_peak_codes=float(2*abs(i)/2048),
            v_fft_phase_rad=float(np.angle(v)),i_fft_phase_rad=float(np.angle(i)),
            ratio_valid=ratio is not None,
            ratio_magnitude=None if ratio is None else float(abs(ratio)),
            ratio_phase_rad=None if ratio is None else float(np.angle(ratio))))
    return dict(samples=2048,fs_hz=10240000,units='ADC codes; uncalibrated V/I code ratio, not ohms',tones=result)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('payload',type=Path); p.add_argument('--output',type=Path)
    a=p.parse_args(); text=json.dumps(analyze(a.payload),indent=2)+'\n'
    if a.output: a.output.write_text(text,encoding='utf-8',newline='\n')
    else: print(text,end='')
