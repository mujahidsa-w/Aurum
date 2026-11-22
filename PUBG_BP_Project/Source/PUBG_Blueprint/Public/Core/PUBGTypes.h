// Shared types for the multiplayer / mobile layer.

#pragma once

#include "CoreMinimal.h"
#include "PUBGTypes.generated.h"

/** Per-player connection state shown in lobby / scoreboard. */
UENUM(BlueprintType)
enum class EPUBGConnectionState : uint8
{
	Loading,
	InLobby,
	InGame,
	Disconnected
};

UENUM(BlueprintType)
enum class EPUBGMatchPhase : uint8
{
	WaitingForPlayers,
	InProgress,
	Finished
};

/** Mirrors the Blueprint enum /Game/Blueprints/Datas/Enum/E_ItemType (same order). */
UENUM(BlueprintType)
enum class EPUBGItemType : uint8
{
	Weapon = 0,
	Accessories = 1,
	Ammo = 2,
	Health = 3,
	Boost = 4,
	Helmet = 5,
	Vest = 6,
	Backpack = 7,
	Fashion = 8,
	Unknown = 255
};

UENUM(BlueprintType)
enum class EPUBGGraphicsPreset : uint8
{
	Low,
	Medium,
	High,
	Ultra
};

/** Options used when hosting a room. */
USTRUCT(BlueprintType)
struct FPUBGRoomSettings
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "PUBG|Room")
	FString RoomName = TEXT("Room");

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "PUBG|Room")
	int32 MaxPlayers = 8;

	/** LAN = discover on the local network (Online Subsystem Null). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "PUBG|Room")
	bool bLAN = true;

	/** Empty = public room. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "PUBG|Room")
	FString Password;

	/** Index into UPUBGSettings::BattleMaps. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "PUBG|Room")
	int32 BattleMapIndex = 0;
};

/** One entry of a room list (LAN search result or room-service listing). */
USTRUCT(BlueprintType)
struct FPUBGRoomInfo
{
	GENERATED_BODY()

	UPROPERTY(BlueprintReadOnly, Category = "PUBG|Room") FString RoomName;
	UPROPERTY(BlueprintReadOnly, Category = "PUBG|Room") FString HostName;
	UPROPERTY(BlueprintReadOnly, Category = "PUBG|Room") int32 CurrentPlayers = 0;
	UPROPERTY(BlueprintReadOnly, Category = "PUBG|Room") int32 MaxPlayers = 0;
	UPROPERTY(BlueprintReadOnly, Category = "PUBG|Room") int32 PingMs = 0;
	UPROPERTY(BlueprintReadOnly, Category = "PUBG|Room") bool bHasPassword = false;
	UPROPERTY(BlueprintReadOnly, Category = "PUBG|Room") bool bLAN = false;
	UPROPERTY(BlueprintReadOnly, Category = "PUBG|Room") FString MapName;
	/** Index in the last Online Subsystem search (LAN), -1 for room-service rooms. */
	UPROPERTY(BlueprintReadOnly, Category = "PUBG|Room") int32 SearchResultIndex = -1;
	/** Room-service id / join code (online rooms only). */
	UPROPERTY(BlueprintReadOnly, Category = "PUBG|Room") FString ServiceRoomId;
	UPROPERTY(BlueprintReadOnly, Category = "PUBG|Room") FString JoinCode;
	UPROPERTY(BlueprintReadOnly, Category = "PUBG|Room") FString State;
};

/** (type, id, amount) triple read from the Blueprint inventory. */
USTRUCT()
struct FPUBGItemRecord
{
	GENERATED_BODY()

	UPROPERTY() uint8 ItemType = 255;
	UPROPERTY() FName ID;
	UPROPERTY() int32 Amount = 0;

	bool operator==(const FPUBGItemRecord& O) const { return ItemType == O.ItemType && ID == O.ID && Amount == O.Amount; }
};

/**
 * Compact copy of the owning client's Blueprint inventory (MyPlayerState),
 * sent to the server which reconciles it against its authoritative ledger.
 */
USTRUCT()
struct FPUBGInventorySnapshot
{
	GENERATED_BODY()

	/** ItemsInBackpack + Equipments + Fashions, aggregated per (type, id). */
	UPROPERTY() TArray<FPUBGItemRecord> Items;

	UPROPERTY() FName Weapon1ID;
	UPROPERTY() FName Weapon2ID;
	UPROPERTY() int32 Weapon1Clip = 0;
	UPROPERTY() int32 Weapon2Clip = 0;
	/** 0 = none, 1 = Weapon1, 2 = Weapon2 */
	UPROPERTY() uint8 HeldSlot = 0;
	/** E_ShootMode of the held weapon: 0 Single, 1 Auto */
	UPROPERTY() uint8 ShootMode = 0;

