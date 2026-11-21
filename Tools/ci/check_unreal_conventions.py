#!/usr/bin/env python3
"""Static checks for the PUBG_Blueprint C++ module.

There is no Unreal Engine in the environment this code was written in, so the
module could not be compiled there. This script catches the mistakes that would
otherwise only show up in UnrealHeaderTool, the compiler or the linker:

  1. headers with UCLASS/USTRUCT/UENUM include "<File>.generated.h" last
  2. every UCLASS/USTRUCT has GENERATED_BODY()
  3. Server/Client/NetMulticast UFUNCTIONs have _Implementation (and _Validate
     when WithValidation) definitions
  4. UPROPERTY(Replicated...) <-> DOREPLIFETIME are consistent and every
     ReplicatedUsing= function is a declared UFUNCTION
  5. member functions declared in a class are defined somewhere (link errors)
  6. project includes resolve to real files
  7. engine includes are covered by the module dependencies in Build.cs
  8. braces / parentheses are balanced (comments and strings ignored)
  9. files using LOCTEXT define and undefine LOCTEXT_NAMESPACE

Usage: python3 Tools/ci/check_unreal_conventions.py [ModuleSourceDir]
Exit code 0 = no findings.
"""
import os
import re
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.path.dirname(__file__), '..', '..', 'PUBG_BP_Project', 'Source', 'PUBG_Blueprint')
ROOT = os.path.abspath(ROOT)
PUBLIC = os.path.join(ROOT, 'Public')
PRIVATE = os.path.join(ROOT, 'Private')

findings = []


def finding(path, msg):
    findings.append(f'{os.path.relpath(path, ROOT)}: {msg}')


def read(path):
    with open(path, encoding='utf-8') as f:
        return f.read()


def strip_comments_and_strings(src):
    """Replace comments and string/char literals with spaces (keeps line numbers)."""
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        nxt = src[i + 1] if i + 1 < n else ''
        if c == '/' and nxt == '/':
            while i < n and src[i] != '\n':
                out.append(' ')
                i += 1
        elif c == '/' and nxt == '*':
            while i < n and not (src[i] == '*' and i + 1 < n and src[i + 1] == '/'):
                out.append('\n' if src[i] == '\n' else ' ')
                i += 1
            out.append('  ')
            i += 2
        elif c in '"\'':
            quote = c
            out.append(' ')
            i += 1
            while i < n and src[i] != quote:
                if src[i] == '\\':
                    out.append(' ')
                    i += 1
                out.append('\n' if i < n and src[i] == '\n' else ' ')
                i += 1
            out.append(' ')
            i += 1
        else:
            out.append(c)
            i += 1
    return ''.join(out)


headers, sources = [], []
for base, _, files in os.walk(ROOT):
    for name in files:
        path = os.path.join(base, name)
        if name.endswith('.h'):
            headers.append(path)
        elif name.endswith('.cpp'):
            sources.append(path)

all_cpp_text = {p: read(p) for p in sources}
all_cpp_joined = '\n'.join(strip_comments_and_strings(t) for t in all_cpp_text.values())

# ---------------------------------------------------------------- 8 / 9 everywhere
for path in headers + sources:
    raw = read(path)
    code = strip_comments_and_strings(raw)
    for open_c, close_c in (('{', '}'), ('(', ')'), ('[', ']')):
        if code.count(open_c) != code.count(close_c):
            finding(path, f'unbalanced {open_c}{close_c}: {code.count(open_c)} vs {code.count(close_c)}')
    if re.search(r'\bLOCTEXT\s*\(', code):
        if '#define LOCTEXT_NAMESPACE' not in raw or '#undef LOCTEXT_NAMESPACE' not in raw:
            finding(path, 'uses LOCTEXT without #define/#undef LOCTEXT_NAMESPACE')
    if path.endswith('.h') and '#pragma once' not in raw:
        finding(path, 'missing #pragma once')

# ---------------------------------------------------------------- 6 project includes
PROJECT_DIRS = {'Core', 'Sessions', 'Lobby', 'Network', 'Mobile', 'UI', 'Logic'}
for path in headers + sources:
    for inc in re.findall(r'#include\s+"([^"]+)"', read(path)):
        top = inc.split('/')[0]
        if top in PROJECT_DIRS or inc == 'PUBG_Blueprint.h':
            if not (os.path.exists(os.path.join(PUBLIC, inc)) or os.path.exists(os.path.join(PRIVATE, inc))):
                finding(path, f'include not found: {inc}')

