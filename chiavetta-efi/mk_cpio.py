#!/usr/bin/env python3
"""Build an uncompressed newc cpio from a directory tree (root-owned, fixed modes).
usage: mk_cpio.py <src-dir> <out.cpio>
Files under */bin/ get mode 0755, other files 0644, dirs 0755.
Adds symlink updates/etc/systemd/system/multi-user.target.wants/strumenti.service -> ../strumenti.service"""
import os, sys

SYMLINKS = {}


def entry(name, mode, data, ino):
    n = name.encode() + b"\0"
    hdr = "070701" + "".join(f"{v:08X}" for v in (ino, mode, 0, 0, 1, 0, len(data), 0, 0, 0, 0, len(n), 0))
    out = hdr.encode() + n
    out += b"\0" * (-len(out) % 4)
    out += data + b"\0" * (-len(data) % 4)
    return out


def main():
    src, dst = sys.argv[1], sys.argv[2]
    items = []
    for root, dirs, files in os.walk(src):
        dirs.sort()
        rel = os.path.relpath(root, src).replace(os.sep, "/")
        if rel != ".":
            items.append((rel, 0o040755, b""))
        for f in sorted(files):
            p = f"{rel}/{f}" if rel != "." else f
            data = open(os.path.join(root, f), "rb").read()
            if b"\0" not in data:  # solo i testi: i firmware devono restare byte per byte
                data = data.replace(b"\r\n", b"\n")
            items.append((p, 0o100755 if "/bin/" in p else 0o100644, data))
    for link, target in SYMLINKS.items():
        items.append((link, 0o120777, target.encode()))
    items.sort(key=lambda x: x[0])
    blob = b"".join(entry(n, m, d, i + 1) for i, (n, m, d) in enumerate(items))
    blob += entry("TRAILER!!!", 0, b"", 0)
    blob += b"\0" * (-len(blob) % 512)
    open(dst, "wb").write(blob)
    for n, m, d in items:
        print(f"{m:o} {len(d):6d} {n}")
    print(f"written {dst}: {len(blob)} bytes")


main()
