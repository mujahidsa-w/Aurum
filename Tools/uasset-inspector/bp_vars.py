"""List Blueprint member variables by scanning the generated class export's
serialized ChildProperties (FProperty list) for property-type FNames followed
by the property's own FName. Heuristic but reliable for UE 4.25+ BPGC data."""
import sys, os, struct
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from uasset_dump import parse
PROP_TYPES = {'BoolProperty','ByteProperty','IntProperty','FloatProperty','NameProperty','StrProperty','TextProperty',
 'ObjectProperty','ClassProperty','SoftObjectProperty','SoftClassProperty','StructProperty','ArrayProperty','MapProperty','SetProperty',
 'EnumProperty','MulticastInlineDelegateProperty','DelegateProperty','InterfaceProperty','Int64Property','WeakObjectProperty'}
def vars_of(path, export_suffix='_C'):
    pk = parse(path); names = pk['names']; data = pk['data']
    res = []
    for e in pk['exports']:
        if e['class_name'] not in ('BlueprintGeneratedClass','WidgetBlueprintGeneratedClass','AnimBlueprintGeneratedClass','UserDefinedStruct','Function'):
            continue
        blob = data[e['offset']:e['offset']+e['size']]
        out = []
        for i in range(0, len(blob)-16, 1):
            idx, num = struct.unpack_from('<ii', blob, i)
            if 0 <= idx < len(names) and num == 0 and names[idx] in PROP_TYPES:
                idx2, num2 = struct.unpack_from('<ii', blob, i+8)
                if 0 <= idx2 < len(names) and num2 in (0,) and names[idx2] not in PROP_TYPES and names[idx2] not in ('None',):
                    out.append((names[idx], names[idx2]))
        # dedupe preserving order
        seen=set(); ded=[]
        for t in out:
            if t not in seen: seen.add(t); ded.append(t)
        res.append((e['name'], e['class_name'], ded))
    return res
if __name__ == '__main__':
  for p in sys.argv[1:]:
    for name, cls, props in vars_of(p):
        if cls == 'Function' and not props: continue
        if cls == 'Function' and len(sys.argv) < 0: continue
        if cls != 'Function':
            print('### %s (%s)' % (name, cls))
            print('   ' + ', '.join('%s:%s' % (n, t.replace('Property','')) for t, n in props))
