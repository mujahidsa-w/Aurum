// Dedicated server target.
// NOTE: Unreal Engine 4.26 can only build Server targets from a SOURCE build of
// the engine (GitHub), not from the Epic Games Launcher build. See
// Docs/03-Build-And-Run.md, section "Dedicated Server".

using UnrealBuildTool;
using System.Collections.Generic;

public class PUBG_BlueprintServerTarget : TargetRules
{
	public PUBG_BlueprintServerTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Server;
		DefaultBuildSettings = BuildSettingsVersion.V2;
		ExtraModuleNames.Add("PUBG_Blueprint");
	}
}
