#include "Core/PUBGItemData.h"

#include "Core/PUBGBlueprintBridge.h"
#include "Core/PUBGSettings.h"
#include "Core/PUBGTypes.h"
#include "Engine/DataTable.h"

namespace PUBGItemData
{
	namespace
	{
		bool Row(const FSoftObjectPath& TablePath, FName ID, const UScriptStruct*& OutStruct, const uint8*& OutRow)
		{
			const UDataTable* Table = PUBGBridge::LoadTable(TablePath);
			if (!Table)
			{
				return false;
			}
			OutStruct = Table->GetRowStruct();
			OutRow = PUBGBridge::FindRow(Table, ID);
			return OutStruct && OutRow;
		}
	}

	FPUBGWeaponStats GetWeaponStats(FName WeaponID)
	{
		static TMap<FName, FPUBGWeaponStats> Cache;
		if (const FPUBGWeaponStats* Found = Cache.Find(WeaponID))
		{
			return *Found;
		}

		const UPUBGSettings* Settings = UPUBGSettings::Get();
		FPUBGWeaponStats Stats;
		Stats.Damage = Settings->DefaultWeaponDamage;
		Stats.FiringInterval = Settings->DefaultFiringInterval;
		Stats.ClipSize = Settings->DefaultClipSize;
		Stats.ReloadTime = Settings->DefaultReloadTime;

		const UScriptStruct* Struct = nullptr;
		const uint8* Data = nullptr;
		if (!WeaponID.IsNone() && Row(Settings->WeaponTable, WeaponID, Struct, Data))
		{
			Stats.bFromTable = true;
			int32 IntValue = 0;
			if (PUBGBridge::GetStructInt(Struct, Data, TEXT("Damage"), IntValue)) { Stats.Damage = (float)IntValue; }
			PUBGBridge::GetStructFloat(Struct, Data, TEXT("FiringInterval"), Stats.FiringInterval);
			PUBGBridge::GetStructInt(Struct, Data, TEXT("ClipSize"), Stats.ClipSize);
			PUBGBridge::GetStructFloat(Struct, Data, TEXT("ReplaceClipTime"), Stats.ReloadTime);
			PUBGBridge::GetStructBool(Struct, Data, TEXT("AutoMode"), Stats.bAutoMode);
			PUBGBridge::GetStructName(Struct, Data, TEXT("UseAmmoID"), Stats.AmmoID);
			Stats.SkeletalMesh = PUBGBridge::GetStructObjectPath(Struct, Data, TEXT("SkeletalMesh"));
			Stats.FireSound = PUBGBridge::GetStructObjectPath(Struct, Data, TEXT("FireSound"));
		}
		else if (!WeaponID.IsNone())
		{
			PUBGBridge::WarnOnce(TEXT("WeaponRow.") + WeaponID.ToString(),
				FString::Printf(TEXT("Weapon '%s' not found in DT_Item_Weapon, using default stats."), *WeaponID.ToString()));
		}
		Stats.FiringInterval = FMath::Max(Stats.FiringInterval, 0.02f);
		Stats.ReloadTime = FMath::Max(Stats.ReloadTime, 0.2f);
		Cache.Add(WeaponID, Stats);
		return Stats;
	}

	bool GetHealthItem(FName ID, float& OutValue, float& OutLimit, float& OutUseTime)
	{
		const UScriptStruct* Struct = nullptr;
		const uint8* Data = nullptr;
		if (!Row(UPUBGSettings::Get()->HealthTable, ID, Struct, Data))
		{
			return false;
		}
		OutValue = 0.f;
		OutLimit = 100.f;
		OutUseTime = 0.f;
		PUBGBridge::GetStructFloat(Struct, Data, TEXT("Value"), OutValue);
		PUBGBridge::GetStructFloat(Struct, Data, TEXT("Limit"), OutLimit);
		PUBGBridge::GetStructFloat(Struct, Data, TEXT("UseTime"), OutUseTime);
		return true;
	}

	bool GetBoostItem(FName ID, float& OutBoost, float& OutUseTime)
	{
		const UScriptStruct* Struct = nullptr;
		const uint8* Data = nullptr;
		if (!Row(UPUBGSettings::Get()->BoostTable, ID, Struct, Data))
		{
			return false;
		}
		OutBoost = 0.f;
		OutUseTime = 0.f;
		PUBGBridge::GetStructFloat(Struct, Data, TEXT("BoostValue"), OutBoost);
		PUBGBridge::GetStructFloat(Struct, Data, TEXT("UseTime"), OutUseTime);
		return true;
	}

	bool GetEquipment(FName ID, uint8& OutType, FSoftObjectPath& OutMesh)
	{
		const UScriptStruct* Struct = nullptr;
		const uint8* Data = nullptr;
		if (!Row(UPUBGSettings::Get()->EquipmentTable, ID, Struct, Data))
		{
			return false;
		}
		OutType = (uint8)EPUBGItemType::Unknown;
		PUBGBridge::GetStructByte(Struct, Data, TEXT("Type"), OutType);
		OutMesh = PUBGBridge::GetStructObjectPath(Struct, Data, TEXT("StaticMesh"));
		return true;
	}

	bool GetFashion(FName ID, uint8& OutFashionType, FSoftObjectPath& OutMesh)
	{
		const UScriptStruct* Struct = nullptr;
		const uint8* Data = nullptr;
		if (!Row(UPUBGSettings::Get()->FashionTable, ID, Struct, Data))
		{
			return false;
		}
		OutFashionType = 255;
		PUBGBridge::GetStructByte(Struct, Data, TEXT("Type"), OutFashionType);
		OutMesh = PUBGBridge::GetStructObjectPath(Struct, Data, TEXT("SkeletalMesh"));
		return true;
	}

	bool GetPickupDisplay(uint8 ItemType, FName ID, FPUBGPickupDisplay& Out)
	{
		const UPUBGSettings* Settings = UPUBGSettings::Get();
		const FSoftObjectPath* Table = nullptr;
		const TCHAR* MeshField = TEXT("StaticMesh");
		switch ((EPUBGItemType)ItemType)
		{
		case EPUBGItemType::Weapon: Table = &Settings->WeaponTable; break;
		case EPUBGItemType::Accessories: Table = &Settings->WeaponAccTable; break;
		case EPUBGItemType::Ammo: Table = &Settings->AmmoTable; MeshField = TEXT("PickupMesh"); break;
		case EPUBGItemType::Health: Table = &Settings->HealthTable; break;
		case EPUBGItemType::Boost: Table = &Settings->BoostTable; break;
		case EPUBGItemType::Helmet:
		case EPUBGItemType::Vest:
		case EPUBGItemType::Backpack: Table = &Settings->EquipmentTable; break;
		case EPUBGItemType::Fashion: Table = &Settings->FashionTable; break;
		default: return false;
		}
		const UScriptStruct* Struct = nullptr;
		const uint8* Data = nullptr;
		if (!Row(*Table, ID, Struct, Data))
		{
			return false;
		}
		PUBGBridge::GetStructText(Struct, Data, TEXT("Name"), Out.Name);
		Out.StaticMesh = PUBGBridge::GetStructObjectPath(Struct, Data, MeshField);
		return true;
	}
}
