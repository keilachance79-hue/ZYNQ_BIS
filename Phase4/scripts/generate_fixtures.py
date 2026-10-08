"""CORDIC bit-accurate vectors plus independent float amplitude/phase checks."""
import ctypes as c
import hashlib
import json
import math
import os
from pathlib import Path
import argparse
import zipfile
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
BINS=[2,3,7,11,19,37,61,113,199]
PI=round(math.pi*(1<<29)); HALF_PI=round(math.pi/2*(1<<29))


class Config(c.Structure):
    _fields_=[('name',c.c_char_p)]+[(n,c.c_uint) for n in
        ['function','coarse','data','phase','input','output','iterations','precision','round','scale']]+[('debug',c.c_int)]


class Complex(c.Structure):
    _fields_=[('re',c.c_double),('im',c.c_double)]


def array_type(scalar):
    class Array(c.Structure):
        _fields_=[('data',c.POINTER(scalar)),('size',c.c_size_t),('capacity',c.c_size_t),
                  ('dim',c.POINTER(c.c_size_t)),('dim_size',c.c_size_t),('dim_capacity',c.c_size_t),
                  ('owner',c.c_uint),('ops',c.c_void_p)]
    return Array


RealArray=array_type(c.c_double)
ComplexArray=array_type(Complex)


class Model:
    def __init__(self,vivado):
        self.zip=vivado/'data/ip/xilinx/cordic_v6_0/cmodel/cordic_v6_0_bitacc_cmodel_nt64.zip'
        dest=ROOT/'build/cmodel'; dest.mkdir(parents=True,exist_ok=True)
        with zipfile.ZipFile(self.zip) as z:
            for name in ['libgmp.dll','libIp_cordic_v6_0_bitacc_cmodel.dll']:
                (dest/name).write_bytes(z.read(name))
        self.directory=os.add_dll_directory(str(dest))
        self.dll=c.CDLL(str(dest/'libIp_cordic_v6_0_bitacc_cmodel.dll'))
        self.config=Config(b'phase4',1,1,0,0,32,32,0,0,3,1,0)
        self.create=self.func('create',[c.POINTER(Config),c.c_void_p,c.c_void_p],c.c_void_p)
        self.state=self.create(c.byref(self.config),None,None)
        if not self.state: raise RuntimeError('CORDIC C model create failed')
        self.ci=self.array('complex',ComplexArray)
        self.mo=self.array('real',RealArray)
        self.po=self.array('real',RealArray)
        self.translate=self.func('translate',[c.c_void_p,c.POINTER(ComplexArray),c.POINTER(RealArray),c.POINTER(RealArray),c.c_size_t])
        self.set_complex=self.func('xip_array_complex_set_data',[c.POINTER(ComplexArray),Complex,c.c_size_t])
        self.get_real=self.func('xip_array_real_get_data',[c.POINTER(RealArray),c.POINTER(c.c_double),c.c_size_t])
    def func(self,name,args,ret=c.c_int):
        f=getattr(self.dll,'xip_cordic_v6_0_'+name);f.argtypes=args;f.restype=ret;return f
    def array(self,kind,typ):
        ptr=self.func(f'xip_array_{kind}_create',[],c.POINTER(typ))()
        for field in ['dim','data']:
            if self.func(f'xip_array_{kind}_reserve_{field}',[c.POINTER(typ),c.c_size_t])(ptr,1):
                raise RuntimeError('Array allocation failed')
        ptr.contents.dim_size=1;ptr.contents.dim[0]=1;ptr.contents.size=1
        return ptr
    def run(self,x,y):
        if self.set_complex(self.ci,Complex(x,y),0): raise RuntimeError('C model input failed')
        if self.translate(self.state,self.ci,self.mo,self.po,1): raise RuntimeError('C model translate failed')
        mag=c.c_double();phase=c.c_double()
        if self.get_real(self.mo,c.byref(mag),0) or self.get_real(self.po,c.byref(phase),0):
            raise RuntimeError('C model output failed')
        return round(mag.value),round(phase.value)
    def close(self):
        for kind,typ,p in [('complex',ComplexArray,self.ci),('real',RealArray,self.mo),('real',RealArray,self.po)]:
            self.func(f'xip_array_{kind}_destroy',[c.POINTER(typ)],c.c_void_p)(p)
        self.func('destroy',[c.c_void_p])(self.state);self.directory.close()


