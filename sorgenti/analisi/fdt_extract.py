#!/usr/bin/env python3
"""Extract the Yoga Slim 7x DTB embedded in Fedora's aarch64 kernel PE and print key facts.
usage: fdt_extract.py <kernel-pe> <out-dir>"""
import struct, sys, os, re

FDT_MAGIC = b"\xd0\x0d\xfe\xed"


def parse_fdt(blob):
    (magic, total, off_struct, off_strings, _rsv, _ver, _lcv, _cpu, sz_strings, sz_struct) = struct.unpack(">10I", blob[:40])
    strings = blob[off_strings:off_strings + sz_strings]

    def sname(off):
        return strings[off:strings.index(b"\0", off)].decode()

    root, stack, p = {}, [], off_struct
    while p < off_struct + sz_struct:
        (tok,) = struct.unpack(">I", blob[p:p + 4]); p += 4
        if tok == 1:
            end = blob.index(b"\0", p); name = blob[p:end].decode(); p = (end + 4) & ~3
            node = {"__name": name, "__props": {}, "__children": {}}
            if stack:
                stack[-1]["__children"][name] = node
            else:
                root = node
            stack.append(node)
        elif tok == 2:
            stack.pop()
        elif tok == 3:
            ln, nameoff = struct.unpack(">II", blob[p:p + 8]); p += 8
            stack[-1]["__props"][sname(nameoff)] = blob[p:p + ln]; p = (p + ln + 3) & ~3
        elif tok == 4:
            continue
        elif tok == 9:
            break
        else:
            raise ValueError(f"bad token {tok} at {p}")
    return root


def walk(node, path=""):
    yield path or "/", node
    for n, c in node["__children"].items():
        yield from walk(c, f"{path}/{n}")


def s(b):
    return [x.decode(errors="replace") for x in b.rstrip(b"\0").split(b"\0")]


def cells(b):
    return [hex(x) for x in struct.unpack(f">{len(b)//4}I", b[:len(b)//4*4])]


def main():
    data = open(sys.argv[1], "rb").read()
    out = sys.argv[2]; os.makedirs(out, exist_ok=True)
    # PE sections
    pe = struct.unpack("<I", data[0x3c:0x40])[0]
    nsec = struct.unpack("<H", data[pe + 6:pe + 8])[0]; opt = struct.unpack("<H", data[pe + 20:pe + 22])[0]
    sec = pe + 24 + opt
    print("PE sections:")
    counts = {}
    for i in range(nsec):
        e = data[sec + 40 * i: sec + 40 * i + 40]
        name = e[:8].rstrip(b"\0").decode(errors="replace"); vsz, _va, rsz, roff = struct.unpack("<4I", e[8:24])
        counts[name] = counts.get(name, 0) + 1
        if name in (".uname", ".osrel", ".cmdline"):
            print(f"  {name}: {data[roff:roff + min(vsz, 300)].rstrip(bytes(1)).decode(errors='replace')!r}")
    print("  " + ", ".join(f"{k}x{v}" for k, v in counts.items()))
    for m in set(re.findall(rb"\d+\.\d+\.\d+-[0-9a-z.]+\.fc\d+\.aarch64", data)):
        print("kernel version string:", m.decode())
    # FDT blobs
    found, pos = [], 0
    while (pos := data.find(FDT_MAGIC, pos)) != -1:
        total = struct.unpack(">I", data[pos + 4:pos + 8])[0]
        if 4096 < total < 2_000_000 and pos + total <= len(data):
            blob = data[pos:pos + total]
            try:
                root = parse_fdt(blob)
                found.append((root["__props"].get("model", b"?").rstrip(b"\0").decode(errors="replace"), blob, root))
                pos += total; continue
            except Exception:
                pass
        pos += 4
    print(f"DTB embedded: {len(found)}")
    qc = sorted({m for m, _, r in found if b"qcom,x1e80100" in r["__props"].get("compatible", b"") or b"qcom,x1p42100" in r["__props"].get("compatible", b"")})
    print("X1E/X1P models:", "; ".join(qc))
    for model, blob, root in found:
        if b"lenovo,yoga-slim7x\0" not in root["__props"].get("compatible", b""):
            continue
        fn = os.path.join(out, "x1e80100-lenovo-yoga-slim7x.dtb"); open(fn, "wb").write(blob)
        print(f"\nSAVED {fn} ({len(blob)} bytes) model={model!r} compatible={s(root['__props']['compatible'])}")
        for path, n in walk(root):
            pr = n["__props"]; base = path.rsplit("/", 1)[-1]
            if "firmware-name" in pr:
                print(f"  firmware-name {path}: {s(pr['firmware-name'])}")
            if "gpio-reserved-ranges" in pr:
                print(f"  gpio-reserved-ranges {path}: {cells(pr['gpio-reserved-ranges'])}")
            if base.startswith(("keyboard@", "touchpad@", "touchscreen@", "embedded-controller@")):
                print(f"  node {path}: compatible={s(pr.get('compatible', b''))} status={s(pr.get('status', b'okay'))} props={sorted(pr)}")
            if base == "sound":
                print(f"  sound model={s(pr.get('model', b''))}")
            if base == "chosen":
                print(f"  chosen: {sorted(pr)}")


main()
