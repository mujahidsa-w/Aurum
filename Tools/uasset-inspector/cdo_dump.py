"""Dump tagged properties of Blueprint CDO exports (Default__X_C) for UE 4.26."""
import sys, os, struct
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from uasset_dump import parse, Reader
def read_tags(pk, start, end, depth=0):
    names = pk['names']; r = Reader(pk['data']); r.p = start; out = []
    def fn():
        i = r.i32(); n = r.i32()
        b = names[i] if 0 <= i < len(names) else '?'
        return b if n == 0 else '%s_%d' % (b, n-1)
    while r.p < end:
        name = fn()
        if name == 'None': break
        typ = fn(); size = r.i32(); idx = r.i32(); extra = ''
        boolval = None
        if typ == 'StructProperty': extra = fn(); r.guid()
        elif typ == 'BoolProperty': boolval = r.d[r.p]; r.p += 1
        elif typ in ('ByteProperty','EnumProperty'): extra = fn()
        elif typ in ('ArrayProperty','SetProperty'): extra = fn()
        elif typ == 'MapProperty': extra = fn() + ',' + fn()
        hasguid = r.d[r.p]; r.p += 1
        if hasguid: r.guid()
        vstart = r.p; val = None
        if typ == 'BoolProperty': val = bool(boolval)
        elif typ == 'IntProperty': val = struct.unpack_from('<i', r.d, vstart)[0]
        elif typ == 'FloatProperty': val = round(struct.unpack_from('<f', r.d, vstart)[0], 3)
        elif typ == 'NameProperty':
            rr = Reader(r.d); rr.p = vstart; i = rr.i32(); n = rr.i32(); val = names[i] + ('' if n == 0 else '_%d' % (n-1))
        elif typ == 'ByteProperty' and size == 1: val = r.d[vstart]
        elif typ in ('ByteProperty','EnumProperty') and size == 8:
            rr = Reader(r.d); rr.p = vstart; i = rr.i32(); val = names[i]
        elif typ == 'ObjectProperty':
            v = struct.unpack_from('<i', r.d, vstart)[0]
            if v < 0: val = 'import:' + pk['imports'][-v-1]['name']
            elif v > 0: val = 'export:' + pk['exports'][v-1]['name']
            else: val = None
        else: val = '<%s %s %dB>' % (typ, extra, size)
        out.append((name, typ, val))
        r.p = vstart + size
    return out
if __name__ == '__main__':
    for p in sys.argv[1:]:
        pk = parse(p)
        for e in pk['exports']:
            if e['name'].startswith('Default__'):
                print('###', os.path.basename(p), e['name'])
                for n, t, v in read_tags(pk, e['offset'], e['offset'] + e['size']):
                    print('   %s = %s' % (n, v))
