// Game target (Windows / Android / iOS client and listen server).

using UnrealBuildTool;
using System.Collections.Generic;

public class PUBG_BlueprintTarget : TargetRules
{
	public PUBG_BlueprintTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Game;
		DefaultBuildSettings = BuildSettingsVersion.V2;
		ExtraModuleNames.Add("PUBG_Blueprint");
	}
}
