// Project settings for the multiplayer / mobile layer.
// Edit in the editor: Project Settings > Game > PUBG Multiplayer & Mobile,
// or in Config/DefaultGame.ini under [/Script/PUBG_Blueprint.PUBGSettings].

#pragma once

#include "CoreMinimal.h"
#include "Engine/DeveloperSettings.h"
#include "Core/PUBGTypes.h"
#include "PUBGSettings.generated.h"

/**
 * Names of the variables / functions inside the ORIGINAL Blueprints that the C++
 * layer reads or writes through reflection. They were extracted from the
 * .uasset files (see Docs/01-Project-Analysis.md). If a Blueprint is renamed,
 * update the name here instead of recompiling.
 */
USTRUCT(BlueprintType)
struct FPUBGBlueprintNames
{
	GENERATED_BODY()

	// --- MyCharacter ---------------------------------------------------------
	UPROPERTY(EditAnywhere, Category = "Character") FName IsDead = TEXT("isDead");
	UPROPERTY(EditAnywhere, Category = "Character") FName IsAiming = TEXT("isAiming");
	UPROPERTY(EditAnywhere, Category = "Character") FName IsSightAiming = TEXT("isSightAiming");
	UPROPERTY(EditAnywhere, Category = "Character") FName IsCrouching = TEXT("isCrouching");
	UPROPERTY(EditAnywhere, Category = "Character") FName IsProne = TEXT("isProne");
	UPROPERTY(EditAnywhere, Category = "Character") FName IsHoldWeapon = TEXT("isHoldWeapon");
	UPROPERTY(EditAnywhere, Category = "Character") FName IsOnTheAir = TEXT("isOnTheAir");
	UPROPERTY(EditAnywhere, Category = "Character") FName IsFreeFalling = TEXT("isFreeFalling");
	UPROPERTY(EditAnywhere, Category = "Character") FName IsUmbrellaOpened = TEXT("isUmbrellaOpened");
	UPROPERTY(EditAnywhere, Category = "Character") FName ForwardValue = TEXT("ForwardValue");
	UPROPERTY(EditAnywhere, Category = "Character") FName PlayingMontageType = TEXT("PlayingMontageType");

	// --- MyPlayerState -------------------------------------------------------
	UPROPERTY(EditAnywhere, Category = "PlayerState") FName SetHealthPoint = TEXT("SetHealthPoint");
	UPROPERTY(EditAnywhere, Category = "PlayerState") FName SetEnergyPoint = TEXT("SetEnergyPoint");
	UPROPERTY(EditAnywhere, Category = "PlayerState") FName RemoveItem = TEXT("RemoveItem");
	UPROPERTY(EditAnywhere, Category = "PlayerState") FName KilledAmount = TEXT("KilledAmount");
	UPROPERTY(EditAnywhere, Category = "PlayerState") FName Weapon1 = TEXT("Weapon1");
	UPROPERTY(EditAnywhere, Category = "PlayerState") FName Weapon2 = TEXT("Weapon2");
	UPROPERTY(EditAnywhere, Category = "PlayerState") FName HoldGun = TEXT("HoldGun");
	UPROPERTY(EditAnywhere, Category = "PlayerState") FName Equipments = TEXT("Equipments");
	UPROPERTY(EditAnywhere, Category = "PlayerState") FName Fashions = TEXT("Fashions");
	UPROPERTY(EditAnywhere, Category = "PlayerState") FName ItemsInBackpack = TEXT("ItemsInBackpack");

	// --- ItemBase / ItemWeapon / PickupBase -------------------------------------
	UPROPERTY(EditAnywhere, Category = "Items") FName ItemType = TEXT("ItemType");
	UPROPERTY(EditAnywhere, Category = "Items") FName ItemID = TEXT("ID");
	UPROPERTY(EditAnywhere, Category = "Items") FName Amount = TEXT("Amount");
	UPROPERTY(EditAnywhere, Category = "Items") FName SN = TEXT("SN");
	UPROPERTY(EditAnywhere, Category = "Items") FName WeaponClipAmmo = TEXT("Ammo");
	UPROPERTY(EditAnywhere, Category = "Items") FName WeaponShootMode = TEXT("ShootMode");
	UPROPERTY(EditAnywhere, Category = "Items") FName PickupInit = TEXT("InitPickup");
	UPROPERTY(EditAnywhere, Category = "Items") FName PickupUIPrefix = TEXT("UI_Prefix");

	// --- MyPlayerController ------------------------------------------------------
	UPROPERTY(EditAnywhere, Category = "Controller") FName ItemsInRange = TEXT("ItemsInRange");
	UPROPERTY(EditAnywhere, Category = "Controller") FName ReadyPickupItem = TEXT("ReadyPickupItem");
	UPROPERTY(EditAnywhere, Category = "Controller") FName InventoryUI = TEXT("InventoryUI");

