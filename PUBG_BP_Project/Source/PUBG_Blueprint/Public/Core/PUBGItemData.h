// Read-only access to the ORIGINAL item DataTables (DT_Item_Weapon, ...),
// whose rows are Blueprint structs. Results are cached per row name.

#pragma once

#include "CoreMinimal.h"

struct FPUBGWeaponStats
{
	bool bFromTable = false;
	float Damage = 30.f;
	float FiringInterval = 0.1f;
	int32 ClipSize = 30;
	float ReloadTime = 2.2f;
	bool bAutoMode = true;
	FName AmmoID;
	FSoftObjectPath SkeletalMesh;
	FSoftObjectPath FireSound;
};

struct FPUBGPickupDisplay
{
	FText Name;
	FSoftObjectPath StaticMesh;
};

namespace PUBGItemData
{
	/** DT_Item_Weapon row (falls back to UPUBGSettings defaults when the row is missing). */
	PUBG_BLUEPRINT_API FPUBGWeaponStats GetWeaponStats(FName WeaponID);

	/** DT_Item_Health: heal Value up to Limit after UseTime seconds. */
	PUBG_BLUEPRINT_API bool GetHealthItem(FName ID, float& OutValue, float& OutLimit, float& OutUseTime);

	/** DT_Item_Boost: energy added. */
	PUBG_BLUEPRINT_API bool GetBoostItem(FName ID, float& OutBoost, float& OutUseTime);

	/** DT_Item_Equipment: E_ItemType (Helmet/Vest/Backpack) and the mesh worn on the body. */
	PUBG_BLUEPRINT_API bool GetEquipment(FName ID, uint8& OutType, FSoftObjectPath& OutMesh);

	/** DT_Item_Fashion: E_FashionType (ClothTop, ClothBottom, Whole, Shoes) and skeletal mesh. */
	PUBG_BLUEPRINT_API bool GetFashion(FName ID, uint8& OutFashionType, FSoftObjectPath& OutMesh);

	/** Name + ground mesh for a pickup of the given E_ItemType, as the pickup Blueprints do. */
	PUBG_BLUEPRINT_API bool GetPickupDisplay(uint8 ItemType, FName ID, FPUBGPickupDisplay& Out);
}
