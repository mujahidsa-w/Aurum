#include "Network/PUBGLoadoutVisualComponent.h"

#include "Core/PUBGBlueprintBridge.h"
#include "Core/PUBGItemData.h"
#include "Core/PUBGSettings.h"

#include "Components/SkeletalMeshComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Engine/GameInstance.h"
#include "Engine/SkeletalMesh.h"
#include "Engine/StaticMesh.h"
#include "Engine/World.h"
#include "GameFramework/Character.h"
#include "Net/UnrealNetwork.h"

UPUBGLoadoutVisualComponent::UPUBGLoadoutVisualComponent()
{
	SetIsReplicatedByDefault(true);
	PrimaryComponentTick.bCanEverTick = true;
}

UPUBGLoadoutVisualComponent* UPUBGLoadoutVisualComponent::Find(const AActor* Actor)
{
	return Actor ? Actor->FindComponentByClass<UPUBGLoadoutVisualComponent>() : nullptr;
}

void UPUBGLoadoutVisualComponent::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
	Super::GetLifetimeReplicatedProps(OutLifetimeProps);
	// The owner's own Blueprint already shows its equipment.
	DOREPLIFETIME_CONDITION(UPUBGLoadoutVisualComponent, Loadout, COND_SkipOwner);
	DOREPLIFETIME(UPUBGLoadoutVisualComponent, CharacterPreset);
}

ACharacter* UPUBGLoadoutVisualComponent::GetCharacter() const
{
	return Cast<ACharacter>(GetOwner());
}

bool UPUBGLoadoutVisualComponent::ShowsRemoteVisuals() const
{
	const ACharacter* Character = GetCharacter();
	return Character && !Character->IsLocallyControlled() && GetNetMode() != NM_DedicatedServer;
}

void UPUBGLoadoutVisualComponent::BeginPlay()
{
	Super::BeginPlay();
	// The Blueprint initialises its own meshes in BeginPlay; re-apply the preset a
	// few times shortly after so it is not overwritten.
	PresetRetryTimer = 0.3f;
	PresetApplications = 0;
}

void UPUBGLoadoutVisualComponent::TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction)
{
	Super::TickComponent(DeltaTime, TickType, ThisTickFunction);
	if (GetNetMode() == NM_DedicatedServer)
	{
		return;
	}
	if (PresetApplications < 3 && CharacterPreset >= 0)
	{
		PresetRetryTimer -= DeltaTime;
		if (PresetRetryTimer <= 0.f)
		{
			PresetRetryTimer = 0.5f;
			++PresetApplications;
			ApplyPreset();
			if (ShowsRemoteVisuals())
			{
				ApplyFashion();
			}
		}
	}
	if (ShowsRemoteVisuals())
	{
		SocketTimer -= DeltaTime;
		if (SocketTimer <= 0.f)
		{
			SocketTimer = 0.2f;
			UpdateWeaponSockets(); // follows the mirrored stance / aim of that player
		}
	}
}

void UPUBGLoadoutVisualComponent::ServerSetLoadout(const FPUBGVisualLoadout& NewLoadout)
{
	if (!GetOwner()->HasAuthority() || NewLoadout == Loadout)
	{
		return;
	}
	Loadout = NewLoadout;
	OnRep_Loadout();
}

void UPUBGLoadoutVisualComponent::ServerSetCharacterPreset(int32 PresetIndex)
{
	if (!GetOwner()->HasAuthority())
	{
		return;
	}
	const int32 Count = UPUBGSettings::Get()->CharacterPresets.Num();
	CharacterPreset = Count > 0 ? FMath::Clamp(PresetIndex, 0, Count - 1) : -1;
	OnRep_Preset();
}

void UPUBGLoadoutVisualComponent::OnRep_Loadout()
{
	if (ShowsRemoteVisuals())
	{
		RefreshRemoteVisuals();
	}
}

void UPUBGLoadoutVisualComponent::OnRep_Preset()
{
	PresetApplications = 0;
	PresetRetryTimer = 0.f;
	ApplyPreset();
}

FName UPUBGLoadoutVisualComponent::GetSocketName(FName GameInstanceVariable, const TCHAR* Fallback) const
{
	const UGameInstance* GameInstance = GetWorld() ? GetWorld()->GetGameInstance() : nullptr;
	FName Value;
	if (GameInstance && PUBGBridge::HasProperty(GameInstance, GameInstanceVariable) && PUBGBridge::GetName(GameInstance, GameInstanceVariable, Value) && !Value.IsNone())
	{
		return Value;
	}
	return FName(Fallback);
}