	// --- MyGameInstance (socket names) ---------------------------------------------
	UPROPERTY(EditAnywhere, Category = "Sockets") FName GunStandName = TEXT("GunStandName");
	UPROPERTY(EditAnywhere, Category = "Sockets") FName GunAimName = TEXT("GunAimName");
	UPROPERTY(EditAnywhere, Category = "Sockets") FName GunCrouchName = TEXT("GunCrouchName");
	UPROPERTY(EditAnywhere, Category = "Sockets") FName GunProneIdleName = TEXT("GunProneIdleName");
	UPROPERTY(EditAnywhere, Category = "Sockets") FName BackLeftName = TEXT("BackLeftNName");
	UPROPERTY(EditAnywhere, Category = "Sockets") FName BackRightName = TEXT("BackRightNName");
	UPROPERTY(EditAnywhere, Category = "Sockets") FName HelmetName = TEXT("HelmetName");
	UPROPERTY(EditAnywhere, Category = "Sockets") FName VestName = TEXT("VestName");
	UPROPERTY(EditAnywhere, Category = "Sockets") FName BackpackName = TEXT("BackpackName");
};

UCLASS(config = Game, defaultconfig, meta = (DisplayName = "PUBG Multiplayer & Mobile"))
class PUBG_BLUEPRINT_API UPUBGSettings : public UDeveloperSettings
{
	GENERATED_BODY()

public:
	UPUBGSettings();

	static const UPUBGSettings* Get() { return GetDefault<UPUBGSettings>(); }

	virtual FName GetCategoryName() const override { return TEXT("Game"); }

	// ---------------------------------------------------------------- Branding
	UPROPERTY(config, EditAnywhere, Category = "Branding") FString GameTitle;
	UPROPERTY(config, EditAnywhere, Category = "Branding") FString GameSubtitle;

	// ---------------------------------------------------------------- Maps
	/** Map shown behind the main menu (loaded with ?game=FrontEndGameAlias). */
	UPROPERTY(config, EditAnywhere, Category = "Maps") FString MenuMap;
	/** Map used for the pre-match lobby (loaded with ?game=LobbyGameAlias). */
	UPROPERTY(config, EditAnywhere, Category = "Maps") FString LobbyMap;
	/** Maps a host can pick for the match. They run their own (Blueprint) GameMode. */
	UPROPERTY(config, EditAnywhere, Category = "Maps") TArray<FString> BattleMaps;
	UPROPERTY(config, EditAnywhere, Category = "Maps") FString FrontEndGameAlias;
	UPROPERTY(config, EditAnywhere, Category = "Maps") FString LobbyGameAlias;

	// ---------------------------------------------------------------- Rooms / sessions
	UPROPERTY(config, EditAnywhere, Category = "Rooms", meta = (ClampMin = 2, ClampMax = 64)) int32 DefaultMaxPlayers;
	UPROPERTY(config, EditAnywhere, Category = "Rooms", meta = (ClampMin = 2, ClampMax = 64)) int32 MaxPlayersLimit;
	/** Minimum connected players before a listen-server host can start. */
	UPROPERTY(config, EditAnywhere, Category = "Rooms", meta = (ClampMin = 1)) int32 MinPlayersToStart;
	/** Dedicated servers start automatically when everyone is ready and at least this many players are in. */
	UPROPERTY(config, EditAnywhere, Category = "Rooms", meta = (ClampMin = 1)) int32 MinPlayersToStartDedicated;
	UPROPERTY(config, EditAnywhere, Category = "Rooms", meta = (ClampMin = 0)) float LobbyCountdownSeconds;
	UPROPERTY(config, EditAnywhere, Category = "Rooms", meta = (ClampMin = 3)) float ReturnToLobbyDelay;
	UPROPERTY(config, EditAnywhere, Category = "Rooms") int32 DefaultPort;

	/** Base URL of Tools/RoomService (e.g. http://my-server:8080). Empty disables online rooms. */
	UPROPERTY(config, EditAnywhere, Category = "Rooms") FString RoomServiceURL;
	UPROPERTY(config, EditAnywhere, Category = "Rooms", meta = (ClampMin = 1)) float RoomHeartbeatSeconds;

	// ---------------------------------------------------------------- Blueprint integration
	UPROPERTY(config, EditAnywhere, Category = "Blueprint Integration") FPUBGBlueprintNames BlueprintNames;
	UPROPERTY(config, EditAnywhere, Category = "Blueprint Integration", meta = (MetaClass = "Actor")) FSoftClassPath PickupBaseClass;
	/** Pickup class to spawn when a dropped item must be re-created on the server, indexed by E_ItemType. */
	UPROPERTY(config, EditAnywhere, Category = "Blueprint Integration", meta = (MetaClass = "Actor")) TArray<FSoftClassPath> PickupClassesByItemType;
	UPROPERTY(config, EditAnywhere, Category = "Blueprint Integration", meta = (MetaClass = "Actor")) FSoftClassPath ImpactDecalClass;
	/** MyCharacter bools copied from each player to everybody (drives MyAnimeBlueprint). Max 32. */
	UPROPERTY(config, EditAnywhere, Category = "Blueprint Integration") TArray<FName> MirroredBoolVariables;

