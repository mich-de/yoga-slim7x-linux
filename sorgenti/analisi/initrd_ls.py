#!/usr/bin/env python3
"""List interesting content of a dracut initrd (concatenated, possibly compressed newc cpio).
usage: initrd_ls.py <initrd> [dump-regex]"""
import sys, re, lzma, gzip, io


def segments(data):
    pos = 0
    while pos < len(data):
        while pos < len(data) and data[pos] == 0:
            pos += 1
        if pos >= len(data):
            return
        head = data[pos:pos + 6]
        if head == b"070701":
            yield "cpio", data[pos:], True
            return  # parser below walks the plain archive and reports where it ends
        if head[:4] == b"\x28\xb5\x2f\xfd":
            from compression import zstd
            yield "zstd", zstd.decompress(data[pos:]), False; return
        if head == b"\xfd7zXZ\x00":
            yield "xz", lzma.decompress(data[pos:]), False; return
        if head[:2] == b"\x1f\x8b":
            yield "gzip", gzip.decompress(data[pos:]), False; return
        raise SystemExit(f"unknown magic at {pos}: {head!r}")


def cpio_entries(buf):
    p = 0
    while p + 110 <= len(buf):
        if buf[p:p + 6] != b"070701":
            if buf[p] == 0:
                p += 4 - (p % 4) if p % 4 else 4
                continue
            return p
        f = [int(buf[p + 6 + 8 * i: p + 14 + 8 * i], 16) for i in range(13)]
        mode, fsize, nsize = f[1], f[6], f[11]
        name = buf[p + 110:p + 110 + nsize - 1].decode(errors="replace")
        dstart = (p + 110 + nsize + 3) & ~3
        yield name, mode, buf[dstart:dstart + fsize]
        p = (dstart + fsize + 3) & ~3
        if name == "TRAILER!!!":
            yield None, p, None
            return
    return


def main():
    data = open(sys.argv[1], "rb").read()
    dump = re.compile(sys.argv[2]) if len(sys.argv) > 2 else None
    pos, n = 0, 0
    names = []
    while pos < len(data):
        while pos < len(data) and data[pos] == 0:
            pos += 1
        if pos >= len(data):
            break
        head = data[pos:pos + 6]
        if head == b"070701":
            kind, buf, plain = "cpio", data[pos:], True
        elif head[:4] == b"\x28\xb5\x2f\xfd":
            from compression import zstd
            kind, buf, plain = "zstd", zstd.decompress(data[pos:]), False
        elif head == b"\xfd7zXZ\x00":
            kind, buf, plain = "xz", lzma.decompress(data[pos:]), False
        elif head[:2] == b"\x1f\x8b":
            kind, buf, plain = "gzip", gzip.decompress(data[pos:]), False
        else:
            print(f"unknown magic at {pos}: {head!r}"); break
        n += 1
        cnt = 0; end = None
        for name, mode, body in cpio_entries(buf):
            if name is None:
                end = mode; break
            cnt += 1; names.append(name)
            if dump and dump.search(name) and body is not None and (mode & 0o170000) == 0o100000:
                print(f"----- {name} (mode {oct(mode)})"); print(body.decode(errors="replace")[:6000])
        print(f"segment {n}: {kind}, {cnt} entries, {len(buf)} bytes")
        if plain and end:
            pos += end
        else:
            break

    def show(title, rx, limit=40):
        m = [x for x in names if re.search(rx, x)]
        print(f"== {title}: {len(m)}"); [print("  " + x) for x in m[:limit]]

    show("dracut hooks", r"dracut/hooks/[^/]+/.+")
    show("hid / i2c-hid modules", r"/(hid-lenovo|hid-generic|i2c-hid|hid-multitouch|hid\.ko)")
    show("qcom remoteproc modules", r"(qcom_q6v5|qcom_pd_mapper|pmic_glink|qcom_battmgr)")
    show("firmware qcom", r"lib/firmware/(updates/)?qcom/", 30)
    show("live scripts", r"(dmsquash|apply-live|livenet|overlay)")
    show("tools", r"/bin/(cp|mkdir|mount|ln|sh|bash|dash|cat|sed|chmod)$")


main()
