// Replicates the identity of a ground pickup (PickupBase and children).
//
// MyGameMode.GenerateItems spawns pickups on the server only and sets their
// Blueprint variables (ItemType, ID, Amount, SN). The bootstrap makes the actor
// replicate and adds this component, which copies those variables to every
// client BEFORE the pickup's BeginPlay runs there (initial bunch), so the
// pickup's own Blueprint selects the right mesh and the client's pickup logic
// creates the right item.

#pragma once

#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "PUBGPickupReplicationComponent.generated.h"

USTRUCT()
struct FPUBGPickupData
{
	GENERATED_BODY()

	UPROPERTY() uint8 ItemType = 255;
	UPROPERTY() FName ID;
	UPROPERTY() int32 Amount = 1;
	UPROPERTY() FString SN;

	bool IsSet() const { return !ID.IsNone(); }
	bool operator==(const FPUBGPickupData& O) const { return ItemType == O.ItemType && ID == O.ID && Amount == O.Amount && SN == O.SN; }
};

UCLASS(ClassGroup = (PUBG))
class PUBG_BLUEPRINT_API UPUBGPickupReplicationComponent : public UActorComponent
{
	GENERATED_BODY()

public:
	UPUBGPickupReplicationComponent();

	virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;
	virtual void BeginPlay() override;

	/** Server: re-read the Blueprint variables (after spawn or an amount change). */
	void ServerCaptureFromActor();

protected:
	UPROPERTY(ReplicatedUsing = OnRep_Data) FPUBGPickupData Data;

	UFUNCTION() void OnRep_Data();

private:
	void ApplyToActor();
	void RefreshDisplay();
};
