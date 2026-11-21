#include "Core/PUBGSettings.h"

#include "GameFramework/Actor.h"

UPUBGSettings::UPUBGSettings()
{
	GameTitle = TEXT("AURUM");
	GameSubtitle = TEXT("Battle Royale Prototype");

	MenuMap = TEXT("/Game/Maps/Level_Test");
	LobbyMap = TEXT("/Game/Maps/Level_Test");
	BattleMaps = { TEXT("/Game/Maps/Level_Test"), TEXT("/Game/Maps/Level_Battle") };
	FrontEndGameAlias = TEXT("FrontEnd");
	LobbyGameAlias = TEXT("Lobby");

	DefaultMaxPlayers = 8;
	MaxPlayersLimit = 16;
	MinPlayersToStart = 1;
	MinPlayersToStartDedicated = 2;
	LobbyCountdownSeconds = 5.f;
	ReturnToLobbyDelay = 15.f;
	DefaultPort = 7777;
	RoomHeartbeatSeconds = 5.f;

	PickupBaseClass = FSoftClassPath(TEXT("/Game/Blueprints/Items/Pickup/PickupBase.PickupBase_C"));
	// Index = E_ItemType: Weapon, Accessories, Ammo, Health, Boost, Helmet, Vest, Backpack, Fashion
	PickupClassesByItemType = {
		FSoftClassPath(TEXT("/Game/Blueprints/Items/Pickup/PickupWeapon.PickupWeapon_C")),
		FSoftClassPath(TEXT("/Game/Blueprints/Items/Pickup/PickupWeaponAcc.PickupWeaponAcc_C")),
		FSoftClassPath(TEXT("/Game/Blueprints/Items/Pickup/PickupAmmo.PickupAmmo_C")),
		FSoftClassPath(TEXT("/Game/Blueprints/Items/Pickup/PickupHealth.PickupHealth_C")),
		FSoftClassPath(TEXT("/Game/Blueprints/Items/Pickup/PickupBoost.PickupBoost_C")),
		FSoftClassPath(TEXT("/Game/Blueprints/Items/Pickup/PickupEquipment.PickupEquipment_C")),
		FSoftClassPath(TEXT("/Game/Blueprints/Items/Pickup/PickupEquipment.PickupEquipment_C")),
		FSoftClassPath(TEXT("/Game/Blueprints/Items/Pickup/PickupEquipment.PickupEquipment_C")),
		// The asset file is "pICKUPfASHION" but the class inside it is PickupFashion_C.
		FSoftClassPath(TEXT("/Game/Blueprints/Items/Pickup/pICKUPfASHION.PickupFashion_C")),
	};
	ImpactDecalClass = FSoftClassPath(TEXT("/Game/Blueprints/Bullet/BulletHoleDecal.BulletHoleDecal_C"));

	MirroredBoolVariables = {
		TEXT("isCrouching"), TEXT("isProne"), TEXT("isAiming"), TEXT("isSightAiming"), TEXT("isHoldWeapon"),
		TEXT("isFiring"), TEXT("isEquip"), TEXT("isReload"), TEXT("isOnTheAir"), TEXT("isFreeFalling"),
		TEXT("isUmbrellaOpened"), TEXT("isPlayingMontage"), TEXT("IsAimAccurate")
	};

	WeaponTable = FSoftObjectPath(TEXT("/Game/Blueprints/Datas/DataTable/Items/DT_Item_Weapon.DT_Item_Weapon"));
	HealthTable = FSoftObjectPath(TEXT("/Game/Blueprints/Datas/DataTable/Items/DT_Item_Health.DT_Item_Health"));
	BoostTable = FSoftObjectPath(TEXT("/Game/Blueprints/Datas/DataTable/Items/DT_Item_Boost.DT_Item_Boost"));
	EquipmentTable = FSoftObjectPath(TEXT("/Game/Blueprints/Datas/DataTable/Items/DT_Item_Equipment.DT_Item_Equipment"));
	AmmoTable = FSoftObjectPath(TEXT("/Game/Blueprints/Datas/DataTable/Items/DT_Item_Ammo.DT_Item_Ammo"));
	FashionTable = FSoftObjectPath(TEXT("/Game/Blueprints/Datas/DataTable/Items/DT_Item_Fashion.DT_Item_Fashion"));
	WeaponAccTable = FSoftObjectPath(TEXT("/Game/Blueprints/Datas/DataTable/Items/DT_Item_WeaponAcc.DT_Item_WeaponAcc"));

	bClientAuthoritativeMovement = true;
	MaxGroundSpeed = 900.f;
	SpeedTolerance = 1.3f;
	MaxCameraOffset = 650.f;
	MaxShotRange = 100000.f;
	HitTargetTolerance = 120.f;
	MaxLatencyCompensation = 0.4f;
	FireRateTolerance = 0.8f;
	PickupClaimRadius = 500.f;

	MaxHealth = 100.f;
	HeadshotMultiplier = 2.0f;
	LimbMultiplier = 0.9f;
	DefaultHelmetReduction = 0.3f;
	DefaultVestReduction = 0.3f;
	DefaultWeaponDamage = 30.f;
	DefaultFiringInterval = 0.1f;
	DefaultClipSize = 30;
	DefaultReloadTime = 2.2f;
	EnergyDrainPerSecond = 1.f;
	EnergyHealPerSecond = 0.5f;

	bForceTouchControls = false;

	auto MakePreset = [](const TCHAR* Name, FLinearColor Color, const TCHAR* Top, const TCHAR* Bottom, const TCHAR* Whole)
	{
		FPUBGCharacterPreset P;
		P.DisplayName = FText::FromString(Name);
		P.UIColor = Color;
		P.Hair = FSoftObjectPath(TEXT("/Game/Assets/Humans/Female/Meshs/Hair/SKM_Cloth_Hair_01.SKM_Cloth_Hair_01"));
		P.Shoes = FSoftObjectPath(TEXT("/Game/Assets/Humans/Female/Meshs/Shoes/SKM_Cloth_Shoes_01.SKM_Cloth_Shoes_01"));
		if (Top) { P.ClothTop = FSoftObjectPath(Top); }
		if (Bottom) { P.ClothBottom = FSoftObjectPath(Bottom); }
		if (Whole) { P.Whole = FSoftObjectPath(Whole); }
		return P;
	};
	CharacterPresets = {
		MakePreset(TEXT("Survivor"), FLinearColor(0.85f, 0.55f, 0.15f),
			TEXT("/Game/Assets/Humans/Female/Meshs/Cloth_Top/SKM_Cloth_Top_01.SKM_Cloth_Top_01"),
			TEXT("/Game/Assets/Humans/Female/Meshs/Cloth_Bottom/SKM_Cloth_Bottom_01.SKM_Cloth_Bottom_01"), nullptr),
		MakePreset(TEXT("Scout"), FLinearColor(0.20f, 0.60f, 0.85f),
			TEXT("/Game/Assets/Humans/Female/Meshs/Cloth_Top/SKM_Cloth_Top_02.SKM_Cloth_Top_02"),
			TEXT("/Game/Assets/Humans/Female/Meshs/Cloth_Bottom/SKM_Cloth_Bottom_02.SKM_Cloth_Bottom_02"), nullptr),
		MakePreset(TEXT("Ranger"), FLinearColor(0.35f, 0.70f, 0.30f),
			TEXT("/Game/Assets/Humans/Female/Meshs/Cloth_Top/SKM_Cloth_Top_03.SKM_Cloth_Top_03"),
			TEXT("/Game/Assets/Humans/Female/Meshs/Cloth_Bottom/SKM_Cloth_Bottom_03.SKM_Cloth_Bottom_03"), nullptr),
		MakePreset(TEXT("Swimmer"), FLinearColor(0.80f, 0.30f, 0.45f), nullptr, nullptr,
			TEXT("/Game/Assets/Humans/Female/Meshs/Cloth_Swimsuit/SKM_Cloth_Swimsuit_01.SKM_Cloth_Swimsuit_01")),
	};
}

FString UPUBGSettings::GetBattleMap(int32 Index) const
{
	if (BattleMaps.IsValidIndex(Index))
	{
		return BattleMaps[Index];
	}
	return BattleMaps.Num() > 0 ? BattleMaps[0] : MenuMap;
}

TSubclassOf<AActor> UPUBGSettings::GetPickupBaseClass() const
{
	return PickupBaseClass.IsValid() ? PickupBaseClass.TryLoadClass<AActor>() : nullptr;
}

TSubclassOf<AActor> UPUBGSettings::GetPickupClassForType(uint8 ItemType) const
{
	if (PickupClassesByItemType.IsValidIndex(ItemType) && PickupClassesByItemType[ItemType].IsValid())
	{
		return PickupClassesByItemType[ItemType].TryLoadClass<AActor>();
	}
	return nullptr;
}