	bool operator==(const FPUBGInventorySnapshot& O) const
	{
		return Items == O.Items && Weapon1ID == O.Weapon1ID && Weapon2ID == O.Weapon2ID && Weapon1Clip == O.Weapon1Clip &&
			Weapon2Clip == O.Weapon2Clip && HeldSlot == O.HeldSlot && ShootMode == O.ShootMode;
	}
	bool operator!=(const FPUBGInventorySnapshot& O) const { return !(*this == O); }
};

/** What other players need to see of someone's equipment. */
USTRUCT(BlueprintType)
struct FPUBGVisualLoadout
{
	GENERATED_BODY()

	UPROPERTY(BlueprintReadOnly, Category = "PUBG|Loadout") FName Weapon1ID;
	UPROPERTY(BlueprintReadOnly, Category = "PUBG|Loadout") FName Weapon2ID;
	UPROPERTY(BlueprintReadOnly, Category = "PUBG|Loadout") uint8 HeldSlot = 0;
	UPROPERTY(BlueprintReadOnly, Category = "PUBG|Loadout") FName HelmetID;
	UPROPERTY(BlueprintReadOnly, Category = "PUBG|Loadout") FName VestID;
	UPROPERTY(BlueprintReadOnly, Category = "PUBG|Loadout") FName BackpackID;
	UPROPERTY(BlueprintReadOnly, Category = "PUBG|Loadout") TArray<FName> FashionIDs;

	FName GetHeldWeaponID() const { return HeldSlot == 1 ? Weapon1ID : (HeldSlot == 2 ? Weapon2ID : NAME_None); }

	bool operator==(const FPUBGVisualLoadout& O) const
	{
		return Weapon1ID == O.Weapon1ID && Weapon2ID == O.Weapon2ID && HeldSlot == O.HeldSlot && HelmetID == O.HelmetID &&
			VestID == O.VestID && BackpackID == O.BackpackID && FashionIDs == O.FashionIDs;
	}
	bool operator!=(const FPUBGVisualLoadout& O) const { return !(*this == O); }
};

/** Cosmetic pose state mirrored from the owning client to everybody else. */
USTRUCT()
struct FPUBGMirrorState
{
	GENERATED_BODY()

	/** Bit i = UPUBGSettings::MirroredBoolVariables[i] */
	UPROPERTY() uint32 Flags = 0;
	UPROPERTY() float ForwardValue = 0.f;
	UPROPERTY() uint8 MontageType = 0;
	UPROPERTY() float Yaw = 0.f;
	UPROPERTY() float MaxWalkSpeed = 0.f;
};

USTRUCT(BlueprintType)
struct FPUBGKillFeedEntry
{
	GENERATED_BODY()

	UPROPERTY(BlueprintReadOnly, Category = "PUBG|Match") FString KillerName;
	UPROPERTY(BlueprintReadOnly, Category = "PUBG|Match") FString VictimName;
	UPROPERTY(BlueprintReadOnly, Category = "PUBG|Match") FName WeaponID;
	UPROPERTY(BlueprintReadOnly, Category = "PUBG|Match") bool bHeadshot = false;
	UPROPERTY(BlueprintReadOnly, Category = "PUBG|Match") float ServerTime = 0.f;
};

/** Outfit preset for the character-select screen (meshes from Assets/Humans). */
USTRUCT(BlueprintType)
struct FPUBGCharacterPreset
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "PUBG|Character") FText DisplayName;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "PUBG|Character") FLinearColor UIColor = FLinearColor::White;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "PUBG|Character", meta = (AllowedClasses = "/Script/Engine.SkeletalMesh")) FSoftObjectPath Hair;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "PUBG|Character", meta = (AllowedClasses = "/Script/Engine.SkeletalMesh")) FSoftObjectPath ClothTop;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "PUBG|Character", meta = (AllowedClasses = "/Script/Engine.SkeletalMesh")) FSoftObjectPath ClothBottom;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "PUBG|Character", meta = (AllowedClasses = "/Script/Engine.SkeletalMesh")) FSoftObjectPath Shoes;
	/** One-piece outfit (E_FashionType::Whole). When set, Top/Bottom are hidden. */
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "PUBG|Character", meta = (AllowedClasses = "/Script/Engine.SkeletalMesh")) FSoftObjectPath Whole;
};

/** Saved position of one touch control (normalized to the safe area). */
USTRUCT(BlueprintType)
struct FPUBGTouchControlLayout
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "PUBG|Touch") FName Id;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "PUBG|Touch") FVector2D Position = FVector2D(0.5f, 0.5f);
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "PUBG|Touch") float Scale = 1.f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "PUBG|Touch") bool bVisible = true;
};
