#include "Network/PUBGPickupReplicationComponent.h"

#include "Core/PUBGBlueprintBridge.h"
#include "Core/PUBGItemData.h"
#include "Core/PUBGSettings.h"

#include "Engine/StaticMesh.h"
#include "GameFramework/Actor.h"
#include "Net/UnrealNetwork.h"

UPUBGPickupReplicationComponent::UPUBGPickupReplicationComponent()
{
	SetIsReplicatedByDefault(true);
	PrimaryComponentTick.bCanEverTick = false;
}

void UPUBGPickupReplicationComponent::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
	Super::GetLifetimeReplicatedProps(OutLifetimeProps);
	DOREPLIFETIME(UPUBGPickupReplicationComponent, Data);
}

void UPUBGPickupReplicationComponent::BeginPlay()
{
	Super::BeginPlay();
	if (GetOwner()->HasAuthority())
	{
		ServerCaptureFromActor();
	}
	else if (Data.IsSet())
	{
		ApplyToActor();
	}
}

void UPUBGPickupReplicationComponent::ServerCaptureFromActor()
{
	AActor* Owner = GetOwner();
	if (!Owner || !Owner->HasAuthority())
	{
		return;
	}
	const FPUBGBlueprintNames& Names = UPUBGSettings::Get()->BlueprintNames;
	FPUBGPickupData NewData;
	PUBGBridge::GetByte(Owner, Names.ItemType, NewData.ItemType);
	PUBGBridge::GetName(Owner, Names.ItemID, NewData.ID);
	PUBGBridge::GetInt(Owner, Names.Amount, NewData.Amount);
	PUBGBridge::GetString(Owner, Names.SN, NewData.SN);
	if (!(NewData == Data))
	{
		Data = NewData;
		Owner->ForceNetUpdate();
	}
}

void UPUBGPickupReplicationComponent::OnRep_Data()
{
	ApplyToActor();
}

void UPUBGPickupReplicationComponent::ApplyToActor()
{
	AActor* Owner = GetOwner();
	if (!Owner || !Data.IsSet())
	{
		return;
	}
	const FPUBGBlueprintNames& Names = UPUBGSettings::Get()->BlueprintNames;
	PUBGBridge::SetByte(Owner, Names.ItemType, Data.ItemType);
	PUBGBridge::SetName(Owner, Names.ItemID, Data.ID);
	PUBGBridge::SetInt(Owner, Names.Amount, Data.Amount);
	PUBGBridge::SetString(Owner, Names.SN, Data.SN);

	// Normally the values arrive before the pickup's BeginPlay and its Blueprint
	// picks the mesh itself. If BeginPlay already ran with empty values, redo the
	// visible part through the Blueprint's own InitPickup().
	if (Owner->HasActorBegunPlay())
	{
		RefreshDisplay();
	}
}

void UPUBGPickupReplicationComponent::RefreshDisplay()
{
	AActor* Owner = GetOwner();
	FPUBGPickupDisplay Display;
	if (!Owner || !PUBGItemData::GetPickupDisplay(Data.ItemType, Data.ID, Display))
	{
		return;
	}
	const FPUBGBlueprintNames& Names = UPUBGSettings::Get()->BlueprintNames;
	UObject* Mesh = Display.StaticMesh.TryLoad();
	FText Prefix;
	PUBGBridge::GetText(Owner, Names.PickupUIPrefix, Prefix);
	const uint8 Type = Data.ItemType;
	// InitPickup(ItemType: E_ItemType, Name: Text, UI_Prefix: Text, StaticMesh: StaticMesh)
	PUBGBridge::CallWithFiller(Owner, Names.PickupInit, [Type, &Display, &Prefix, Mesh](const TArray<FProperty*>& Inputs, uint8* Params)
	{
		if (Inputs.Num() < 4)
		{
			return false;
		}
		PUBGBridge::WriteParamNumber(Inputs[0], Params, Type);
		PUBGBridge::WriteParamText(Inputs[1], Params, Display.Name);
		PUBGBridge::WriteParamText(Inputs[2], Params, Prefix);
		PUBGBridge::WriteParamObject(Inputs[3], Params, Mesh);
		return true;
	});
}