USkeletalMeshComponent* UPUBGLoadoutVisualComponent::FindNamedMesh(const TCHAR* ComponentName) const
{
	const ACharacter* Character = GetCharacter();
	if (!Character)
	{
		return nullptr;
	}
	TArray<USkeletalMeshComponent*> Meshes;
	Character->GetComponents<USkeletalMeshComponent>(Meshes);
	for (USkeletalMeshComponent* Mesh : Meshes)
	{
		if (Mesh && Mesh->GetFName() == FName(ComponentName))
		{
			return Mesh;
		}
	}
	return nullptr;
}

USkeletalMeshComponent* UPUBGLoadoutVisualComponent::EnsureWeaponMesh(int32 Index)
{
	if (WeaponMeshes.Num() < 2)
	{
		WeaponMeshes.SetNumZeroed(2);
	}
	ACharacter* Character = GetCharacter();
	if (!WeaponMeshes[Index] && Character)
	{
		USkeletalMeshComponent* Mesh = NewObject<USkeletalMeshComponent>(Character, *FString::Printf(TEXT("PUBGRemoteWeapon%d"), Index));
		Mesh->SetCollisionEnabled(ECollisionEnabled::NoCollision);
		Mesh->SetGenerateOverlapEvents(false);
		Mesh->RegisterComponent();
		WeaponMeshes[Index] = Mesh;
	}
	return WeaponMeshes[Index];
}

UStaticMeshComponent* UPUBGLoadoutVisualComponent::EnsureEquipmentMesh(int32 Index)
{
	if (EquipmentMeshes.Num() < 3)
	{
		EquipmentMeshes.SetNumZeroed(3);
	}
	ACharacter* Character = GetCharacter();
	if (!EquipmentMeshes[Index] && Character)
	{
		UStaticMeshComponent* Mesh = NewObject<UStaticMeshComponent>(Character, *FString::Printf(TEXT("PUBGRemoteEquipment%d"), Index));
		Mesh->SetCollisionEnabled(ECollisionEnabled::NoCollision);
		Mesh->SetGenerateOverlapEvents(false);
		Mesh->RegisterComponent();
		EquipmentMeshes[Index] = Mesh;
	}
	return EquipmentMeshes[Index];
}

void UPUBGLoadoutVisualComponent::RefreshRemoteVisuals()
{
	ACharacter* Character = GetCharacter();
	if (!Character || !Character->GetMesh())
	{
		return;
	}
	// Weapons (held + on the back)
	const FName WeaponIDs[2] = { Loadout.Weapon1ID, Loadout.Weapon2ID };
	for (int32 i = 0; i < 2; ++i)
	{
		USkeletalMeshComponent* Mesh = EnsureWeaponMesh(i);
		if (!Mesh)
		{
			continue;
		}
		USkeletalMesh* Asset = WeaponIDs[i].IsNone() ? nullptr : Cast<USkeletalMesh>(PUBGItemData::GetWeaponStats(WeaponIDs[i]).SkeletalMesh.TryLoad());
		Mesh->SetSkeletalMesh(Asset);
		Mesh->SetVisibility(Asset != nullptr);
		CurrentWeaponSockets[i] = NAME_None; // force re-attach
	}
	UpdateWeaponSockets();

	// Helmet / vest / backpack
	const FPUBGBlueprintNames& Names = UPUBGSettings::Get()->BlueprintNames;
	const FName EquipIDs[3] = { Loadout.HelmetID, Loadout.VestID, Loadout.BackpackID };
	const FName Sockets[3] = {
		GetSocketName(Names.HelmetName, TEXT("Socket_Helmet")),
		GetSocketName(Names.VestName, TEXT("Socket_Vest")),
		GetSocketName(Names.BackpackName, TEXT("Socket_Backpack")) };
	for (int32 i = 0; i < 3; ++i)
	{
		UStaticMeshComponent* Mesh = EnsureEquipmentMesh(i);
		if (!Mesh)
		{
			continue;
		}
		UStaticMesh* Asset = nullptr;
		uint8 Type = 255;
		FSoftObjectPath MeshPath;
		if (!EquipIDs[i].IsNone() && PUBGItemData::GetEquipment(EquipIDs[i], Type, MeshPath))
		{
			Asset = Cast<UStaticMesh>(MeshPath.TryLoad());
		}
		Mesh->SetStaticMesh(Asset);
		Mesh->SetVisibility(Asset != nullptr);
		Mesh->AttachToComponent(Character->GetMesh(), FAttachmentTransformRules::SnapToTargetNotIncludingScale, Sockets[i]);
	}
	ApplyFashion();
}

