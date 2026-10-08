"""Deterministic vectors and vendor bit-accurate FFT reference (Vivado 2020.2)."""
import argparse
import ctypes as c
import hashlib
import json
import os
from pathlib import Path
import zipfile
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
N = 2048
BINS = [2, 3, 7, 11, 19, 37, 61, 113, 199]


class Generics(c.Structure):
    _fields_ = [(n, c.c_int) for n in ('nfft', 'arch', 'has_nfft', 'float', 'input_width',
                                    'twiddle_width', 'scaling', 'bfp', 'rounding')]


class Inputs(c.Structure):
    _fields_ = [('nfft', c.c_int), ('re', c.POINTER(c.c_double)), ('re_size', c.c_int),
                ('im', c.POINTER(c.c_double)), ('im_size', c.c_int),
                ('scaling', c.POINTER(c.c_int)), ('scaling_size', c.c_int), ('direction', c.c_int)]


class Outputs(c.Structure):
    _fields_ = [('re', c.POINTER(c.c_double)), ('re_size', c.c_int),
                ('im', c.POINTER(c.c_double)), ('im_size', c.c_int),
                ('exponent', c.c_int), ('overflow', c.c_int)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--vivado-root', type=Path, default=Path('D:/Application/Xilinx/Vivado/2020.2'))
    args = parser.parse_args()
    gen = ROOT / 'build/fixtures'
    gen.mkdir(parents=True, exist_ok=True)
    modeldir = ROOT / 'build/cmodel'
    modeldir.mkdir(parents=True, exist_ok=True)
    archive = args.vivado_root / 'data/ip/xilinx/xfft_v9_1/cmodel/xfft_v9_1_bitacc_cmodel_nt64.zip'
    # Only named runtime DLLs are copied locally; no vendor code is redistributed.
    with zipfile.ZipFile(archive) as z:
        for name in ('libgmp.dll', 'libIp_xfft_v9_1_bitacc_cmodel.dll'):
            (modeldir / name).write_bytes(z.read(name))
    dll_directory = os.add_dll_directory(str(modeldir))
    dll = c.CDLL(str(modeldir / 'libIp_xfft_v9_1_bitacc_cmodel.dll'))
    create = dll.xilinx_ip_xfft_v9_1_create_state
    create.argtypes, create.restype = [Generics], c.c_void_p
    simulate = dll.xilinx_ip_xfft_v9_1_bitacc_simulate
    simulate.argtypes, simulate.restype = [c.c_void_p, Inputs, c.POINTER(Outputs)], c.c_int
    destroy = dll.xilinx_ip_xfft_v9_1_destroy_state
    destroy.argtypes = [c.c_void_p]
    state = create(Generics(11, 3, 0, 0, 16, 24, 0, 0, 1))
    if not state:
        raise RuntimeError('Vendor FFT model creation failed')

    n = np.arange(N)
    vectors = [('zero', np.zeros((N, 2), dtype=np.int64)),
               ('dc_extremes', np.tile([-32768, 32767], (N, 1)))]
    for j, q in enumerate(BINS):
        vectors.append((f'sine_bin_{q}', np.rint(np.column_stack([
            (12000+j*1500)*np.sin(2*np.pi*q*n/N + .37*j-.8),
            (24000-j*1700)*np.sin(2*np.pi*q*n/N - .21*j+.6)] )).astype(np.int64)))
    wave = np.loadtxt(ROOT.parent / 'Phase1/generated/waveform.hex', dtype=str)
    codes = np.array([int(x, 16) for x in wave], dtype=np.int64)
    # Phase1 DAC waveform is offset binary; rotate I to expose V/I mixing.
    wave = codes - 32768
    vectors.append(('phase1_multisine', np.column_stack([wave, np.roll(wave, 17)//2])))
    rng = np.random.default_rng(20261008)
    vectors.append(('random_full_range', rng.integers(-32768, 32768, (N, 2))))
    impulse = np.zeros((N, 2), dtype=np.int64)
    impulse[0, 0], impulse[123, 1] = 32767, -32768
    vectors.append(('impulses', impulse))
    vectors.append(('nyquist_extremes', np.column_stack([
        np.where(n%2, -32768, 32767), np.where(n%2, 32767, -32768)])))
    raw = ROOT.parent / 'Phase2/build/reports/raw_capture.csv'
    if not raw.exists():
        raise FileNotFoundError('Rebuild Phase2 first: its verified raw_capture.csv is required')
    # Read the real Phase2 simulation output, not a regenerated approximation.
    data = np.genfromtxt(raw, delimiter=',', names=True, dtype=np.int64)
    for fid in np.unique(data['frame_id']):
        frame = data[data['frame_id'] == fid]
        if len(frame) != N or not np.array_equal(frame['index'], n):
            raise ValueError('Incomplete Phase2 simulation frame')
        vectors.append((f'phase2_frame_{fid}', np.column_stack([frame['v_signed'], frame['i_signed']])))

    fixtures, golden, rows = [], [], []
    max_error = 0.0
    try:
        for fi, (name, samples) in enumerate(vectors):
            if samples.shape != (N, 2) or samples.min() < -32768 or samples.max() > 32767:
                raise ValueError(f'Invalid vector {name}')
            fixtures.extend(f'{((int(i)&65535)<<16)|(int(v)&65535):08x}' for v, i in samples)
            errors = []
            for channel in range(2):
                re = (c.c_double*N)(*(samples[:, channel]/32768.0))
                im = (c.c_double*N)()
                ore, oim = (c.c_double*N)(), (c.c_double*N)()
                schedule = (c.c_int*11)()
                inp = Inputs(11, re, N, im, N, schedule, 11, 1)
                out = Outputs(ore, N, oim, N, 0, 0)
                if simulate(state, inp, c.byref(out)) != 0 or out.re_size != N or out.im_size != N:
                    raise RuntimeError('FFT C model failed')
                integer = np.rint(np.column_stack([ore, oim])*32768).astype(np.int64)
                gold_float = np.fft.fft(samples[:, channel])
                error = float(np.max(np.abs(integer[:,0]+1j*integer[:,1]-gold_float)))
                # Conservative absolute budget in unscaled FFT integer codes.
                # Bit-exact agreement with the vendor model is the primary criterion.
                if error > 4096:
                    raise AssertionError(f'Float FFT error exceeds declared budget: {error}')
                max_error = max(max_error, error)
                errors.append(error)
                golden.extend(f'{((int(imag)&0xffffffff)<<32)|(int(real)&0xffffffff):016x}'
                              for real, imag in integer)
            rows.append({'frame': fi, 'id': 100+fi, 'name': name, 'max_complex_error_codes': errors})
    finally:
        destroy(state)
        dll_directory.close()
    for name, values in [('input.hex', fixtures), ('golden.hex', golden)]:
        (gen/name).write_text('\n'.join(values)+'\n', encoding='ascii')
    (gen/'fixture_config.vh').write_text(f'localparam integer FRAMES={len(vectors)};\n', encoding='ascii')
    result = {'n': N, 'bins': BINS, 'frames': rows, 'model_generics': [11,3,0,0,16,24,0,0,1],
              'float_complex_abs_budget_codes': 4096, 'max_complex_error_codes': max_error,
              'cmodel_zip_sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
              'phase2_raw_sha256': hashlib.sha256(raw.read_bytes()).hexdigest(),
              'input_sha256': hashlib.sha256((gen/'input.hex').read_bytes()).hexdigest(),
              'golden_sha256': hashlib.sha256((gen/'golden.hex').read_bytes()).hexdigest()}
    (gen/'reference.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print(f'Generated {len(vectors)} V/I frames; max float error {max_error:.6f} FFT codes')


if __name__ == '__main__':
    main()