def normalize(x,y):
    return 28-(max(abs(x),abs(y)).bit_length()-1)


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--vivado-root',type=Path,default=Path('D:/Application/Xilinx/Vivado/2020.2'))
    args=ap.parse_args();model=Model(args.vivado_root)
    target=ROOT/'build/fixtures';target.mkdir(parents=True,exist_ok=True)
    source=ROOT.parent/'Phase3/verification/nine_bins.csv'
    data=np.genfromtxt(source,delimiter=',',names=True,dtype=np.int64)
    vectors=[tuple(int(row[n]) for n in ['v_real','v_imag','i_real','i_imag']) for row in data]
    cases=['phase3_result']*len(vectors)
    extra=[(0,0,0,0),(1,0,0,1),(-1,0,0,-1),(1,1,-1,-1),(1,-1,-1,1),
           (-(1<<27),0,(1<<27)-1,0), (-(1<<27),-(1<<27),(1<<27)-1,(1<<27)-1),
           (-100000000,1,-100000000,-1), (1,1,1,1),
           (1<<27,0,0,0), (-(1<<27)-1,0,100,0), (0,0,0x7fffffff,-0x80000000)]
    for p in range(28):
        extra.extend([(1<<p,1,-(1<<p),-1),((1<<p)-1,1,1,(1<<p)-1)])
    rng=np.random.default_rng(20261008)
    extra.extend(tuple(map(int,row)) for row in rng.integers(-(1<<27),1<<27,(128,4)))
    vectors+=extra;cases+=['boundary_or_random']*len(extra)
    while len(vectors)%9: vectors.append((0,0,1,0));cases.append('padding')
    inputs=[];expected=[];cores=[];errors=[];calls=0
    try:
        for vi,vec in enumerate(vectors):
            packed=sum((x&0xffffffff)<<(32*j) for j,x in enumerate(vec))
            outputs=[];flags=[]
            for ch in range(2):
                x,y=vec[2*ch:2*ch+2]
                if not (-(1<<27)<=x<(1<<27) and -(1<<27)<=y<(1<<27)):
                    outputs.extend([0,0]);flags.append(2);cores.append('00000000000000000');continue
                if x==0 and y==0:
                    outputs.extend([0,0]);flags.append(8);cores.append('00000000000000000');continue
                shift=normalize(x,y)
                mag,phase=model.run(x<<shift,y<<shift)
                if not 0<=mag<(1<<31): raise ValueError(f'Unexpected model magnitude {mag}')
                cores.append(f'{(1<<64)|((phase&0xffffffff)<<32)|mag:017x}');calls+=1
                amp=((mag+(1<<(shift-5)))>>(shift-4)) if shift>4 else (mag<<(4-shift))
                if y==0: phase=-PI if x<0 else 0
                elif x==0: phase=HALF_PI if y>0 else -HALF_PI
                elif phase>=PI: phase-=2*PI
                elif phase< -PI: phase+=2*PI
                flag=1
                if amp>0xffffffff: amp=0xffffffff;flag|=4
                outputs.extend([amp,phase]);flags.append(flag)
                amp_error=abs(amp/(1<<14)-math.hypot(x,y)/1024)
                phase_error=abs(math.remainder(phase/(1<<29)-math.atan2(y,x),2*math.pi))
                if amp_error>.005 or phase_error>1e-7:
                    raise AssertionError((vi,ch,x,y,amp_error,phase_error))
                errors.append((amp_error,phase_error))
            record=packed+sum((x&0xffffffff)<<(128+32*j) for j,x in enumerate(outputs))
            flagbyte=flags[0]|flags[1]<<4
            inputs.append(f'{packed:032x}');expected.append(f'{flagbyte:02x}{record:064x}')
        for name,lines in [('input.hex',inputs),('expected.hex',expected),('core.hex',cores)]:
            (target/name).write_text('\n'.join(lines)+'\n',encoding='ascii')
        (target/'fixture_config.vh').write_text(f'localparam integer RECORDS={len(vectors)}, FRAMES={len(vectors)//9};\n',encoding='ascii')
        result={'records':len(vectors),'frames':len(vectors)//9,'phase3_records':len(data),'cordic_calls':calls,
                'max_amplitude_error_adc_codes':max(e[0] for e in errors),
                'max_phase_error_rad':max(e[1] for e in errors),
                'amplitude_budget_adc_codes':.005,'phase_budget_rad':1e-7,
                'phase3_csv_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
                'phase3_csv_lf_sha256':hashlib.sha256(source.read_bytes().replace(b'\r\n',b'\n')).hexdigest(),
                'cmodel_zip_sha256':hashlib.sha256(model.zip.read_bytes()).hexdigest(),
                'input_sha256':hashlib.sha256((target/'input.hex').read_bytes()).hexdigest(),
                'expected_sha256':hashlib.sha256((target/'expected.hex').read_bytes()).hexdigest(),
                'core_sha256':hashlib.sha256((target/'core.hex').read_bytes()).hexdigest(),
                'model_config':{name:getattr(model.config,name) for name,_ in Config._fields_ if name!='name'}}
        (target/'reference.json').write_text(json.dumps(result,indent=2)+'\n')
        print(json.dumps(result))
    finally: model.close()


if __name__=='__main__': main()
