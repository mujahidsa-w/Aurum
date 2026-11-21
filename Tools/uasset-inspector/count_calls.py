import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from uasset_dump import parse
targets = ['GetPlayerController','GetPlayerCharacter','GetPlayerPawn','GetPlayerState','GetPlayerCameraManager','GetGameState','GetGameMode','GetHUD']
for p in sys.argv[1:]:
    pk = parse(p)
    names = pk['names']
    # count K2Node_CallFunction exports is not tied to target; approximate by FMemberReference names present
    present = [t for t in targets if t in names]
    if present:
        print('%-28s %s' % (os.path.basename(p), ', '.join(present)))