# ---------------------------------------------------------------- 7 module dependencies
build_cs = read(os.path.join(ROOT, 'PUBG_Blueprint.Build.cs'))
deps = set(re.findall(r'"(\w+)"', build_cs))
INCLUDE_MODULE = [
    (r'^Widgets/|^Framework/|^Styling/CoreStyle\.h', 'Slate'),
    (r'^Widgets/SCompoundWidget|^Widgets/SLeafWidget|^Widgets/SWidget|^Rendering/|^Fonts/|^Brushes/|^Styling/Slate|^Input/Reply', 'SlateCore'),
    (r'^Blueprint/|^Components/Widget', 'UMG'),
    (r'^HttpModule\.h|^Interfaces/IHttp|^GenericPlatform/GenericPlatformHttp', 'HTTP'),
    (r'^Dom/Json|^Serialization/Json', 'Json'),
    (r'^SocketSubsystem\.h|^IPAddress\.h', 'Sockets'),
    (r'^OnlineSubsystem\.h|^OnlineSessionSettings|^Interfaces/Online', 'OnlineSubsystem'),
    (r'^OnlineSubsystemUtils', 'OnlineSubsystemUtils'),
    (r'^Engine/DeveloperSettings\.h', 'DeveloperSettings'),
    (r'^InputCoreTypes\.h', 'InputCore'),
]
for path in headers + sources:
    for inc in re.findall(r'#include\s+"([^"]+)"', read(path)):
        for pattern, module in INCLUDE_MODULE:
            if re.search(pattern, inc) and module not in deps:
                finding(path, f'include "{inc}" needs module "{module}" in Build.cs')

# Macro argument list allowing one level of nested parentheses, e.g.
# UCLASS(ClassGroup = (PUBG)) or UPROPERTY(meta = (ClampMin = 1)).
ARGS = r'\((?:[^()]|\([^()]*\))*\)'
ARGS_CAPTURE = r'\(((?:[^()]|\([^()]*\))*)\)'

# ---------------------------------------------------------------- class parsing helpers
CLASS_RE = re.compile(r'\b(class|struct)\s+(?:\w+_API\s+)?([AUFSIE]\w+)\s*(?:final\s*)?(?::[^{;]*)?\{')


def class_bodies(code):
    """Yield (kind, name, body, start) for top-level class/struct definitions."""
    for m in CLASS_RE.finditer(code):
        start = m.end()
        depth = 1
        i = start
        while i < len(code) and depth:
            if code[i] == '{':
                depth += 1
            elif code[i] == '}':
                depth -= 1
            i += 1
        yield m.group(1), m.group(2), code[start:i - 1], m.start()


def depth_one(body):
    """Text of the class body at nesting depth 0. Nested blocks (inline function
    bodies, nested structs) collapse to '{}' so an inline definition never looks
    like a bare declaration."""
    out, depth = [], 0
    for c in body:
        if c == '{':
            if depth == 0:
                out.append('{')
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                out.append('}')
        else:
            out.append(c if depth == 0 else ' ')
    return ''.join(out)


