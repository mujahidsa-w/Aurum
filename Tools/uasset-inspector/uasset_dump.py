#!/usr/bin/env python3
"""Minimal UE4 (4.26, FileVersionUE4 522) .uasset header parser.

Reads the package summary, name map, import map and export map so we can
inspect Blueprint structure (parent class, functions, graph nodes, variable
names) without the Unreal Editor. Read-only; never modifies files.
"""
import struct
import sys
import json


class Reader:
    def __init__(self, data):
        self.d = data
        self.p = 0

    def i32(self):
        v = struct.unpack_from('<i', self.d, self.p)[0]
        self.p += 4
        return v

    def u32(self):
        v = struct.unpack_from('<I', self.d, self.p)[0]
        self.p += 4
        return v

    def i64(self):
        v = struct.unpack_from('<q', self.d, self.p)[0]
        self.p += 8
        return v

    def u16(self):
        v = struct.unpack_from('<H', self.d, self.p)[0]
        self.p += 2
        return v

    def guid(self):
        g = self.d[self.p:self.p + 16]
        self.p += 16
        return g.hex()

    def fstring(self):
        n = self.i32()
        if n == 0:
            return ''
        if n > 0:
            s = self.d[self.p:self.p + n - 1].decode('latin-1')
            self.p += n
            return s
        n = -n
        s = self.d[self.p:self.p + 2 * (n - 1)].decode('utf-16-le')
        self.p += 2 * n
        return s


PKG_FILTER_EDITOR_ONLY = 0x80000000


def parse(path):
    data = open(path, 'rb').read()
    r = Reader(data)
    tag = r.u32()
    assert tag == 0x9E2A83C1, 'not a UE package'
    legacy = r.i32()
    if legacy != -4:
        r.i32()  # LegacyUE3Version
    ue4ver = r.i32()
    r.i32()  # licensee
    if legacy <= -2:
        n = r.i32()
        for _ in range(n):
            r.guid()
            r.i32()
    r.i32()  # TotalHeaderSize
    r.fstring()  # FolderName
    pkg_flags = r.u32()
    name_count = r.i32()
    name_off = r.i32()
    if ue4ver >= 516 and not (pkg_flags & PKG_FILTER_EDITOR_ONLY):
        r.fstring()  # LocalizationId
    if ue4ver >= 459:
        r.i32()
        r.i32()
    export_count = r.i32()
    export_off = r.i32()
    import_count = r.i32()
    import_off = r.i32()

    # Names
    r.p = name_off
    names = []
    for _ in range(name_count):
        names.append(r.fstring())
        if ue4ver >= 504:
            r.u16()
            r.u16()

    def fname(rr):
        idx = rr.i32()
        num = rr.i32()
        base = names[idx] if 0 <= idx < len(names) else '<bad:%d>' % idx
        return base if num == 0 else '%s_%d' % (base, num - 1)

    editor_data = not (pkg_flags & PKG_FILTER_EDITOR_ONLY)

    # Imports
    r.p = import_off
    imports = []
    for _ in range(import_count):
        cpkg = fname(r)
        cname = fname(r)
        outer = r.i32()
        oname = fname(r)
        if ue4ver >= 520 and editor_data:
            fname(r)  # PackageName
        imports.append({'class_package': cpkg, 'class': cname, 'outer': outer, 'name': oname})

    # Exports
    r.p = export_off
    exports = []
    for _ in range(export_count):
        cls = r.i32()
        sup = r.i32()
        if ue4ver >= 508:
            r.i32()  # TemplateIndex
        outer = r.i32()
        oname = fname(r)
        oflags = r.u32()
        if ue4ver >= 511:
            ssize = r.i64()
            soff = r.i64()
        else:
            ssize = r.i32()
            soff = r.i32()
        r.i32(); r.i32(); r.i32()  # forced, notforclient, notforserver
        r.guid()
        r.u32()
        if ue4ver >= 365:
            r.i32()
        if ue4ver >= 485:
            r.i32()
        if ue4ver >= 507:
            for _ in range(5):
                r.i32()
        exports.append({'class': cls, 'super': sup, 'outer': outer, 'name': oname,
                        'flags': oflags, 'size': ssize, 'offset': soff})

    def resolve(idx):
        if idx == 0:
            return None
        if idx < 0:
            imp = imports[-idx - 1]
            return imp['name']
        return exports[idx - 1]['name']

    def class_of(idx):
        if idx < 0:
            return imports[-idx - 1]['name']
        if idx > 0:
            return exports[idx - 1]['name']
        return 'Class'

    def path_of(idx):
        parts = []
        while idx != 0:
            if idx < 0:
                imp = imports[-idx - 1]
                parts.append(imp['name'])
                idx = imp['outer']
            else:
                ex = exports[idx - 1]
                parts.append(ex['name'])
                idx = ex['outer']
        return '.'.join(reversed(parts))

    for e in exports:
        e['class_name'] = class_of(e['class'])
        e['super_name'] = path_of(e['super']) if e['super'] else None
        e['outer_name'] = resolve(e['outer'])
    for i in imports:
        i['outer_name'] = resolve(i['outer'])
    return {'ue4ver': ue4ver, 'pkg_flags': pkg_flags, 'names': names,
            'imports': imports, 'exports': exports, 'data': data}


