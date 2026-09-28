"""Deterministic phase-only crest reduction and 16-bit LTC1668 ROM export.

Alternating time-domain clipping / fixed-magnitude spectral projection.
This implements the paper's crest-reduction idea, not its unpublished exact LUT.
Requires numpy. No waveform clipping is applied to the final exported samples.
"""
from pathlib import Path
import argparse
import hashlib
import json
import numpy as np

ROOT = Path(__file__).resolve().parents[1]


def validate(c):
    n, fs = c['rom_length'], c['fs_hz']
    bins = c['bins']
    if n < 4 or n & (n-1) or fs <= 0:
        raise ValueError('N must be a power of two >= 4 and Fs must be positive')
    if len(bins) != len(c['amplitudes']) or not bins:
        raise ValueError('Each bin needs an amplitude')
    if len(set(bins)) != len(bins) or any(type(q) is not int or not 0 < q < n//2 for q in bins):
        raise ValueError('Bins must be unique positive integers below Nyquist')
    if any(a <= 0 for a in c['amplitudes']):
        raise ValueError('Amplitudes must be positive')
    if not 0 < c['headroom'] < 1 or c['oversample'] < 2 or c['restarts'] < 2 or c['iterations'] < 1:
        raise ValueError('Invalid optimization or headroom settings')
    actual = c['reference_clock_hz']*c['mmcm_mult']/c['mmcm_divclk']/c['mmcm_out_div']
    if abs(actual-fs) > 1e-6:
        raise ValueError('MMCM settings and Fs disagree')


def synth(phases, amplitudes, bins, length):
    spectrum = np.zeros(length//2+1, dtype=complex)
    spectrum[bins] = .5*length*amplitudes*np.exp(1j*(phases-np.pi/2))
    return np.fft.irfft(spectrum, n=length)


def crest(x):
    return float(np.max(np.abs(x))/np.sqrt(np.mean(x*x)))


def generate(config=ROOT/'config.json', output=ROOT/'generated'):
    c = json.loads(Path(config).read_text(encoding='utf-8'))
    validate(c)
    n = c['rom_length']; nos = n*c['oversample']
    bins = np.array(c['bins']); amps = np.array(c['amplitudes'], dtype=float)
    rng = np.random.default_rng(c['seed'])
    rms = float(np.sqrt(np.sum(amps**2)/2))
    best_phases = np.zeros(len(bins))
    baseline = synth(best_phases, amps, bins, nos)
    best_cf = crest(baseline)
    for restart in range(c['restarts']):
        phases = (-np.pi*np.arange(len(bins))*(np.arange(len(bins))-1)/len(bins)
                  if restart == 0 else rng.uniform(-np.pi, np.pi, len(bins)))
        for iteration in range(c['iterations']):
            wave = synth(phases, amps, bins, nos)
            cf = crest(wave)
            if cf < best_cf:
                best_cf, best_phases = cf, phases.copy()
            # Projection is an optimization step only, not final DAC clipping.
            threshold = rms*(2.1-.65*iteration/max(1, c['iterations']-1))
            projected = np.fft.rfft(np.clip(wave, -threshold, threshold))
            phases = np.angle(projected[bins])+np.pi/2
    # Independent, denser grid checks peaks between optimization-grid points.
    check_wave = synth(best_phases, amps, bins, 4*nos)
    scale = c['headroom']*32767/np.max(np.abs(check_wave))
    unit = synth(best_phases, amps, bins, n)
    ideal = unit*scale
    codes = np.rint(ideal).astype(np.int64)+32768
    if np.any(codes < 0) or np.any(codes > 65535):
        raise RuntimeError('Final waveform would clip')
    output = Path(output); output.mkdir(parents=True, exist_ok=True)
    hex_text = ''.join(f'{v:04x}\n' for v in codes)
    coe_text = ('memory_initialization_radix=16;\nmemory_initialization_vector=\n'
                + ',\n'.join(f'{v:04x}' for v in codes)+';\n')
    (output/'waveform.hex').write_text(hex_text, encoding='ascii', newline='\n')
    (output/'waveform.coe').write_text(coe_text, encoding='ascii', newline='\n')
    csv = 'index,time_s,ideal_signed_code,dac_code,signed_code\n'
    csv += ''.join(f'{i},{i/c["fs_hz"]:.15g},{x:.15g},{v},{v-32768}\n'
                   for i,(x,v) in enumerate(zip(ideal,codes)))
    (output/'reference.csv').write_text(csv, encoding='ascii', newline='\n')
    quantized = codes-32768
    coeff = np.fft.rfft(quantized)[bins]
    report = dict(config=c, phases_sine_rad=best_phases.tolist(),
                  frequencies_hz=(bins*c['fs_hz']/n).tolist(),
                  cf_zero_phase_oversampled=crest(baseline),
                  cf_optimized_grid=best_cf,
                  cf_optimized_dense=crest(check_wave),
                  cf_quantized_samples=crest(quantized),
                  scale_codes_per_unit=float(scale),
                  ideal_tone_peak_codes=(amps*scale).tolist(),
                  measured_tone_peak_codes=(2*np.abs(coeff)/n).tolist(),
                  measured_phase_fft_rad=np.angle(coeff).tolist(),
                  code_min=int(codes.min()), code_max=int(codes.max()),
                  max_quantization_error_codes=float(np.max(np.abs(quantized-ideal))),
                  waveform_sha256=hashlib.sha256(hex_text.encode()).hexdigest(),
                  amplitude_unit='DAC code; NOT amperes',
                  optimization='phase-only clipping/projection; no global optimum claim')
    (output/'waveform_report.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8', newline='\n')
    header = ('// Generated from config.json. Do not edit manually.\n'
              f'`define PH1_FS_HZ {c["fs_hz"]}\n'
              f'`define PH1_ROM_LENGTH {n}\n'
              f'`define PH1_REF_CLK_HZ {c["reference_clock_hz"]}\n'
              f'`define PH1_MMCM_DIVCLK {c["mmcm_divclk"]}\n'
              f'`define PH1_MMCM_MULT {c["mmcm_mult"]}\n'
              f'`define PH1_MMCM_OUT_DIV {c["mmcm_out_div"]}\n')
    (output/'phase1_config.svh').write_text(header, encoding='ascii', newline='\n')
    xdc = ('# Generated from config.json; reference frequency confirmed by user.\n'
           f'create_clock -period {1e9/c["reference_clock_hz"]:.9f} -name ref_clk [get_ports ref_clk]\n')
    (output/'phase1_clock.xdc').write_text(xdc, encoding='ascii', newline='\n')
    return report


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--config', type=Path, default=ROOT/'config.json')
    p.add_argument('--output', type=Path, default=ROOT/'generated')
    a = p.parse_args(); r = generate(a.config, a.output)
    print(f'CF {r["cf_zero_phase_oversampled"]:.6f} -> {r["cf_optimized_dense"]:.6f}; '
          f'code range {r["code_min"]}..{r["code_max"]}; SHA256 {r["waveform_sha256"]}')