# ---------------------------------------------------------------- 1-5 per header
for header in headers:
    raw = read(header)
    code = strip_comments_and_strings(raw)
    base = os.path.splitext(os.path.basename(header))[0]
    reflected = re.search(r'\b(UCLASS|USTRUCT|UENUM)\s*\(', code)
    includes = re.findall(r'#include\s+"([^"]+)"', raw)
    if reflected:
        gen = f'{base}.generated.h'
        if gen not in includes:
            finding(header, f'missing #include "{gen}"')
        elif includes[-1] != gen:
            finding(header, f'"{gen}" must be the last include')

    for kind, name, body, start in class_bodies(code):
        prefix = code[max(0, start - 200):start]
        is_reflected = re.search(r'\b(UCLASS|USTRUCT)\s*' + ARGS + r'\s*$', prefix.rstrip()) is not None
        if is_reflected and 'GENERATED_BODY()' not in body and 'GENERATED_USTRUCT_BODY()' not in body:
            finding(header, f'{name}: missing GENERATED_BODY()')

        top = depth_one(body)

        # 3. RPCs
        rpc_names = set()
        for m in re.finditer(r'UFUNCTION\s*' + ARGS_CAPTURE + r'\s*(?:virtual\s+)?void\s+(\w+)\s*\(', top):
            spec, func = m.group(1), m.group(2)
            if re.search(r'\b(Server|Client|NetMulticast)\b', spec):
                rpc_names.add(func)
                if not re.search(rf'\b{name}::{func}_Implementation\s*\(', all_cpp_joined):
                    finding(header, f'{name}::{func} is an RPC but {func}_Implementation is not defined')
                if 'WithValidation' in spec and not re.search(rf'\b{name}::{func}_Validate\s*\(', all_cpp_joined):
                    finding(header, f'{name}::{func} has WithValidation but {func}_Validate is not defined')

        # 4. replication
        replicated = {}
        for m in re.finditer(r'UPROPERTY\s*' + ARGS_CAPTURE + r'\s*([^;]*?)\b(\w+)\s*(?:=[^;]*)?;', top):
            spec, prop = m.group(1), m.group(3)
            if re.search(r'\bReplicated(Using)?\b', spec):
                replicated[prop] = spec
                using = re.search(r'ReplicatedUsing\s*=\s*(\w+)', spec)
                if using and not re.search(r'UFUNCTION\s*' + ARGS + rf'\s*(?:virtual\s+)?void\s+{using.group(1)}\s*\(', top):
                    finding(header, f'{name}.{prop}: ReplicatedUsing={using.group(1)} is not a declared UFUNCTION')
        lifetime = set(re.findall(rf'DOREPLIFETIME(?:_CONDITION)?(?:_NOTIFY)?\s*\(\s*{name}\s*,\s*(\w+)', all_cpp_joined))
        for prop in replicated:
            if prop not in lifetime:
                finding(header, f'{name}.{prop} is Replicated but has no DOREPLIFETIME')
        for prop in lifetime:
            if prop not in replicated:
                finding(header, f'DOREPLIFETIME({name}, {prop}) but {prop} is not UPROPERTY(Replicated)')
        if replicated and not re.search(rf'\b{name}::GetLifetimeReplicatedProps\s*\(', all_cpp_joined):
            finding(header, f'{name} has replicated properties but no GetLifetimeReplicatedProps')

        # 5. declared methods must be defined (skip pure virtual, inline, defaulted, RPC stubs)
        cleaned = re.sub(r'UFUNCTION\s*' + ARGS, ' ', top)
        cleaned = re.sub(r'UPROPERTY\s*' + ARGS, ' ', cleaned)
        cleaned = re.sub(r'(GENERATED_BODY|GENERATED_USTRUCT_BODY|SLATE_\w+|DECLARE_\w+)\s*\([^)]*\)', ' ', cleaned)
        for m in re.finditer(r'(?:^|[;:{}])\s*([^;:{}()]*?)\b(~?\w+)\s*\(([^;{}]*?)\)\s*((?:const|override|final|\s)*)\s*;', cleaned):
            ret, func, _, quals = m.group(1), m.group(2), m.group(3), m.group(4)
            if func in rpc_names:
                continue  # defined as _Implementation, checked above
            if func in ('if', 'for', 'while', 'switch', 'return', 'sizeof', 'decltype', 'static_assert'):
                continue
            if '=' in ret or 'friend' in ret or 'using' in ret or 'typedef' in ret:
                continue
            if not ret.strip() and func not in (name, '~' + name):
                continue  # macro invocation or expression
            snippet = cleaned[m.end():m.end() + 3]
            if '= 0' in m.group(0) or '= default' in m.group(0) or '= delete' in m.group(0):
                continue
            if func in (name, '~' + name) or ret.strip():
                pattern = rf'\b{re.escape(name)}::{re.escape(func)}\s*\('
                if not re.search(pattern, all_cpp_joined):
                    finding(header, f'{name}::{func} is declared but never defined (link error)')

if findings:
    print('\n'.join(sorted(set(findings))))
    print(f'\n{len(set(findings))} finding(s)')
    sys.exit(1)
print(f'OK - {len(headers)} headers, {len(sources)} sources checked, no findings.')
