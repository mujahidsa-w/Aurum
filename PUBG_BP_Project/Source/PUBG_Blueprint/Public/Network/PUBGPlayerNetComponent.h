// Per-player network bridge, attached at runtime to MyPlayerController.
//
// OWNING CLIENT
//   * Reads the ORIGINAL Blueprint inventory (MyPlayerState: Weapon1/2, HoldGun,
//     ItemsInBackpack, Equipments, Fashions) and sends a compact snapshot when it
//     changes.
//   * Detects every real shot of the Blueprint weapon (ItemWeapon.Ammo going
//     down) and sends it to the server - same channel as the snapshots, so the
//     server sees shots and inventory changes in order.
//   * Detects items the Blueprint drops (it spawns a local, non-replicated
//     pickup), removes that local copy and asks the server to drop it for real.
//
// SERVER
//   * Keeps an authoritative ledger. An item only becomes "verified" when a
//     matching replicated pickup lying near the player can be claimed (and is
//     then removed for everyone). Ammo, magazines and reloads are tracked so a
//     modified client cannot fire more bullets than it picked up.
//   * Applies the effects of consumables (DT_Item_Health / DT_Item_Boost).
//   * Publishes the visible loadout (weapons, helmet, vest, backpack, outfit).
//
// On a listen server the host's own inventory runs on the server already, so it
// is trusted as-is.

#pragma once

#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "Core/PUBGTypes.h"
#include "Logic/PUBGNetLogic.h"
#include "Network/PUBGCombatComponent.h"
#include "PUBGPlayerNetComponent.generated.h"

class APlayerController;
class APawn;

UCLASS(ClassGroup = (PUBG))
class PUBG_BLUEPRINT_API UPUBGPlayerNetComponent : public UActorComponent
{
	GENERATED_BODY()

public:
	UPUBGPlayerNetComponent();

	static UPUBGPlayerNetComponent* Find(const AController* Controller);

	virtual void BeginPlay() override;
	virtual void EndPlay(const EEndPlayReason::Type EndPlayReason) override;
	virtual void TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction) override;

	// ---- Server queries used by the combat code
	bool GetHeldWeapon(FName& OutWeaponID, int32& OutSlot) const;
	bool ServerTryConsumeShot(double Now);
	/** Armor reduction (0..1) of the verified helmet / vest. */
	float GetArmorReduction(bool bHead) const;
	bool IsTrustedLocal() const;

	// ---- UI
	FString LastNotice;
	double LastNoticeTime = -100.0;

	UFUNCTION(Server, Reliable, WithValidation) void ServerShot(const FPUBGShot& Shot);

protected:
	UFUNCTION(Server, Reliable, WithValidation) void ServerSubmitSnapshot(const FPUBGInventorySnapshot& Snapshot);
	UFUNCTION(Server, Reliable, WithValidation) void ServerReportDrop(const FPUBGItemRecord& Item, FVector_NetQuantize Location);
	UFUNCTION(Client, Reliable) void ClientRejectItem(const FPUBGItemRecord& Item, const FString& Reason);
	UFUNCTION(Client, Reliable) void ClientNotice(const FString& Message);

private:
	APlayerController* GetPC() const;
	APawn* GetPawn() const;
	bool IsOwningClient() const;

	// Owning client
	bool BuildSnapshot(FPUBGInventorySnapshot& Out) const;
	void DetectShots();
	void HandleActorSpawned(AActor* Actor);
	void ProcessPendingDrops();

	// Server
	void ApplySnapshot(const FPUBGInventorySnapshot& Snapshot);
	void ApplyTrustedSnapshot(const FPUBGInventorySnapshot& Snapshot);
	void ReconcileWeapons(const FPUBGInventorySnapshot& Snapshot, double Now);
	void ReconcileAmmo(const FPUBGInventorySnapshot& Snapshot);
	void ReconcileItems(const FPUBGInventorySnapshot& Snapshot);
	void QueueConsumption(uint8 Type, FName ID, int32 Count);
	void ProcessConsumptions(double Now);
	int32 CountClaimable(uint8 Type, FName ID) const;
	int32 ClaimFromWorld(uint8 Type, FName ID, int32 Amount);
	void GatherPickups(uint8 Type, FName ID, TArray<AActor*>& Out) const;
	void SpawnDroppedPickup(const FPUBGItemRecord& Item, const FVector& Location);
	void PublishLoadout();
	void Notice(const FString& Message, const FString& DedupKey);
	FName FindVerifiedOfType(uint8 Type) const;
	int32 GetAmmoBudget(FName AmmoID) const;
	static FName MakeKey(uint8 Type, FName ID);

	// ---- Owning client state
	FPUBGInventorySnapshot LastSent;
	bool bHasSent = false;
	float SnapshotTimer = 0.f;
	TArray<TWeakObjectPtr<AActor>> PendingDrops;
	FDelegateHandle SpawnHandle;
	TWeakObjectPtr<UObject> LastHoldGun;
	int32 LastHoldAmmo = -1;

	// ---- Server ledger
	TMap<FName, FPUBGItemRecord> Verified; // non-weapon, non-ammo items, key = type|id
	FName SlotWeapon[3];                   // [1], [2]
	PUBGLogic::FMagazineTracker Mags[3];
	uint8 HeldSlot = 0;
	TMap<FName, int32> AmmoTotal;          // bullets owned (backpack + magazines), by ammo item ID
	FPUBGInventorySnapshot LastReported;
	bool bHasReport = false;
	TMap<FName, double> RejectedUntil;
	TMap<FString, double> NoticeCooldown;

	struct FConsumption
	{
		uint8 Type;
		FName ID;
	};
	TArray<FConsumption> ConsumeQueue;
	double NextConsumeAllowed = 0.0;
};
