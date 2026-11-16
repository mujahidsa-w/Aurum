#include "Mobile/PUBGTouchKeys.h"

#define LOCTEXT_NAMESPACE "PUBGTouchKeys"

namespace PUBGTouchKeys
{
	const FKey MoveX(TEXT("PUBGTouch_MoveX"));
	const FKey MoveY(TEXT("PUBGTouch_MoveY"));
	const FKey Fire(TEXT("PUBGTouch_Fire"));
	const FKey Aim(TEXT("PUBGTouch_Aim"));
	const FKey Jump(TEXT("PUBGTouch_Jump"));
	const FKey Crouch(TEXT("PUBGTouch_Crouch"));
	const FKey Prone(TEXT("PUBGTouch_Prone"));
	const FKey Sprint(TEXT("PUBGTouch_Sprint"));
	const FKey Walk(TEXT("PUBGTouch_Walk"));
	const FKey Reload(TEXT("PUBGTouch_Reload"));
	const FKey Weapon1(TEXT("PUBGTouch_Weapon1"));
	const FKey Weapon2(TEXT("PUBGTouch_Weapon2"));
	const FKey Inventory(TEXT("PUBGTouch_Inventory"));
	const FKey Interact(TEXT("PUBGTouch_Interact"));
	const FKey FireMode(TEXT("PUBGTouch_FireMode"));
	const FKey Holster(TEXT("PUBGTouch_Holster"));
	const FKey Drop(TEXT("PUBGTouch_Drop"));
	const FKey FreeLook(TEXT("PUBGTouch_FreeLook"));

	void RegisterKeys()
	{
		static bool bRegistered = false;
		if (bRegistered)
		{
			return;
		}
		bRegistered = true;

		const FName Category(TEXT("PUBGTouch"));
		EKeys::AddMenuCategoryDisplayInfo(Category, LOCTEXT("Category", "PUBG Touch Controls"), TEXT("GraphEditor.PadEvent_16x"));

		EKeys::AddKey(FKeyDetails(MoveX, LOCTEXT("MoveX", "Touch Move X"), FKeyDetails::GamepadKey | FKeyDetails::FloatAxis, Category));
		EKeys::AddKey(FKeyDetails(MoveY, LOCTEXT("MoveY", "Touch Move Y"), FKeyDetails::GamepadKey | FKeyDetails::FloatAxis, Category));

		struct FButtonDef { const FKey* Key; FText Name; };
		const FButtonDef Buttons[] = {
			{ &Fire, LOCTEXT("Fire", "Touch Fire") },
			{ &Aim, LOCTEXT("Aim", "Touch Aim") },
			{ &Jump, LOCTEXT("Jump", "Touch Jump") },
			{ &Crouch, LOCTEXT("Crouch", "Touch Crouch") },
			{ &Prone, LOCTEXT("Prone", "Touch Prone") },
			{ &Sprint, LOCTEXT("Sprint", "Touch Sprint") },
			{ &Walk, LOCTEXT("Walk", "Touch Walk") },
			{ &Reload, LOCTEXT("Reload", "Touch Reload") },
			{ &Weapon1, LOCTEXT("Weapon1", "Touch Weapon 1") },
			{ &Weapon2, LOCTEXT("Weapon2", "Touch Weapon 2") },
			{ &Inventory, LOCTEXT("Inventory", "Touch Inventory") },
			{ &Interact, LOCTEXT("Interact", "Touch Interact") },
			{ &FireMode, LOCTEXT("FireMode", "Touch Fire Mode") },
			{ &Holster, LOCTEXT("Holster", "Touch Holster") },
			{ &Drop, LOCTEXT("Drop", "Touch Drop Weapon") },
			{ &FreeLook, LOCTEXT("FreeLook", "Touch Free Look") },
		};
		for (const FButtonDef& Def : Buttons)
		{
			EKeys::AddKey(FKeyDetails(*Def.Key, Def.Name, FKeyDetails::GamepadKey, Category));
		}
	}
}

#undef LOCTEXT_NAMESPACE
