// Editor target.

using UnrealBuildTool;
using System.Collections.Generic;

public class PUBG_BlueprintEditorTarget : TargetRules
{
	public PUBG_BlueprintEditorTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Editor;
		DefaultBuildSettings = BuildSettingsVersion.V2;
		ExtraModuleNames.Add("PUBG_Blueprint");
	}
}
