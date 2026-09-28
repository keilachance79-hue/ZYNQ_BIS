"""Generate the fixed Q1.15 reference ROM and an example multisine DAC table."""
from pathlib import Path
import math
import argparse

ROOT = Path(__file__).resolve().parents[1]

def generate(log2=14):
    out = ROOT / "mem"
    out.mkdir(exist_ok=True)
    sine = [round(32767 * math.sin(2 * math.pi * n / 1024)) for n in range(1024)]
    (out / "sin1024.mem").write_text("\n".join(f"{v & 0xffff:04x}" for v in sine)+"\n")
    npoints = 1 << log2
    # 5,10,20,50,100,200,300,500 kHz at 10.24 MSPS / 16384 points.
    bins = [8,16,32,80,160,320,480,800] if log2 == 14 else list(range(1,9))
    phases = [-math.pi*k*(k-1)/8 for k in range(8)]
    values = [sum(math.sin(2*math.pi*b*n/npoints+p) for b,p in zip(bins,phases)) for n in range(npoints)]
    scale = 0.65*32767/max(abs(v) for v in values)
    words = [32768+round(scale*v) for v in values]
    (out / "wave_example.mem").write_text("\n".join(f"{v:04x}" for v in words)+"\n")
    # This is a DAC digital-range example, not a prescribed human excitation level.
    (out / "wave_example.csv").write_text("index,dac_code\n"+"".join(f"{i},{v}\n" for i,v in enumerate(words)))
    print(f"Generated {len(sine)} reference entries and {npoints} DAC entries; bins={bins}")

if __name__ == "__main__":
    p=argparse.ArgumentParser()
    p.add_argument("--log2",type=int,default=14)
    generate(p.parse_args().log2)
