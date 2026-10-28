#!/usr/bin/env python3
"""Generates Sources/ITDBKit/Signing/Hash58Tables.swift from two references.

The tables are not copied by hand - the script reads both implementations and stops
if they differ. Run it after replacing either reference.

Usage: generate-hash58-tables.py <Hash58.cs> <itdb_hash58.c>
"""
import re, sys, io, pathlib

def parse(path, name):
    src = io.open(path, encoding="utf-8", errors="replace").read()
    i = src.index(name); a = src.index("{", i); b = src.index("}", a)
    return [int(x, 16) for x in re.findall(r"0x([0-9A-Fa-f]{2})", src[a:b])]

def main(cs_path, c_path):
    t1 = parse(cs_path, "table1 = new byte[256]")
    t2 = parse(cs_path, "table2 = new byte[256]")
    fx = parse(cs_path, "_fixed = new byte[18]")
    for label, mine, theirs in (("table1", t1, parse(c_path, "table1[256]")),
                                ("table2", t2, parse(c_path, "table2[256]")),
                                ("fixed",  fx, parse(c_path, "fixed[18]"))):
        if mine != theirs:
            sys.exit(f"{label} differs between the references - stopping")
    assert (len(t1), len(t2), len(fx)) == (256, 256, 18)

    def fmt(vals, per):
        rows = [", ".join(f"0x{v:02X}" for v in vals[i:i+per]) for i in range(0, len(vals), per)]
        return "\n".join("        " + r + "," for r in rows)

    out = f'''// Hash58Tables.swift
//
// GENERATED FILE - do not edit by hand.
// Source: Tools/generate-hash58-tables.py, which reads both references and checks
// that they are identical. table1 is the AES S-box, table2 the inverse AES S-box.

extension Hash58 {{
    /// AES S-box.
    static let table1: [UInt8] = [
{fmt(t1, 8)}
    ]

    /// Inverse AES S-box.
    static let table2: [UInt8] = [
{fmt(t2, 8)}
    ]

    /// The 18-byte constant preceding the key material.
    static let fixedSalt: [UInt8] = [
{fmt(fx, 9)}
    ]
}}
'''
    target = pathlib.Path(__file__).parent.parent / "Sources/ITDBKit/Signing/Hash58Tables.swift"
    target.write_text(out, encoding="utf-8")
    print(f"wrote {target}")

if __name__ == "__main__":
    if len(sys.argv) != 3: sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
