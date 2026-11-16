// PUBG_Blueprint game module.
//
// The original project is Blueprint-only. This module adds a C++ layer on top of
// it (multiplayer, lobby, mobile touch controls, settings) WITHOUT modifying the
// existing Blueprint assets. See Docs/02-Architecture.md.

#pragma once

#include "CoreMinimal.h"
#include "Modules/ModuleInterface.h"

DECLARE_LOG_CATEGORY_EXTERN(LogPUBG, Log, All);

class FPUBGBlueprintModule : public IModuleInterface
{
public:
	virtual void StartupModule() override;
	virtual void ShutdownModule() override;
};