void UPUBGLoadoutVisualComponent::UpdateWeaponSockets()
{
	ACharacter* Character = GetCharacter();
	if (!Character || !Character->GetMesh() || WeaponMeshes.Num() < 2)
	{
		return;
	}
	const FPUBGBlueprintNames& Names = UPUBGSettings::Get()->BlueprintNames;
	// Same rule as MyPlayerController.CalculateHoldGunSocket, using the mirrored flags.
	bool bAiming = false, bSight = false, bProne = false, bCrouch = false;
	PUBGBridge::GetBool(Character, Names.IsAiming, bAiming);
	PUBGBridge::GetBool(Character, Names.IsSightAiming, bSight);
	PUBGBridge::GetBool(Character, Names.IsProne, bProne);
	PUBGBridge::GetBool(Character, Names.IsCrouching, bCrouch);

	FName HeldSocket = GetSocketName(Names.GunStandName, TEXT("Socket_Gun_Stand"));
	if (bAiming || bSight)
	{
		HeldSocket = GetSocketName(Names.GunAimName, TEXT("Socket_Gun_Aim"));
	}
	else if (bProne)
	{
		HeldSocket = GetSocketName(Names.GunProneIdleName, TEXT("Socket_Gun_ProneIdle"));
	}
	else if (bCrouch)
	{
		HeldSocket = GetSocketName(Names.GunCrouchName, TEXT("Socket_Gun_Crouch"));
	}
	const FName BackSockets[2] = {
		GetSocketName(Names.BackLeftName, TEXT("Socket_BackLeft_Normal")),
		GetSocketName(Names.BackRightName, TEXT("Socket_BackRight_Normal")) };

	for (int32 i = 0; i < 2; ++i)
	{
		USkeletalMeshComponent* Mesh = WeaponMeshes[i];
		if (!Mesh)
		{
			continue;
		}
		const FName Wanted = (Loadout.HeldSlot == i + 1) ? HeldSocket : BackSockets[i];
		if (Wanted != CurrentWeaponSockets[i])
		{
			CurrentWeaponSockets[i] = Wanted;
			Mesh->AttachToComponent(Character->GetMesh(), FAttachmentTransformRules::SnapToTargetNotIncludingScale, Wanted);
		}
	}
}

void UPUBGLoadoutVisualComponent::ApplyPreset()
{
	const TArray<FPUBGCharacterPreset>& Presets = UPUBGSettings::Get()->CharacterPresets;
	if (!Presets.IsValidIndex(CharacterPreset))
	{
		return;
	}
	const FPUBGCharacterPreset& Preset = Presets[CharacterPreset];
	auto SetMesh = [this](const TCHAR* ComponentName, const FSoftObjectPath& Path)
	{
		if (!Path.IsValid())
		{
			return;
		}
		if (USkeletalMeshComponent* Component = FindNamedMesh(ComponentName))
		{
			if (USkeletalMesh* Asset = Cast<USkeletalMesh>(Path.TryLoad()))
			{
				Component->SetSkeletalMesh(Asset);
				Component->SetVisibility(true);
			}
		}
	};
	SetMesh(TEXT("SKM_Hair"), Preset.Hair);
	SetMesh(TEXT("SKM_Shoes"), Preset.Shoes);
	if (Preset.Whole.IsValid())
	{
		SetMesh(TEXT("SKM_Whole"), Preset.Whole);
		for (const TCHAR* Hidden : { TEXT("SKM_ClothTop"), TEXT("SKM_ClothBottom") })
		{
			if (USkeletalMeshComponent* Component = FindNamedMesh(Hidden))
			{
				Component->SetVisibility(false);
			}
		}
	}
	else
	{
		SetMesh(TEXT("SKM_ClothTop"), Preset.ClothTop);
		SetMesh(TEXT("SKM_ClothBottom"), Preset.ClothBottom);
	}
}

void UPUBGLoadoutVisualComponent::ApplyFashion()
{
	// E_FashionType: ClothTop, ClothBottom, Whole, Shoes
	static const TCHAR* ComponentByType[4] = { TEXT("SKM_ClothTop"), TEXT("SKM_ClothBottom"), TEXT("SKM_Whole"), TEXT("SKM_Shoes") };
	for (const FName& FashionID : Loadout.FashionIDs)
	{
		uint8 FashionType = 255;
		FSoftObjectPath MeshPath;
		if (!PUBGItemData::GetFashion(FashionID, FashionType, MeshPath) || FashionType > 3)
		{
			continue;
		}
		if (USkeletalMeshComponent* Component = FindNamedMesh(ComponentByType[FashionType]))
		{
			if (USkeletalMesh* Asset = Cast<USkeletalMesh>(MeshPath.TryLoad()))
			{
				Component->SetSkeletalMesh(Asset);
				Component->SetVisibility(true);
			}
		}
	}
}
