"""Cross-check host parser against packets actually emitted by XSim."""
from pathlib import Path
import struct
from decode_packet import decode

root=Path(__file__).resolve().parents[1]
sim=root/"build/vivado/bia.sim/sim_1/behav/xsim"
for index in range(5):
    lines=(sim/f"packet_{index}.hex").read_text().splitlines()
    blob=b"".join(struct.pack("<I",int(s,16)) for s in lines)
    result=decode(blob,list(range(1,9)),complex(100,0))
    assert result["frame_id"]==100+index
    assert result["valid"] == (index in (0,1,3))
    if result["valid"]:
        for item in result["tones"]:
            if abs(complex(*item["I"]))>1:
                assert abs(complex(*item["channel_ratio"])-2)<1e-9
                assert abs(complex(*item["Z_ohm"])-200)<1e-7
    try:
        decode(blob[:-4])
    except ValueError:
        pass
    else:
        raise AssertionError("Truncated packet accepted")
    (sim/f"packet_{index}.bin").write_bytes(blob)
    print(f"PASS decoder packet {index}: mode={result['mode']} valid={result['valid']}")
print("ALL HOST DECODER TESTS PASSED")
