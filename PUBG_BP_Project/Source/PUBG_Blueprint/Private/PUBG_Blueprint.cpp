#include "PUBG_Blueprint.h"

#include "Modules/ModuleManager.h"
#include "Mobile/PUBGTouchKeys.h"

DEFINE_LOG_CATEGORY(LogPUBG);

void FPUBGBlueprintModule::StartupModule()
{
	// Virtual keys used by the touch controls. They are mapped to the ORIGINAL
	// action/axis names (Fire, Jump, MoveForward ...) in DefaultInput.ini, so the
	// existing MyPlayerController input events keep doing all the work.
	PUBGTouchKeys::RegisterKeys();
}

void FPUBGBlueprintModule::ShutdownModule()
{
}

IMPLEMENT_PRIMARY_GAME_MODULE(FPUBGBlueprintModule, PUBG_Blueprint, "PUBG_Blueprint");
