"""Read-only inspection of EasyEDA Pro epro2 document records.

Reads ZIP members in memory, never extracts or modifies the source project.
Empty payloads remove prior record IDs; this is not the vendor ERC engine.
"""
from pathlib import Path
import json
import zipfile
import hashlib


def read_documents(path):
    decoder = json.JSONDecoder()
    docs = {}
    current = None
    with zipfile.ZipFile(path) as archive:
        members = [n for n in archive.namelist() if n.endswith('.epru')]
        if len(members) != 1:
            raise ValueError('Expected one project .epru member')
        lines = archive.read(members[0]).decode('utf-8').splitlines()
    for line_number, line in enumerate(lines, 1):
        if not line.strip():
            continue
        header, payload = line.split('||', 1)
        header = json.loads(header)
        if payload == '|':
            current['records'].pop(header['id'], None)
            continue
        data, end = decoder.raw_decode(payload)
        if payload[end:] not in ('|', ''):
            raise ValueError(f'Unexpected record suffix at line {line_number}')
        if header['type'] == 'DOCHEAD':
            current = {'head': data, 'records': {}}
            if data['uuid'] in docs:
                raise ValueError('Repeated document; replay semantics need review')
            docs[data['uuid']] = current
        else:
            current['records'][header['id']] = {
                'type': header['type'], 'data': data, 'line': line_number,
                'ticket': header.get('ticket'), 'id': header['id']}
    return docs


def records(doc, kind):
    return [r for r in doc['records'].values() if r['type'] == kind]


def attributes(doc):
    result = {}
    for record in records(doc, 'ATTR'):
        data = record['data']
        result.setdefault(data['parentId'], {})[data['key']] = {
            'value': data['value'], 'line': record['line']}
    return result


def audit(path, docs):
    # Explicit target: the archive also contains unrelated reference boards.
    board = 'ab157d633e1e4969'
    schematic = '86cefc97253543df82bc371d1071ae42'
    pcb_id = '585f0d4e5ddb4537b2b87cf8e89f1097'
    pcb = docs[pcb_id]
    meta = lambda doc: records(doc, 'META')[0]['data']
    if meta(pcb)['board'] != board or meta(docs[schematic])['board'] != board:
        raise ValueError('Target board relationships changed')
    sch_parts = {}
    for doc in docs.values():
        if doc['head']['docType'] == 'SCH_PAGE' and meta(doc)['schematic'] == schematic:
            for attrs in attributes(doc).values():
                if 'Designator' in attrs:
                    name = attrs['Designator']['value']
                    if name in sch_parts:
                        raise ValueError(f'Duplicate schematic designator {name}')
                    sch_parts[name] = attrs
    pcb_attrs = attributes(pcb)
    nets, pads = {}, {}
    for record in records(pcb, 'PAD_NET'):
        kind, component, pin, _ = json.loads(record['id'])
        if kind != 'PAD_NET':
            raise ValueError('Unexpected pad key')
        name = pcb_attrs[component]['Designator']['value']
        net = record['data']['padNet']
        endpoint = {'component': name, 'pin': pin, 'line': record['line']}
        nets.setdefault(net, []).append(endpoint)
        if pin in pads.setdefault(name, {}) and pads[name][pin] != net:
            raise ValueError(f'Conflicting pad nets {name}.{pin}')
        pads[name][pin] = net
    paths = []
    for channel in 'AB':
        for bit in range(16):
            net = f'ADC{bit}{channel}'
            ends = nets[net]
            resistors = {e['component'] for e in ends if e['component'].startswith('R')}
            if len(ends) != 2 or len(resistors) != 1 or not any(e['component'] == 'U64' for e in ends):
                raise ValueError(f'Unexpected ADC output topology {net}')
            resistor = resistors.pop()
            other = set(pads[resistor].values()) - {net}
            if len(pads[resistor]) != 2 or len(other) != 1:
                raise ValueError(f'Unexpected series resistor {resistor}')
            destination = other.pop()
            connectors = [e for e in nets[destination] if e['component'] in ('CN1', 'CN2')]
            if len(connectors) != 1 or len(nets[destination]) != 2:
                raise ValueError(f'Expected only resistor and one connector for {net}')
            paths.append({'channel': channel, 'bit': bit, 'adc_net': net,
                          'adc_endpoints': ends, 'series_resistor': resistor,
                          'resistor_value': sch_parts[resistor]['Value'],
                          'connector_net': destination,
                          'connector_net_endpoints': nets[destination]})
    if len({p['connector_net'] for p in paths}) != 32:
        raise ValueError('ADC data connector nets are not distinct')
    rbias_net = pads['U64']['58']
    if pads['R148'].get('1') != rbias_net or pads['R148'].get('2') != 'GND':
        raise ValueError('RBIAS topology changed')
    controls = {}
    for name, pin in [('CLK+', '1'), ('CLK-', '2'), ('DCOA', '24'), ('DCOB', '23')]:
        net = pads['U64'][pin]
        controls[name] = {'pcb_net': net, 'endpoints': nets[net]}
    return {
        'source_name': path.name, 'source_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
        'board': {'uuid': board, **meta(docs[board])},
        'schematic_uuid': schematic, 'pcb_uuid': pcb_id,
        'method': 'Final record state after replay; PCB PAD_NET assignments, not copper connectivity or vendor ERC/DRC.',
        'line_numbers': 'One-based lines in the sole .epru ZIP member.',
        'r148': {key: sch_parts['R148'][key] for key in
                 ('Value', 'Tolerance', 'Manufacturer Part', 'Supplier Part', 'Device')},
        'rbias_net': {'name': rbias_net, 'endpoints': nets[rbias_net]},
        'controls': controls, 'adc_paths': paths,
        'checks': {'distinct_adc_connector_nets': 32, 'adc_paths_traced': len(paths),
                   'rbias_resistor_to_ground': True},
    }


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('project', type=Path)
    parser.add_argument('--output', type=Path, help='Write focused board audit JSON')
    args = parser.parse_args()
    documents = read_documents(args.project)
    if args.output:
        if args.output.resolve() == args.project.resolve():
            raise ValueError('Output must not overwrite source')
        result = audit(args.project, documents)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        print(json.dumps(result['checks']))
        raise SystemExit(0)
    for uid, doc in documents.items():
        if doc['head']['docType'] in ['BOARD', 'SCH', 'SCH_PAGE', 'PCB']:
            print(json.dumps({'uuid': uid, 'type': doc['head']['docType'],
                              'meta': [r['data'] for r in records(doc, 'META')]}, ensure_ascii=True))
