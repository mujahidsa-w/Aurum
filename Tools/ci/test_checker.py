#!/usr/bin/env python3
"""Mutation test for check_unreal_conventions.py: injects one known defect at a
time into a copy of the module and verifies the checker reports it."""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
MODULE = os.path.abspath(os.path.join(HERE, '..', '..', 'PUBG_BP_Project', 'Source', 'PUBG_Blueprint'))
CHECKER = os.path.join(HERE, 'check_unreal_conventions.py')

# (file, original text, replacement, expected substring in the report)
MUTATIONS = [
    ('Private/Network/PUBGHealthComponent.cpp', 'DOREPLIFETIME(UPUBGHealthComponent, MaxHealth);', '',
     'MaxHealth is Replicated but has no DOREPLIFETIME'),
    ('Private/Network/PUBGPlayerNetComponent.cpp', 'UPUBGPlayerNetComponent::ServerShot_Validate(', 'UPUBGPlayerNetComponent::ServerShotX_Validate(',
     'ServerShot_Validate is not defined'),
    ('Private/Network/PUBGCombatComponent.cpp', 'UPUBGCombatComponent::MulticastShotFX_Implementation(', 'UPUBGCombatComponent::MulticastShotFXX(',
     'MulticastShotFX_Implementation is not defined'),
    ('Private/Lobby/PUBGLobbyGameMode.cpp', 'void APUBGLobbyGameMode::CancelCountdown()', 'void APUBGLobbyGameMode::CancelCountdownX()',
     'APUBGLobbyGameMode::CancelCountdown is declared but never defined'),
    ('Public/Lobby/PUBGLobbyGameState.h', '#include "PUBGLobbyGameState.generated.h"', '',
     'missing #include "PUBGLobbyGameState.generated.h"'),
    ('Public/Network/PUBGMatchStateComponent.h', '\tGENERATED_BODY()\n', '\n',
     'UPUBGMatchStateComponent: missing GENERATED_BODY()'),
    ('Private/UI/SPUBGGameHud.cpp', '#include "UI/PUBGUIStyle.h"', '#include "UI/PUBGUIStyleMissing.h"',
     'include not found: UI/PUBGUIStyleMissing.h'),
    ('PUBG_Blueprint.Build.cs', '"Sockets",', '',
     'needs module "Sockets"'),
    ('Private/Mobile/PUBGTouchKeys.cpp', 'void RegisterKeys()\n\t{', 'void RegisterKeys()\n\t{{',
     'unbalanced {}'),
    ('Private/UI/SPUBGLobbyPanel.cpp', '#undef LOCTEXT_NAMESPACE', '',
     'uses LOCTEXT without #define/#undef LOCTEXT_NAMESPACE'),
    ('Public/Network/PUBGStateMirrorComponent.h', 'UPROPERTY(ReplicatedUsing = OnRep_State) FPUBGMirrorState State;',
     'UPROPERTY(ReplicatedUsing = OnRep_StateMissing) FPUBGMirrorState State;',
     'ReplicatedUsing=OnRep_StateMissing is not a declared UFUNCTION'),
]


def run(root):
    proc = subprocess.run([sys.executable, '-I', CHECKER, root], capture_output=True, text=True)
    return proc.returncode, proc.stdout + proc.stderr


def main():
    code, out = run(MODULE)
    assert code == 0, 'checker must pass on the real module first:\n' + out
    failures = 0
    for rel, old, new, expected in MUTATIONS:
        tmp = tempfile.mkdtemp()
        try:
            dst = os.path.join(tmp, 'PUBG_Blueprint')
            shutil.copytree(MODULE, dst)
            path = os.path.join(dst, rel)
            with open(path, encoding='utf-8') as f:
                text = f.read()
            assert old in text, f'mutation anchor not found in {rel}: {old!r}'
            with open(path, 'w', encoding='utf-8') as f:
                f.write(text.replace(old, new, 1))
            code, out = run(dst)
            ok = code != 0 and expected in out
            print(('DETECTED ' if ok else 'MISSED   ') + expected)
            failures += 0 if ok else 1
        finally:
            shutil.rmtree(tmp)
    print(f'{len(MUTATIONS) - failures}/{len(MUTATIONS)} injected defects detected')
    sys.exit(1 if failures else 0)


if __name__ == '__main__':
    main()