def summarize(path):
    pk = parse(path)
    ex = pk['exports']
    out = {}
    gen = [e for e in ex if e['class_name'] in ('BlueprintGeneratedClass', 'WidgetBlueprintGeneratedClass', 'AnimBlueprintGeneratedClass')]
    out['generated_class'] = [(e['name'], e['super_name']) for e in gen]
    bp = [e for e in ex if e['class_name'] in ('Blueprint', 'WidgetBlueprint', 'AnimBlueprint')]
    out['blueprint'] = [e['name'] for e in bp]
    out['functions'] = sorted({e['name'] for e in ex if e['class_name'] == 'Function'})
    out['graphs'] = sorted({e['name'] for e in ex if e['class_name'] == 'EdGraph'})
    nodes = {}
    for e in ex:
        if e['class_name'].startswith('K2Node') or e['class_name'].startswith('AnimGraphNode'):
            nodes[e['class_name']] = nodes.get(e['class_name'], 0) + 1
    out['node_counts'] = dict(sorted(nodes.items(), key=lambda kv: -kv[1]))
    out['components'] = sorted({e['name'] + ':' + e['class_name'] for e in ex if e['class_name'].endswith('Component') and e['name'].endswith('_GEN_VARIABLE')})
    out['import_functions'] = sorted({i['outer_name'] + '::' + i['name'] for i in pk['imports'] if i['class'] == 'Function'})
    out['import_classes'] = sorted({i['name'] for i in pk['imports'] if i['class'] in ('Class', 'BlueprintGeneratedClass', 'WidgetBlueprintGeneratedClass', 'ScriptStruct', 'UserDefinedStruct', 'UserDefinedEnum', 'Enum')})
    return pk, out


if __name__ == '__main__':
    mode = sys.argv[1]
    for p in sys.argv[2:]:
        pk, s = summarize(p)
        if mode == 'summary':
            print('=' * 100)
            print(p)
            print('parent:', s['generated_class'])
            print('functions:', s['functions'])
            print('graphs:', s['graphs'])
            print('nodes:', s['node_counts'])
            print('components:', s['components'])
        elif mode == 'names':
            print('=' * 100)
            print(p)
            print('\n'.join(pk['names']))
        elif mode == 'imports':
            print('=' * 100)
            print(p)
            print('\n'.join(s['import_functions']))
            print('-- classes/structs/enums --')
            print('\n'.join(s['import_classes']))
        elif mode == 'json':
            print(json.dumps({'path': p, **{k: v for k, v in s.items()}}, default=str))
