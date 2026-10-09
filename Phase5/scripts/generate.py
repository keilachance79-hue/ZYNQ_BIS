"""One reviewed map generates C/SV/docs; independent scan enumeration is the oracle."""
import csv
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]


def main():
    cfg=json.loads((ROOT/'config/electrode_map.json').read_text(encoding='utf-8'))
    e=cfg['electrode_to_db'];assert len(e)==32 and sorted(e)==list(range(1,33))
    roles=['I+','I-','V+','V-']
    table=[[cfg['roles'][r]['db'][str(db)]['address'] for db in e] for r in roles]
    # Independent PDF-derived DB->S piecewise rule cross-checks the PCB audit.
    for r in range(4):
        for d in range(1,33):
            s=(29-d if 13<=d<=16 else d) if r==0 else (13-d if d<=12 else 45-d if r in (1,2) and 17<=d<=28 else d)
            assert cfg['roles'][roles[r]]['db'][str(d)]['address']==s-1
    for folder in ('generated','docs','build/fixtures'): (ROOT/folder).mkdir(parents=True,exist_ok=True)
    lines=['`timescale 1ns/1ps','// Generated from config/electrode_map.json. role: IP,IN,VP,VN; electrode: 1..32.',
           'package electrode_map_pkg;','function automatic [4:0] electrode_address(input [1:0] role,input [5:0] electrode);',
           'case ({role,electrode})']
    for r in range(4):
        lines += [f"8'd{(r<<6)|n}: electrode_address=5'd{a};" for n,a in enumerate(table[r],1)]
    lines+=['default: electrode_address=0;','endcase','endfunction','endpackage']
    (ROOT/'generated/electrode_map.sv').write_text('\n'.join(lines)+'\n')
    header=['/* Generated; electrode indices in arrays are E-1. */','#ifndef ELECTRODE_MAP_H','#define ELECTRODE_MAP_H','#include <stdint.h>',
            'static const uint8_t electrode_to_db[32] = {'+','.join(map(str,e))+'};',
            'static const uint8_t electrode_map[4][32] = {']
    header += ['{'+','.join(map(str,row))+'},' for row in table]
    header+=['};','#endif']
    (ROOT/'generated/electrode_map.h').write_text('\n'.join(header)+'\n')
    md=['# 电极映射','', '2026-10-09：用户确认 E1→DB1，依次至 E32→DB32；不是导通实测结论。',
        'DB→S/address 来自当前 EDA PCB PAD_NET，已与历史 PDF 规律交叉核对。角色次序 I+、I−、V+、V−。',
        '', '| E | DB | I+ S/address | I− S/address | V+ S/address | V− S/address |','|---|---|---|---|---|---|']
    for n,db in enumerate(e):md.append(f'| {n+1} | {db} | '+' | '.join(f'S{table[r][n]+1}/{table[r][n]:05b}' for r in range(4))+' |')
    md+=['','## 地址线','', '| 角色 | A0 | A1 | A2 | A3 | A4 |','|---|---|---|---|---|---|']
    for role in roles:md.append('| '+role+' | '+' | '.join(cfg['roles'][role]['address_pins'][f'A{i}']['net'] for i in range(5))+' |')
    md+=['','**I− 的 A0=B35_L23P，A1=B35_L23N，与旧 PDF 整理表相反，按当前 EDA 记录执行。**',
         '四片 CS/WR/EN 均为 GND。没有 FPGA 全局断开功能；20 位地址寄存器同一时钟更新也不保证模拟同时切换。',
         '电极到 DB 可修改 config 中的 permutation 后重新生成；不得单独修改 SV 或 C 表。',
         '原始网络行号和源文件指纹见 [映射证据](../config/electrode_map.json)。']
    (ROOT/'docs/electrode_map.md').write_text('\n'.join(md)+'\n',encoding='utf-8')
    for count in (4,16,32):
        rows=[];words=[]
        for ip in range(1,count+1):
            im=ip%count+1
            for vp in range(1,count+1):
                vm=vp%count+1
                if {ip,im}.isdisjoint({vp,vm}):
                    els=[ip,im,vp,vm];addresses=[table[r][v-1] for r,v in enumerate(els)]
                    rows.append([len(rows),*els,*addresses])
                    word=sum(v<<(6*r) for r,v in enumerate(els))+sum(v<<(24+5*r) for r,v in enumerate(addresses))
                    words.append(f'{word:011x}')
        assert len(rows)==count*(count-3) and len({tuple(r[1:5]) for r in rows})==len(rows)
        (ROOT/f'build/fixtures/scan_{count}.hex').write_text('\n'.join(words)+'\n')
        with (ROOT/f'generated/scan_{count}.csv').open('w',newline='') as f:
            w=csv.writer(f);w.writerow(['index','i_plus','i_minus','v_plus','v_minus','ip_addr','in_addr','vp_addr','vn_addr']);w.writerows(rows)
    print('MAP_SCAN_PASS: 4=4, 16=208, 32=928; 128 mapped addresses')


if __name__=='__main__':main()
