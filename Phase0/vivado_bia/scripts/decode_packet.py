"""Decode one BIA1 DMA packet; optionally perform raw-data DFT and calibration."""
from pathlib import Path
import argparse
import cmath
import json
import math
import struct

def decode(data, freq_bins=None, factor=None):
    if len(data)<80 or len(data)%4:
        raise ValueError("Truncated or unaligned packet")
    h=struct.unpack_from("<16I",data)
    magic,version=h[:2]
    if magic!=0x31414942 or version>>16!=1:
        raise ValueError("Unsupported magic/protocol")
    raw=bool(version&1)
    n,fs,tones,payload_bytes=h[10:14]
    if not n or not fs or tones!=8 or h[14]!=15:
        raise ValueError("Invalid frame configuration")
    if payload_bytes != (4*n if raw else 32*tones) or len(data)!=64+payload_bytes+16:
        raise ValueError("Packet size does not match header")
    status,accepted,end_lo,end_hi=struct.unpack_from("<4I",data,64+payload_bytes)
    start=h[6]|(h[7]<<32)
    end=end_lo|(end_hi<<32)
    if end!=start+n-1 or accepted>n:
        raise ValueError("Invalid timestamp span/sample count")
    result={"session_id":h[2],"frame_id":h[3],"config_id":h[4],
            "electrodes":[(h[5]>>(5*k))&31 for k in range(4)],
            "mode":"raw" if raw else "demod", "fs_hz":fs,"sample_count":n,
            "t_start_tick":start,"t_end_tick":end,"t_center_s":(start+(n-1)/2)/fs,
            "status":status,"accepted_samples":accepted,
            "timestamp_calibrated":not bool(status&16)}
    if status&0x4f or accepted!=n:
        result["valid"]=False
        result["reason"]="Frame is invalid; padded/lost/overrange/fault samples must not be used for impedance"
        return result
    result["valid"]=True
    if freq_bins is not None and len(freq_bins)!=tones:
        raise ValueError("Supply exactly eight bins matching config_id")
    if raw:
        if freq_bins is None:
            result["note"]="Raw samples decoded; supply --bins for DFT"
            return result
        samples=list(struct.iter_unpack("<hh",data[64:64+payload_bytes]))
        pairs=[]
        for b in freq_bins:
            v=i=0j
            for j,(sv,si) in enumerate(samples):
                ref=cmath.exp(-2j*math.pi*b*j/n)
                v+=sv*ref; i+=si*ref
            pairs.append((v,i))
    else:
        pairs=[(complex(vr,vi),complex(ir,ii)) for vr,vi,ir,ii in
               struct.iter_unpack("<qqqq",data[64:64+payload_bytes])]
    result["tones"]=[]
    for k,(v,i) in enumerate(pairs):
        item={"index":k,"V":[v.real,v.imag],"I":[i.real,i.imag]}
        if freq_bins is not None: item["frequency_hz"]=freq_bins[k]*fs/n
        if abs(i)>0:
            ratio=v/i
            item["channel_ratio"]=[ratio.real,ratio.imag]
            if factor is not None:
                z=ratio*factor
                item.update(Z_ohm=[z.real,z.imag],magnitude_ohm=abs(z),phase_deg=math.degrees(cmath.phase(z)))
        else: item["error"]="Zero measured current coefficient"
        result["tones"].append(item)
    return result

if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("packet",type=Path)
    p.add_argument("--bins",type=int,nargs=8)
    p.add_argument("--factor-real",type=float,help="Real part of Rsense*HI/HV, ohms")
    p.add_argument("--factor-imag",type=float,default=0)
    a=p.parse_args()
    factor=None if a.factor_real is None else complex(a.factor_real,a.factor_imag)
    print(json.dumps(decode(a.packet.read_bytes(),a.bins,factor),ensure_ascii=False,indent=2))
