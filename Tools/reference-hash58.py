"""GATE T1.2 - hash58 verification on an untouched iPod database.

An independent Python port used to check the Swift implementation. The tables are
extracted programmatically from both references (libgpod BSD-3 + ipod-sharp LGPL-2,
the latter only for comparison), to rule out copying mistakes.

Usage (from a folder holding Hash58.cs and itdb_hash58.c):
    reference-hash58.py <iTunesDB> <FireWire GUID, 16 hex characters>
"""
import re, hashlib, hmac, struct, sys

def parse_arrays(path, names):
    src = open(path, encoding='utf-8', errors='replace').read()
    out = {}
    for n in names:
        # find the name, then the first { ... } block
        i = src.index(n)
        a = src.index('{', i); b = src.index('}', a)
        out[n] = [int(x, 16) for x in re.findall(r'0x([0-9A-Fa-f]{2})', src[a:b])]
    return out

if len(sys.argv) != 3:
    sys.exit(__doc__)
DB, FWID = sys.argv[1], sys.argv[2]

cs = parse_arrays('Hash58.cs', ['table1 = new byte[256]', 'table2 = new byte[256]', '_fixed = new byte[18]'])
c  = parse_arrays('itdb_hash58.c', ['table1[256]', 'table2[256]', 'fixed[18]'])

t1_cs, t2_cs, fx_cs = cs['table1 = new byte[256]'], cs['table2 = new byte[256]'], cs['_fixed = new byte[18]']
t1_c,  t2_c,  fx_c  = c['table1[256]'], c['table2[256]'], c['fixed[18]']

print("== agreement of the references (ipod-sharp vs libgpod) ==")
for label, a, b, n in (("table1", t1_cs, t1_c, 256), ("table2", t2_cs, t2_c, 256), ("fixed", fx_cs, fx_c, 18)):
    ok = (len(a) == n and len(b) == n and a == b)
    print(f"  {label:7s} len={len(a)}/{len(b)}  identical: {'YES' if ok else 'NO'}")
    if not ok: sys.exit("The references differ - stopping")
TABLE1, TABLE2, FIXED = t1_cs, t2_cs, bytes(fx_cs)
print(f"  table1[0..3]={TABLE1[:4]} (AES S-box: {TABLE1[:4] == [0x63,0x7C,0x77,0x7B]})")

def gcd(a, b):
    while True:
        a = a % b
        if a == 0: return b
        b = b % a
        if b == 0: return a

def lcm(a, b):
    return 1 if (a == 0 or b == 0) else (a * b) // gcd(a, b)

def generate_key(fwid8: bytes) -> bytes:
    y = bytearray(16)
    for i in range(4):
        cur = lcm(fwid8[i*2], fwid8[i*2+1])
        hi, lo = (cur & 0xFF00) >> 8, cur & 0xFF
        y[i*4:i*4+4] = bytes((TABLE1[hi], TABLE2[hi], TABLE1[lo], TABLE2[lo]))
    return hashlib.sha1(FIXED + bytes(y)).digest()      # 20 B, HMAC pads it with zeros to 64

def compute_hash58(fwid_hex: str, itdb: bytes) -> bytes:
    fwid8 = bytes.fromhex(fwid_hex)
    assert len(fwid8) == 8, "the FWID must be 16 hex characters"
    return hmac.new(generate_key(fwid8), itdb, hashlib.sha1).digest()

def prepare(itdb: bytes) -> bytes:
    b = bytearray(itdb)
    assert b[0:4] == b'mhbd', "this is not an iTunesDB"
    b[0x18:0x20] = b'\x00' * 8      # db_id
    b[0x32:0x46] = b'\x00' * 20     # unk_0x32
    b[0x58:0x6C] = b'\x00' * 20     # hash58
    struct.pack_into('<H', b, 0x30, 1)   # hashing_scheme = HASH58 (0x72 is the hash72 signature)
    return bytes(b)

raw = open(DB, 'rb').read()
stored = raw[0x58:0x6C]
got    = compute_hash58(FWID, prepare(raw))

print(f"\n== gate T1.2 ==")
print(f"  file      {DB}  ({len(raw)} B)")
print(f"  FWID      {FWID}")
print(f"  stored    {stored.hex()}")
print(f"  computed  {got.hex()}")
print(f"\n  >>> {'MATCH - gate passed' if got == stored else 'MISMATCH'} <<<")
sys.exit(0 if got == stored else 1)
