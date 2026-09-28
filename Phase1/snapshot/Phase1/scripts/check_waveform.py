"""Independent export/reference and optional captured-DAC checks (numpy)."""
from pathlib import Path
import argparse
import hashlib
import json
import tempfile
import numpy as np
from generate_multisine import generate, ROOT


def check(capture=None, reproduce=False):
    out=ROOT/'generated'
    report=json.loads((out/'waveform_report.json').read_text())
    c=json.loads((ROOT/'config.json').read_text())
    assert report['config']==c
    n=c['rom_length']; q=np.array(c['bins']); amp=np.array(c['amplitudes'])
    phases=np.array(report['phases_sine_rad']); scale=report['scale_codes_per_unit']
    codes=np.array([int(s,16) for s in (out/'waveform.hex').read_text().split()])
    assert len(codes)==n and np.all((codes>=0)&(codes<=65535))
    coe=(out/'waveform.coe').read_text().split('memory_initialization_vector=')[1].strip().rstrip(';')
    assert np.array_equal(codes,[int(s.strip(),16) for s in coe.split(',')])
    # Direct sine summation, independent of generator's spectral construction.
    wave=np.sum(amp[:,None]*np.sin(2*np.pi*q[:,None]*np.arange(n)/n+phases[:,None]),axis=0)
    assert np.array_equal(np.rint(wave*scale).astype(int)+32768,codes)
    raw=codes-32768
    coeff=np.fft.rfft(raw); measured_amp=2*np.abs(coeff[q])/n
    amp_error=np.max(np.abs(measured_amp-amp*scale))
    phase_error=np.max(np.abs(np.angle(np.exp(1j*(np.angle(coeff[q])-(phases-np.pi/2))))))
    assert amp_error<=1.0 and phase_error<2e-4
    mask=np.ones(len(coeff),dtype=bool); mask[q]=False
    spur_peak=2*np.max(np.abs(coeff[mask]))/n
    assert spur_peak<=1.0
    assert report['cf_optimized_dense']<report['cf_zero_phase_oversampled']*.95
    assert not np.allclose(phases,0)
    assert hashlib.sha256((out/'waveform.hex').read_bytes()).hexdigest()==report['waveform_sha256']
    if reproduce:
        with tempfile.TemporaryDirectory() as t:
            generate(ROOT/'config.json',Path(t))
            for f in out.iterdir():
                if f.is_file(): assert f.read_bytes()==(Path(t)/f.name).read_bytes(),f.name
    result=dict(status='PASS',samples=n,frequencies_hz=report['frequencies_hz'],
                amplitude_max_error_codes=float(amp_error),phase_max_error_rad=float(phase_error),
                max_non_target_bin_peak_codes=float(spur_peak),
                cf_zero=report['cf_zero_phase_oversampled'],cf_optimized=report['cf_optimized_dense'],
                reproducible_exports=bool(reproduce))
    if capture:
        rows=np.genfromtxt(capture,delimiter=',',names=True)
        total=0; mean_periods=[]
        for epoch in np.unique(rows['epoch']):
            part=rows[rows['epoch']==epoch]
            count=len(part); idx=np.arange(count)%n
            assert count>=2*n
            assert np.array_equal(part['ordinal'],np.arange(count))
            assert np.array_equal(part['index'],idx)
            assert np.array_equal(part['dac_code'],codes[idx])
            period=(part['time_ns'][-1]-part['time_ns'][0])/(count-1)
            assert abs(period-1e9/c['fs_hz'])/(1e9/c['fs_hz'])<1e-4
            mean_periods.append(float(period)); total+=count
        assert len(np.unique(rows['epoch']))==2
        result.update(captured_samples=total,capture_epochs=2,mean_periods_ns=mean_periods)
    return result


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--capture',type=Path)
    p.add_argument('--reproduce',action='store_true')
    p.add_argument('--report',type=Path)
    a=p.parse_args();result=check(a.capture,a.reproduce)
    text=json.dumps(result,indent=2)+'\n'
    print(text,end='')
    if a.report:
        a.report.parent.mkdir(parents=True,exist_ok=True)
        a.report.write_text(text,encoding='utf-8')
