// Virtual input keys produced by the touch controls.
//
// They are mapped to the ORIGINAL action / axis names in Config/DefaultInput.ini
// (e.g. Fire -> LeftMouseButton AND PUBGTouch_Fire), so pressing a touch button
// fires exactly the same InputAction event in MyPlayerController as the
// keyboard / mouse. No Blueprint input logic is duplicated.

#pragma once

#include "CoreMinimal.h"
#include "InputCoreTypes.h"

namespace PUBGTouchKeys
{
	extern PUBG_BLUEPRINT_API const FKey MoveX;      // axis, -1..1, right
	extern PUBG_BLUEPRINT_API const FKey MoveY;      // axis, -1..1, forward
	extern PUBG_BLUEPRINT_API const FKey Fire;
	extern PUBG_BLUEPRINT_API const FKey Aim;
	extern PUBG_BLUEPRINT_API const FKey Jump;
	extern PUBG_BLUEPRINT_API const FKey Crouch;
	extern PUBG_BLUEPRINT_API const FKey Prone;
	extern PUBG_BLUEPRINT_API const FKey Sprint;
	extern PUBG_BLUEPRINT_API const FKey Walk;
	extern PUBG_BLUEPRINT_API const FKey Reload;
	extern PUBG_BLUEPRINT_API const FKey Weapon1;
	extern PUBG_BLUEPRINT_API const FKey Weapon2;
	extern PUBG_BLUEPRINT_API const FKey Inventory;
	extern PUBG_BLUEPRINT_API const FKey Interact;
	extern PUBG_BLUEPRINT_API const FKey FireMode;
	extern PUBG_BLUEPRINT_API const FKey Holster;
	extern PUBG_BLUEPRINT_API const FKey Drop;
	extern PUBG_BLUEPRINT_API const FKey FreeLook;

	/** Registers the keys with EKeys (called from the module startup). */
	void RegisterKeys();
}