	UPROPERTY(config, EditAnywhere, Category = "Data Tables", meta = (AllowedClasses = "DataTable")) FSoftObjectPath WeaponTable;
	UPROPERTY(config, EditAnywhere, Category = "Data Tables", meta = (AllowedClasses = "DataTable")) FSoftObjectPath HealthTable;
	UPROPERTY(config, EditAnywhere, Category = "Data Tables", meta = (AllowedClasses = "DataTable")) FSoftObjectPath BoostTable;
	UPROPERTY(config, EditAnywhere, Category = "Data Tables", meta = (AllowedClasses = "DataTable")) FSoftObjectPath EquipmentTable;
	UPROPERTY(config, EditAnywhere, Category = "Data Tables", meta = (AllowedClasses = "DataTable")) FSoftObjectPath AmmoTable;
	UPROPERTY(config, EditAnywhere, Category = "Data Tables", meta = (AllowedClasses = "DataTable")) FSoftObjectPath FashionTable;
	UPROPERTY(config, EditAnywhere, Category = "Data Tables", meta = (AllowedClasses = "DataTable")) FSoftObjectPath WeaponAccTable;

	// ---------------------------------------------------------------- Authority / anti-cheat
	/**
	 * The original MyPlayerController moves the pawn with SetActorLocation, which the
	 * CharacterMovementComponent would otherwise rubber-band. When true the server
	 * accepts client positions and bounds them with a speed check instead.
	 * Set false only after ExecuteMove is converted to AddMovementInput.
	 */
	UPROPERTY(config, EditAnywhere, Category = "Authority") bool bClientAuthoritativeMovement;
	UPROPERTY(config, EditAnywhere, Category = "Authority") float MaxGroundSpeed;
	UPROPERTY(config, EditAnywhere, Category = "Authority") float SpeedTolerance;
	UPROPERTY(config, EditAnywhere, Category = "Authority") float MaxCameraOffset;
	UPROPERTY(config, EditAnywhere, Category = "Authority") float MaxShotRange;
	UPROPERTY(config, EditAnywhere, Category = "Authority") float HitTargetTolerance;
	UPROPERTY(config, EditAnywhere, Category = "Authority") float MaxLatencyCompensation;
	UPROPERTY(config, EditAnywhere, Category = "Authority") float FireRateTolerance;
	UPROPERTY(config, EditAnywhere, Category = "Authority") float PickupClaimRadius;

	// ---------------------------------------------------------------- Combat
	UPROPERTY(config, EditAnywhere, Category = "Combat") float MaxHealth;
	UPROPERTY(config, EditAnywhere, Category = "Combat") float HeadshotMultiplier;
	UPROPERTY(config, EditAnywhere, Category = "Combat") float LimbMultiplier;
	UPROPERTY(config, EditAnywhere, Category = "Combat") float DefaultHelmetReduction;
	UPROPERTY(config, EditAnywhere, Category = "Combat") float DefaultVestReduction;
	/** Optional per-item armor reduction (e.g. Helmet_Lv3 = 0.55). Overrides the defaults above. */
	UPROPERTY(config, EditAnywhere, Category = "Combat") TMap<FName, float> ArmorReductionById;
	/** Fallbacks when a weapon row cannot be read from DT_Item_Weapon. */
	UPROPERTY(config, EditAnywhere, Category = "Combat") float DefaultWeaponDamage;
	UPROPERTY(config, EditAnywhere, Category = "Combat") float DefaultFiringInterval;
	UPROPERTY(config, EditAnywhere, Category = "Combat") int32 DefaultClipSize;
	UPROPERTY(config, EditAnywhere, Category = "Combat") float DefaultReloadTime;
	UPROPERTY(config, EditAnywhere, Category = "Combat") float EnergyDrainPerSecond;
	UPROPERTY(config, EditAnywhere, Category = "Combat") float EnergyHealPerSecond;

	// ---------------------------------------------------------------- Mobile
	/** Show the touch controls on desktop too (testing with "Use Mouse for Touch"). */
	UPROPERTY(config, EditAnywhere, Category = "Mobile") bool bForceTouchControls;
	UPROPERTY(config, EditAnywhere, Category = "Mobile") TArray<FPUBGCharacterPreset> CharacterPresets;

	// ---------------------------------------------------------------- Helpers
	FString GetBattleMap(int32 Index) const;
	TSubclassOf<AActor> GetPickupBaseClass() const;
	TSubclassOf<AActor> GetPickupClassForType(uint8 ItemType) const;
};
