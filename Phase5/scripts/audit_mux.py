"""Read-only MUX pad/net audit of the supplied EasyEDA project."""
import argparse
import hashlib
import json
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT.parent/'Phase2/scripts'))
from audit_epro2 import read_documents, records, attributes


def main():
    ap=argparse.ArgumentParser();ap.add_argument('project',type=Path);args=ap.parse_args()
    docs=read_documents(args.project)
    pcb=docs['585f0d4e5ddb4537b2b87cf8e89f1097'];attrs=attributes(pcb)
    # ADG732 TQFP Figure 5: pin1=S12, pin12=S1, pin45=S16, pin48=S13.
    pin_to_s={**{p:13-p for p in range(1,13)},**{p:61-p for p in range(45,49)},**{p:p-8 for p in range(25,41)}}
    roles=['I+','I-','V+','V-'];result={}
    for role in roles:
        component,= [k for k,v in attrs.items() if v.get('Designator',{}).get('value')==role]
        pads={int(json.loads(r['id'])[2]):{'net':r['data']['padNet'],'line':r['line']}
              for r in records(pcb,'PAD_NET') if json.loads(r['id'])[1]==component}
        mapping={}
        for pin,s in pin_to_s.items():
            net=pads[pin]['net'];assert net.startswith('DB')
            db=int(net[2:]);assert db not in mapping
            mapping[db]={'pin':pin,'source':s,'address':s-1,**pads[pin]}
        assert sorted(mapping)==list(range(1,33))
        assert sorted(v['address'] for v in mapping.values())==list(range(32))
        assert all(pads[p]['net']=='GND' for p in (20,21,22,23,24))
        assert all(pads[p]['net']=='A+5V' for p in (13,14)) and pads[43]['net']==role
        result[role]={'db':mapping,'address_pins':{f'A{p-15}':pads[p] for p in range(15,20)},
                      'controls':{k:pads[p] for k,p in [('CS',20),('WR',21),('EN',22)]}}
    target=ROOT/'config';target.mkdir(exist_ok=True)
    output={'source_name':args.project.name,'source_sha256':hashlib.sha256(args.project.read_bytes()).hexdigest(),
            'pcb_uuid':'585f0d4e5ddb4537b2b87cf8e89f1097',
            'method':'Final PCB PAD_NET records, not copper/assembly connectivity or vendor ERC.',
            'electrode_to_db':list(range(1,33)),
            'electrode_order_evidence':'User confirmed E1->DB1 sequentially through E32->DB32 on 2026-10-09; continuity not measured.',
            'roles':result}
    (target/'electrode_map.json').write_text(json.dumps(output,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('MUX_AUDIT_PASS: 128 source routes, 20 address pins, 12 grounded controls')


if __name__=='__main__':main()
