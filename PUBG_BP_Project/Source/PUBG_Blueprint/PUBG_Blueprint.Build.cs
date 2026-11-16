// Build rules for the PUBG_Blueprint game module (UE 4.26).

using UnrealBuildTool;

public class PUBG_Blueprint : ModuleRules
{
	public PUBG_Blueprint(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;

		PublicDependencyModuleNames.AddRange(new string[]
		{
			"Core",
			"CoreUObject",
			"Engine",
			"InputCore",
			"DeveloperSettings",   // UDeveloperSettings lives in its own module since 4.26
			"OnlineSubsystem",
			"OnlineSubsystemUtils",
			"HTTP",
			"Sockets",
			"Json",
			"JsonUtilities"
		});

		PrivateDependencyModuleNames.AddRange(new string[]
		{
			"Slate",
			"SlateCore",
			"UMG",
			"ApplicationCore"
		});

		// The Null subsystem is loaded dynamically through DefaultPlatformService=Null.
		DynamicallyLoadedModuleNames.Add("OnlineSubsystemNull");
	}
}
