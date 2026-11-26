"""Lê a tabela cmap de uma TTF (só biblioteca padrão) para saber quais caracteres têm glifo."""

import struct


def _u16(b, o):
    return struct.unpack_from(">H", b, o)[0]


def _u32(b, o):
    return struct.unpack_from(">I", b, o)[0]


def _format4(b, o, out):
    seg = _u16(b, o + 6) // 2
    end_o = o + 14
    start_o = end_o + 2 * seg + 2
    delta_o = start_o + 2 * seg
    range_o = delta_o + 2 * seg
    for i in range(seg):
        end, start = _u16(b, end_o + 2 * i), _u16(b, start_o + 2 * i)
        delta, ro = _u16(b, delta_o + 2 * i), _u16(b, range_o + 2 * i)
        for c in range(start, min(end, 0xFFFE) + 1):
            if ro == 0:
                gid = (c + delta) & 0xFFFF
            else:
                addr = range_o + 2 * i + ro + 2 * (c - start)
                if addr + 2 > len(b):
                    continue
                gid = _u16(b, addr)
                if gid:
                    gid = (gid + delta) & 0xFFFF
            if gid:
                out.add(c)


def _format12(b, o, out):
    n = _u32(b, o + 12)
    for i in range(n):
        s, e, g = struct.unpack_from(">III", b, o + 16 + 12 * i)
        if g:
            out.update(range(s, e + 1))


def covered_codepoints(path) -> set:
    with open(path, "rb") as f:
        b = f.read()
    tables = {}
    for i in range(_u16(b, 4)):
        tag = b[12 + 16 * i : 16 + 16 * i]
        tables[tag] = _u32(b, 12 + 16 * i + 8)
    base = tables[b"cmap"]
    out = set()
    for i in range(_u16(b, base + 2)):
        off = base + _u32(b, base + 4 + 8 * i + 4)
        fmt = _u16(b, off)
        if fmt == 4:
            _format4(b, off, out)
        elif fmt == 12:
            _format12(b, off, out)
    return out


def missing_chars(text: str, covered: set) -> list:
    """Caracteres do texto sem glifo (quebras de linha e tabs não contam)."""
    return sorted({ch for ch in text if ch not in "\n\r\t" and ord(ch) not in covered})
