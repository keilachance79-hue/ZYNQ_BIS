"""Cross-check scan traces and preserve compact simulation/synthesis evidence."""
import csv
import hashlib
import json
import re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]


def digest(path):return hashlib.sha256(path.read_bytes().replace(b'\r\n',b'\n')).hexdigest()


def main():
    reports=ROOT/'build/reports';target=ROOT/'verification';target.mkdir(exist_ok=True)
    log=(reports/'scan_sim.log').read_text()
    assert 'PHASE5_SCAN_PASS' in log and 'FAULT_PASS cases=12' in log and not re.search(r'Fatal:|Error:',log)
    cases=[]
    for n,samples in [(4,16),(16,16),(32,16),(4,2048)]:
        match=re.search(fr'SCAN_PASS N={n} frame_samples={samples} requests=(\d+) samples=(\d+) overlaps=(\d+) stalls=(\d+)',log)
        assert match
        requests,pairs,overlaps,stalls=map(int,match.groups())
        assert requests==n*(n-3) and pairs==requests*samples and overlaps>0
        if samples==16:assert stalls>0
        filename=f'scan_{n}_{samples}_trace.csv'
        rows=list(csv.DictReader((reports/filename).open()))
        golden=list(csv.DictReader((ROOT/f'generated/scan_{n}.csv').open()))
        assert len(rows)==len(golden)==requests
        for j,(r,g) in enumerate(zip(rows,golden)):
            els=[int(g[k]) for k in ['i_plus','i_minus','v_plus','v_minus']]
            addr=[int(g[k]) for k in ['ip_addr','in_addr','vp_addr','vn_addr']]
            assert int(r['index'])==j and int(r['completed_at_request'])==j
            assert int(r['start_tag'])%samples==0
            assert int(r['electrodes_hex'],16)==sum(v<<(6*k) for k,v in enumerate(els))
            assert int(r['addresses_hex'],16)==sum(v<<(5*k) for k,v in enumerate(addr))
        (target/filename).write_bytes((reports/filename).read_bytes())
        cases.append(dict(electrodes=n,frame_samples=samples,requests=requests,sample_pairs=pairs,
                          overlapped_switches=overlaps,buffer_wait_cycles=stalls,trace_sha256_lf=digest(reports/filename)))
    synth=(ROOT/'synth.log').read_text(errors='replace')
    assert 'PHASE5_SYNTH_PASS' in synth and not re.search(r'^ERROR:',synth,re.M)
    timing=(reports/'timing_synth.rpt').read_text()
    match=re.search(r'WNS\(ns\).*?\n\s*-+.*?\n\s*([-\d.]+)\s+([-\d.]+)\s+\d+\s+\d+\s+([-\d.]+)',timing,re.S)
    assert match;wns,tns,whs=map(float,match.groups())
    util=(reports/'utilization_synth.rpt').read_text()
    resources={key:float(re.search(r'\| '+re.escape(label)+r'\s*\|\s*([\d.]+)',util).group(1))
               for key,label in [('lut','Slice LUTs*'),('ff','Slice Registers'),('dsp','DSPs'),('bram_tile','Block RAM Tile')]}
    source={p.relative_to(ROOT).as_posix():digest(p) for folder in ('rtl','sim','scripts','constraints','generated','config')
            for p in sorted((ROOT/folder).glob('*')) if p.is_file()}
    source['../Phase2/rtl/adc_frame_buffer.sv']=digest(ROOT.parent/'Phase2/rtl/adc_frame_buffer.sv')
    result={'date':'2026-10-09','stage':'Phase5 scan controller with real Phase2 frame buffer RTL',
            'simulation':'PASS','trace_check':'PASS','fault_scenarios':12,'cases':cases,
            'sample_pairs_compared':sum(c['sample_pairs'] for c in cases),
            'resources_controller_only':resources,'wns_ns':wns,'tns_ns':tns,'whs_ns':whs,
            'internal_timing':'PASS' if wns>=0 and whs>=0 else 'FAIL',
            'clock_hz':100000000,'board_implementation':'NOT_RUN','analog_settling':'NOT_MEASURED',
            'full_adc_fft_cordic_scan_rtl':'NOT_RUN','ps_dma':'NOT_RUN','source_sha256_lf':source}
    for name in ('timing_synth.rpt','utilization_synth.rpt','drc_synth.rpt'):(target/name).write_bytes((reports/name).read_bytes())
    markers=[line for line in log.splitlines() if re.search(r'SCAN_PASS|FAULT_PASS',line)]
    (target/'simulation_summary.txt').write_text('\n'.join(markers)+'\n')
    (target/'digital_result.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k!='source_sha256_lf'}))
    assert wns>=0 and whs>=0,'Internal timing failed'


if __name__=='__main__':main()
