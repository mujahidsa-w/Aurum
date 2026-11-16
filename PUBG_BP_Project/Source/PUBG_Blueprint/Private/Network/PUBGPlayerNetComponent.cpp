#include "Network/PUBGPlayerNetComponent.h"

#include "PUBG_Blueprint.h"
#include "Core/PUBGBlueprintBridge.h"
#include "Core/PUBGItemData.h"
#include "Core/PUBGSettings.h"
#include "Network/PUBGCombatComponent.h"
#include "Network/PUBGHealthComponent.h"
#include "Network/PUBGLoadoutVisualComponent.h"
#include "Network/PUBGPickupReplicationComponent.h"

#include "Engine/World.h"
#include "EngineUtils.h"
#include "GameFramework/Pawn.h"
#include "GameFramework/PlayerController.h"
#include "GameFramework/PlayerState.h"
#include "Kismet/GameplayStatics.h"
#include "Misc/Guid.h"

namespace
{
	constexpr int32 MaxSnapshotItems = 96;
	constexpr int32 MaxItemAmount = 9999;
	constexpr float SnapshotInterval = 0.2f;
	constexpr float DropDetectRadius = 800.f;

	void AddRecord(TMap<FName, FPUBGItemRecord>& Map, uint8 Type, FName ID, int32 Amount)
	{
		if (ID.IsNone() || Amount <= 0)
		{
			return;
		}
		const FName Key(*FString::Printf(TEXT("%d|%s"), Type, *ID.ToString()));
		FPUBGItemRecord& Rec = Map.FindOrAdd(Key);
		Rec.ItemType = Type;
		Rec.ID = ID;
		Rec.Amount = FMath::Min(Rec.Amount + Amount, MaxItemAmount);
	}

	bool ReadItem(const UObject* Item, const FPUBGBlueprintNames& Names, FPUBGItemRecord& Out)
	{
		if (!Item)
		{
			return false;
		}
		Out = FPUBGItemRecord();
		if (!PUBGBridge::GetName(Item, Names.ItemID, Out.ID) || Out.ID.IsNone())
		{
			return false;
		}
		PUBGBridge::GetByte(Item, Names.ItemType, Out.ItemType);
		Out.Amount = 1;
		int32 Amount = 1;
		if (PUBGBridge::GetInt(Item, Names.Amount, Amount))
		{
			Out.Amount = FMath::Clamp(Amount, 1, MaxItemAmount);
		}
		return true;
	}
}

UPUBGPlayerNetComponent::UPUBGPlayerNetComponent()
{
	SetIsReplicatedByDefault(true);
	PrimaryComponentTick.bCanEverTick = true;
	PrimaryComponentTick.TickGroup = TG_PostUpdateWork; // after the Blueprint fired / changed its inventory this frame
}

UPUBGPlayerNetComponent* UPUBGPlayerNetComponent::Find(const AController* Controller)
{
	return Controller ? Controller->FindComponentByClass<UPUBGPlayerNetComponent>() : nullptr;
}

APlayerController* UPUBGPlayerNetComponent::GetPC() const
{
	return Cast<APlayerController>(GetOwner());
}

APawn* UPUBGPlayerNetComponent::GetPawn() const
{
	const APlayerController* PC = GetPC();
	return PC ? PC->GetPawn() : nullptr;
}

bool UPUBGPlayerNetComponent::IsOwningClient() const
{
	const APlayerController* PC = GetPC();
	return PC && PC->IsLocalController();
}

bool UPUBGPlayerNetComponent::IsTrustedLocal() const
{
	// The listen-server host runs its Blueprint inventory on the server itself.
	const APlayerController* PC = GetPC();
	return PC && PC->IsLocalController() && PC->HasAuthority();
}

void UPUBGPlayerNetComponent::BeginPlay()
{
	Super::BeginPlay();
	if (IsOwningClient() && !IsTrustedLocal())
	{
		// Pickups placed in the map exist locally on every client; the server replaced
		// them with replicated copies (UPUBGNetBootstrapSubsystem::ReplaceLevelPickup).
		const TSubclassOf<AActor> PickupClass = UPUBGSettings::Get()->GetPickupBaseClass();
		if (PickupClass)
		{
			TArray<AActor*> LevelCopies;
			for (TActorIterator<AActor> It(GetWorld(), PickupClass); It; ++It)
			{
				if (!It->GetIsReplicated() && It->GetLocalRole() == ROLE_Authority && It->HasAnyFlags(RF_WasLoaded))
				{
					LevelCopies.Add(*It);
				}
			}
			for (AActor* Copy : LevelCopies)
			{
				Copy->Destroy();
			}
		}
		SpawnHandle = GetWorld()->AddOnActorSpawnedHandler(FOnActorSpawned::FDelegate::CreateUObject(this, &UPUBGPlayerNetComponent::HandleActorSpawned));
	}
}

void UPUBGPlayerNetComponent::EndPlay(const EEndPlayReason::Type EndPlayReason)
{
	if (SpawnHandle.IsValid() && GetWorld())
	{
		GetWorld()->RemoveOnActorSpawnedHandler(SpawnHandle);
	}
	Super::EndPlay(EndPlayReason);
}

void UPUBGPlayerNetComponent::TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction)
{
	Super::TickComponent(DeltaTime, TickType, ThisTickFunction);

	if (GetOwner()->HasAuthority())
	{
		ProcessConsumptions(GetWorld()->GetTimeSeconds());
	}
	if (!IsOwningClient())
	{
		return;
	}

	// Order matters: shots first, then drops, then the snapshot.
	DetectShots();
	ProcessPendingDrops();
	if (PendingDrops.Num() > 0)
	{
		return; // wait until the dropped pickup has its variables, so the drop is reported before the snapshot
	}

	SnapshotTimer -= DeltaTime;
	if (SnapshotTimer > 0.f)
	{
		return;
	}
	SnapshotTimer = SnapshotInterval;

	FPUBGInventorySnapshot Snapshot;
	if (!BuildSnapshot(Snapshot))
	{
		return;
	}
	if (IsTrustedLocal())
	{
		if (!bHasReport || Snapshot != LastReported)
		{
			ApplyTrustedSnapshot(Snapshot);
		}
		return;
	}
	if (!bHasSent || Snapshot != LastSent)
	{
		LastSent = Snapshot;
		bHasSent = true;
		ServerSubmitSnapshot(Snapshot);
	}
}

// ---------------------------------------------------------------------------
// Owning client
// ---------------------------------------------------------------------------

bool UPUBGPlayerNetComponent::BuildSnapshot(FPUBGInventorySnapshot& Out) const
{
	const APlayerController* PC = GetPC();
	const APlayerState* PS = PC ? PC->PlayerState : nullptr;
	if (!PS)
	{
		return false;
	}
	const FPUBGBlueprintNames& Names = UPUBGSettings::Get()->BlueprintNames;
	if (!PUBGBridge::HasProperty(PS, Names.ItemsInBackpack))
	{
		return false; // not the Blueprint MyPlayerState (e.g. lobby)
	}

	TMap<FName, FPUBGItemRecord> Items;
	auto AddItemObject = [&Items, &Names](const UObject* Item)
	{
		FPUBGItemRecord Rec;
		if (ReadItem(Item, Names, Rec))
		{
			AddRecord(Items, Rec.ItemType, Rec.ID, Rec.Amount);
		}
	};

	TArray<UObject*> Objects;
	for (const FName ArrayName : { Names.ItemsInBackpack, Names.Equipments, Names.Fashions })
	{
		if (PUBGBridge::GetObjectArray(PS, ArrayName, Objects))
		{
			for (const UObject* Item : Objects)
			{
				AddItemObject(Item);
			}
		}
	}

	UObject* Weapon1 = PUBGBridge::GetObject(PS, Names.Weapon1);
	UObject* Weapon2 = PUBGBridge::GetObject(PS, Names.Weapon2);
	UObject* HoldGun = PUBGBridge::GetObject(PS, Names.HoldGun);
	static const FName AccessorySlots[] = { TEXT("AccMagObj"), TEXT("AccMuzzleObj"), TEXT("AccSightObj"), TEXT("AccForegrip"), TEXT("AccButtstockObj") };
	auto ReadWeapon = [&](UObject* Weapon, FName& OutID, int32& OutClip)
	{
		OutID = NAME_None;
		OutClip = 0;
		if (!Weapon)
		{
			return;
		}
		PUBGBridge::GetName(Weapon, Names.ItemID, OutID);
		PUBGBridge::GetInt(Weapon, Names.WeaponClipAmmo, OutClip);
		OutClip = FMath::Clamp(OutClip, 0, MaxItemAmount);
		// Accessories attached to a weapon still belong to the player.
		for (const FName& Slot : AccessorySlots)
		{
			if (PUBGBridge::HasProperty(Weapon, Slot))
			{
				AddItemObject(PUBGBridge::GetObject(Weapon, Slot));
			}
		}
	};
	ReadWeapon(Weapon1, Out.Weapon1ID, Out.Weapon1Clip);
	ReadWeapon(Weapon2, Out.Weapon2ID, Out.Weapon2Clip);
	Out.HeldSlot = (HoldGun && HoldGun == Weapon1) ? 1 : ((HoldGun && HoldGun == Weapon2) ? 2 : 0);
	Out.ShootMode = 0;
	if (HoldGun)
	{
		PUBGBridge::GetByte(HoldGun, Names.WeaponShootMode, Out.ShootMode);
	}

	Items.GenerateValueArray(Out.Items);
	Out.Items.Sort([](const FPUBGItemRecord& A, const FPUBGItemRecord& B)
	{
		return A.ItemType != B.ItemType ? A.ItemType < B.ItemType : A.ID.Compare(B.ID) < 0;
	});
	if (Out.Items.Num() > MaxSnapshotItems)
	{
		Out.Items.SetNum(MaxSnapshotItems);
	}
	return true;
}

void UPUBGPlayerNetComponent::DetectShots()
{
	const APlayerController* PC = GetPC();
	const APlayerState* PS = PC ? PC->PlayerState : nullptr;
	const FPUBGBlueprintNames& Names = UPUBGSettings::Get()->BlueprintNames;
	UObject* HoldGun = PS ? PUBGBridge::GetObject(PS, Names.HoldGun) : nullptr;
	int32 Ammo = -1;
	const bool bHasAmmo = HoldGun && PUBGBridge::GetInt(HoldGun, Names.WeaponClipAmmo, Ammo);

	if (bHasAmmo && LastHoldGun.Get() == HoldGun && LastHoldAmmo > Ammo)
	{
		const UPUBGCombatComponent* Combat = UPUBGCombatComponent::Find(GetPawn());
		const UPUBGHealthComponent* Health = UPUBGHealthComponent::Find(GetPawn());
		const int32 Shots = FMath::Min(LastHoldAmmo - Ammo, 5); // the Blueprint fires at most a few rounds per frame
		for (int32 i = 0; Combat && !(Health && Health->IsDead()) && i < Shots; ++i)
		{
			FPUBGShot Shot;
			if (Combat->BuildLocalShot(Shot))
			{
				if (GetOwner()->HasAuthority())
				{
					ServerShot_Implementation(Shot); // listen-server host
				}
				else
				{
					ServerShot(Shot);
				}
			}
		}
	}
	LastHoldGun = HoldGun;
	LastHoldAmmo = bHasAmmo ? Ammo : -1;
}

void UPUBGPlayerNetComponent::HandleActorSpawned(AActor* Actor)
{
	// Only locally spawned (non-replicated) pickups: those are Blueprint drops on this client.
	const TSubclassOf<AActor> PickupClass = UPUBGSettings::Get()->GetPickupBaseClass();
	if (!Actor || !PickupClass || !Actor->IsA(PickupClass) || Actor->GetLocalRole() != ROLE_Authority)
	{
		return;
	}
	PendingDrops.Add(Actor);
}

void UPUBGPlayerNetComponent::ProcessPendingDrops()
{
	if (PendingDrops.Num() == 0)
	{
		return;
	}
	const APawn* Pawn = GetPawn();
	const FPUBGBlueprintNames& Names = UPUBGSettings::Get()->BlueprintNames;
	TArray<TWeakObjectPtr<AActor>> StillPending;
	for (const TWeakObjectPtr<AActor>& Weak : PendingDrops)
	{
		AActor* Pickup = Weak.Get();
		if (!Pickup || Pickup->IsPendingKill())
		{
			continue;
		}
		if (!Pickup->HasActorBegunPlay())
		{
			StillPending.Add(Weak); // deferred spawn not finished yet
			continue;
		}
		FPUBGItemRecord Item;
		if (Pawn && ReadItem(Pickup, Names, Item) && FVector::Dist(Pickup->GetActorLocation(), Pawn->GetActorLocation()) <= DropDetectRadius)
		{
			ServerReportDrop(Item, Pickup->GetActorLocation());
			// The server spawns the real, replicated pickup; remove the local-only copy.
			Pickup->Destroy();
		}
	}
	PendingDrops = MoveTemp(StillPending);
}

void UPUBGPlayerNetComponent::ClientRejectItem_Implementation(const FPUBGItemRecord& Item, const FString& Reason)
{
	LastNotice = Reason;
	LastNoticeTime = FPlatformTime::Seconds();

	// Remove the unverified copy from the Blueprint backpack so the UI matches the server.
	const APlayerController* PC = GetPC();
	APlayerState* PS = PC ? PC->PlayerState : nullptr;
	if (!PS || Item.ItemType == (uint8)EPUBGItemType::Weapon || Item.ItemType == (uint8)EPUBGItemType::Ammo)
	{
		return;
	}
	const FPUBGBlueprintNames& Names = UPUBGSettings::Get()->BlueprintNames;
	TArray<UObject*> Backpack;
	if (PUBGBridge::GetObjectArray(PS, Names.ItemsInBackpack, Backpack))
	{
		for (UObject* Obj : Backpack)
		{
			FPUBGItemRecord Rec;
			if (ReadItem(Obj, Names, Rec) && Rec.ID == Item.ID && Rec.ItemType == Item.ItemType)
			{
				PUBGBridge::CallWithObject(PS, Names.RemoveItem, Obj);
				if (AActor* ItemActor = Cast<AActor>(Obj))
				{
					ItemActor->Destroy();
				}
				break;
			}
		}
	}
}

void UPUBGPlayerNetComponent::ClientNotice_Implementation(const FString& Message)
{
	LastNotice = Message;
	LastNoticeTime = FPlatformTime::Seconds();
}

// ---------------------------------------------------------------------------
// Server: RPC entry points
// ---------------------------------------------------------------------------

bool UPUBGPlayerNetComponent::ServerShot_Validate(const FPUBGShot& Shot)
{
	return !Shot.Origin.ContainsNaN() && !Shot.HitLocation.ContainsNaN() && !Shot.Direction.ContainsNaN();
}

void UPUBGPlayerNetComponent::ServerShot_Implementation(const FPUBGShot& Shot)
{
	if (UPUBGCombatComponent* Combat = UPUBGCombatComponent::Find(GetPawn()))
	{
		Combat->ServerProcessShot(Shot, this);
	}
}

bool UPUBGPlayerNetComponent::ServerSubmitSnapshot_Validate(const FPUBGInventorySnapshot& Snapshot)
{
	return Snapshot.Items.Num() <= MaxSnapshotItems && Snapshot.HeldSlot <= 2;
}

void UPUBGPlayerNetComponent::ServerSubmitSnapshot_Implementation(const FPUBGInventorySnapshot& Snapshot)
{
	ApplySnapshot(Snapshot);
}

bool UPUBGPlayerNetComponent::ServerReportDrop_Validate(const FPUBGItemRecord& Item, FVector_NetQuantize Location)
{
	return Item.Amount > 0 && Item.Amount <= MaxItemAmount && !Location.ContainsNaN();
}

void UPUBGPlayerNetComponent::ServerReportDrop_Implementation(const FPUBGItemRecord& Item, FVector_NetQuantize Location)
{
	APawn* Pawn = GetPawn();
	if (!Pawn || IsTrustedLocal())
	{
		return;
	}
	bool bOwned = false;
	FPUBGItemRecord ToSpawn = Item;
	if (Item.ItemType == (uint8)EPUBGItemType::Weapon)
	{
		bOwned = (SlotWeapon[1] == Item.ID || SlotWeapon[2] == Item.ID);
		ToSpawn.Amount = 1;
	}
	else if (Item.ItemType == (uint8)EPUBGItemType::Ammo)
	{
		int32& Total = AmmoTotal.FindOrAdd(Item.ID);
		ToSpawn.Amount = FMath::Min(Item.Amount, Total);
		bOwned = ToSpawn.Amount > 0;
		Total -= ToSpawn.Amount;
	}
	else if (FPUBGItemRecord* Rec = Verified.Find(MakeKey(Item.ItemType, Item.ID)))
	{
		ToSpawn.Amount = FMath::Min(Item.Amount, Rec->Amount);
		bOwned = ToSpawn.Amount > 0;
		Rec->Amount -= ToSpawn.Amount;
	}

	if (!bOwned)
	{
		Notice(TEXT("That item was not verified by the server."), TEXT("drop"));
		return;
	}
	// Keep the drop next to the player.
	FVector DropLocation = Location;
	const FVector PawnLocation = Pawn->GetActorLocation();
	if (FVector::Dist(DropLocation, PawnLocation) > 300.f)
	{
		DropLocation = PawnLocation + (DropLocation - PawnLocation).GetClampedToMaxSize(300.f);
	}
	SpawnDroppedPickup(ToSpawn, DropLocation);
}

// ---------------------------------------------------------------------------
// Server: ledger
// ---------------------------------------------------------------------------

FName UPUBGPlayerNetComponent::MakeKey(uint8 Type, FName ID)
{
	return FName(*FString::Printf(TEXT("%d|%s"), Type, *ID.ToString()));
}

void UPUBGPlayerNetComponent::ApplyTrustedSnapshot(const FPUBGInventorySnapshot& Snapshot)
{
	// Host: consumables still need their server effect; everything else is taken as reported.
	TMap<FName, FPUBGItemRecord> Reported;
	for (const FPUBGItemRecord& Rec : Snapshot.Items)
	{
		if (Rec.ItemType != (uint8)EPUBGItemType::Ammo)
		{
			Reported.Add(MakeKey(Rec.ItemType, Rec.ID), Rec);
		}
	}
	for (const TPair<FName, FPUBGItemRecord>& Old : Verified)
	{
		const FPUBGItemRecord* New = Reported.Find(Old.Key);
		const int32 Removed = Old.Value.Amount - (New ? New->Amount : 0);
		if (Removed > 0)
		{
			QueueConsumption(Old.Value.ItemType, Old.Value.ID, Removed);
		}
	}
	Verified = MoveTemp(Reported);
	SlotWeapon[1] = Snapshot.Weapon1ID;
	SlotWeapon[2] = Snapshot.Weapon2ID;
	HeldSlot = Snapshot.HeldSlot;
	LastReported = Snapshot;
	bHasReport = true;
	PublishLoadout();
}

void UPUBGPlayerNetComponent::ApplySnapshot(const FPUBGInventorySnapshot& Snapshot)
{
	const double Now = GetWorld()->GetTimeSeconds();
	ReconcileWeapons(Snapshot, Now);
	ReconcileAmmo(Snapshot);
	ReconcileItems(Snapshot);
	LastReported = Snapshot;
	bHasReport = true;
	PublishLoadout();
}

void UPUBGPlayerNetComponent::ReconcileWeapons(const FPUBGInventorySnapshot& Snapshot, double Now)
{
	const FName Reported[3] = { NAME_None, Snapshot.Weapon1ID, Snapshot.Weapon2ID };
	const int32 ReportedClip[3] = { 0, Snapshot.Weapon1Clip, Snapshot.Weapon2Clip };
	const int32 PreviousClip[3] = { 0, bHasReport ? LastReported.Weapon1Clip : 0, bHasReport ? LastReported.Weapon2Clip : 0 };
	const FName PreviousID[3] = { NAME_None, bHasReport ? LastReported.Weapon1ID : NAME_None, bHasReport ? LastReported.Weapon2ID : NAME_None };

	FName FinalSlots[3] = { NAME_None, NAME_None, NAME_None };
	PUBGLogic::FMagazineTracker FinalMags[3];
	bool bOldUsed[3] = { true, SlotWeapon[1].IsNone(), SlotWeapon[2].IsNone() };

	for (int32 Slot = 1; Slot <= 2; ++Slot)
	{
		const FName ID = Reported[Slot];
		if (ID.IsNone())
		{
			continue;
		}
		// Same verified weapon, possibly moved to the other slot.
		int32 Match = -1;
		if (!bOldUsed[Slot] && SlotWeapon[Slot] == ID)
		{
			Match = Slot;
		}
		else if (!bOldUsed[3 - Slot] && SlotWeapon[3 - Slot] == ID)
		{
			Match = 3 - Slot;
		}
		if (Match > 0)
		{
			bOldUsed[Match] = true;
			FinalSlots[Slot] = ID;
			FinalMags[Slot] = Mags[Match];
			// Extended magazines (ST_Item_WeaponAcc.ClipCapacity) raise the clip above the
			// table value: follow the largest clip reported, bounded to twice the base size.
			const int32 BaseClip = FMath::Max(1, PUBGItemData::GetWeaponStats(ID).ClipSize);
			FinalMags[Slot].ClipSize = FMath::Clamp(FMath::Max(FinalMags[Slot].ClipSize, ReportedClip[Slot]), BaseClip, BaseClip * 2);
			// A higher clip count for the same weapon means the Blueprint reloaded it.
			int32 Before = PreviousClip[Match];
			if (PreviousID[Match] == ID && ReportedClip[Slot] > Before)
			{
				FinalMags[Slot].AcceptClientReload(Now);
			}
			continue;
		}

		// New weapon: it must come from a pickup lying next to the player.
		const FName Key = MakeKey((uint8)EPUBGItemType::Weapon, ID);
		const double* Until = RejectedUntil.Find(Key);
		const bool bOnCooldown = Until && *Until > Now;
		if (!bOnCooldown && ClaimFromWorld((uint8)EPUBGItemType::Weapon, ID, 1) == 1)
		{
			const FPUBGWeaponStats Stats = PUBGItemData::GetWeaponStats(ID);
			FinalSlots[Slot] = ID;
			FinalMags[Slot].ClipSize = Stats.ClipSize;
			FinalMags[Slot].ReloadDuration = Stats.ReloadTime;
			FinalMags[Slot].InitFromLoadedClip(ReportedClip[Slot]);
			// Bullets already loaded in a picked-up weapon count as owned ammo.
			const int32 Loaded = FMath::Clamp(ReportedClip[Slot], 0, FMath::Max(Stats.ClipSize, 0));
			if (!Stats.AmmoID.IsNone() && Loaded > 0)
			{
				AmmoTotal.FindOrAdd(Stats.AmmoID) += Loaded;
			}
			RejectedUntil.Remove(Key);
		}
		else if (!bOnCooldown)
		{
			RejectedUntil.Add(Key, Now + 10.0);
			FPUBGItemRecord Rec;
			Rec.ItemType = (uint8)EPUBGItemType::Weapon;
			Rec.ID = ID;
			Rec.Amount = 1;
			ClientRejectItem(Rec, TEXT("Weapon not verified: it was already taken by another player."));
		}
	}

	for (int32 Slot = 1; Slot <= 2; ++Slot)
	{
		SlotWeapon[Slot] = FinalSlots[Slot];
		Mags[Slot] = FinalMags[Slot];
	}
	const uint8 ReportedHeld = Snapshot.HeldSlot;
	HeldSlot = (ReportedHeld >= 1 && ReportedHeld <= 2 && !SlotWeapon[ReportedHeld].IsNone() && SlotWeapon[ReportedHeld] == Reported[ReportedHeld]) ? ReportedHeld : 0;
}

void UPUBGPlayerNetComponent::ReconcileAmmo(const FPUBGInventorySnapshot& Snapshot)
{
	// Reported total per ammo type = backpack ammo items + bullets loaded in verified weapons.
	TMap<FName, int32> Reported;
	for (const FPUBGItemRecord& Rec : Snapshot.Items)
	{
		if (Rec.ItemType == (uint8)EPUBGItemType::Ammo)
		{
			Reported.FindOrAdd(Rec.ID) += Rec.Amount;
		}
	}
	const int32 Clips[3] = { 0, Snapshot.Weapon1Clip, Snapshot.Weapon2Clip };
	for (int32 Slot = 1; Slot <= 2; ++Slot)
	{
		if (!SlotWeapon[Slot].IsNone())
		{
			const FName AmmoID = PUBGItemData::GetWeaponStats(SlotWeapon[Slot]).AmmoID;
			if (!AmmoID.IsNone())
			{
				Reported.FindOrAdd(AmmoID) += Clips[Slot];
			}
		}
	}

	TSet<FName> Keys;
	for (const TPair<FName, int32>& P : Reported) { Keys.Add(P.Key); }
	for (const TPair<FName, int32>& P : AmmoTotal) { Keys.Add(P.Key); }

	for (const FName& AmmoID : Keys)
	{
		const int32 Rep = Reported.FindRef(AmmoID);
		int32& Server = AmmoTotal.FindOrAdd(AmmoID);
		if (Rep > Server)
		{
			const int32 Need = Rep - Server;
			const PUBGLogic::FReconcileResult R = PUBGLogic::ReconcileItemCount(Server, Rep, CountClaimable((uint8)EPUBGItemType::Ammo, AmmoID));
			const int32 Claimed = ClaimFromWorld((uint8)EPUBGItemType::Ammo, AmmoID, R.Claim);
			Server += Claimed;
			if (Need - Claimed > 0)
			{
				Notice(TEXT("Some ammo was not verified by the server."), TEXT("ammo"));
			}
		}
		else
		{
			// Fewer bullets than the server thinks (fired, or dropped): never grows from a report.
			Server = Rep;
		}
	}
}

void UPUBGPlayerNetComponent::ReconcileItems(const FPUBGInventorySnapshot& Snapshot)
{
	const double Now = GetWorld()->GetTimeSeconds();
	TMap<FName, FPUBGItemRecord> Reported;
	for (const FPUBGItemRecord& Rec : Snapshot.Items)
	{
		if (Rec.ItemType != (uint8)EPUBGItemType::Ammo && Rec.ItemType != (uint8)EPUBGItemType::Weapon)
		{
			AddRecord(Reported, Rec.ItemType, Rec.ID, Rec.Amount);
		}
	}
	TSet<FName> Keys;
	for (const TPair<FName, FPUBGItemRecord>& P : Reported) { Keys.Add(P.Key); }
	for (const TPair<FName, FPUBGItemRecord>& P : Verified) { Keys.Add(P.Key); }

	for (const FName& Key : Keys)
	{
		const FPUBGItemRecord* Rep = Reported.Find(Key);
		FPUBGItemRecord& Ver = Verified.FindOrAdd(Key);
		if (Rep)
		{
			Ver.ItemType = Rep->ItemType;
			Ver.ID = Rep->ID;
		}
		const int32 RepAmount = Rep ? Rep->Amount : 0;

		if (RepAmount > Ver.Amount)
		{
			const double* Until = RejectedUntil.Find(Key);
			if (Until && *Until > Now)
			{
				continue;
			}
			const PUBGLogic::FReconcileResult R = PUBGLogic::ReconcileItemCount(Ver.Amount, RepAmount, CountClaimable(Ver.ItemType, Ver.ID));
			Ver.Amount += ClaimFromWorld(Ver.ItemType, Ver.ID, R.Claim);
			if (Ver.ItemType == (uint8)EPUBGItemType::Fashion)
			{
				// Outfits are cosmetic and the Blueprint may grant default clothes that were
				// never on the ground: remove a matching ground copy if there is one, never reject.
				Ver.Amount = RepAmount;
				continue;
			}
			if (R.Reject > 0)
			{
				RejectedUntil.Add(Key, Now + 10.0);
				FPUBGItemRecord Rejected = Ver;
				Rejected.Amount = R.Reject;
				ClientRejectItem(Rejected, TEXT("Item not verified: it was already taken by another player."));
			}
		}
		else if (RepAmount < Ver.Amount)
		{
			// Dropped items were already removed by ServerReportDrop, so this is a use.
			QueueConsumption(Ver.ItemType, Ver.ID, Ver.Amount - RepAmount);
			Ver.Amount = RepAmount;
		}
	}
	for (auto It = Verified.CreateIterator(); It; ++It)
	{
		if (It->Value.Amount <= 0)
		{
			It.RemoveCurrent();
		}
	}
}

void UPUBGPlayerNetComponent::QueueConsumption(uint8 Type, FName ID, int32 Count)
{
	if (Type != (uint8)EPUBGItemType::Health && Type != (uint8)EPUBGItemType::Boost)
	{
		return; // accessories moved onto a weapon, equipment swapped, ...
	}
	for (int32 i = 0; i < FMath::Min(Count, 10); ++i)
	{
		ConsumeQueue.Add({ Type, ID });
	}
}

void UPUBGPlayerNetComponent::ProcessConsumptions(double Now)
{
	if (ConsumeQueue.Num() == 0 || Now < NextConsumeAllowed)
	{
		return;
	}
	const FConsumption Item = ConsumeQueue[0];
	ConsumeQueue.RemoveAt(0);
	UPUBGHealthComponent* Health = UPUBGHealthComponent::Find(GetPawn());
	if (!Health)
	{
		return;
	}
	float UseTime = 0.f;
	if (Item.Type == (uint8)EPUBGItemType::Health)
	{
		float Value = 0.f, Limit = 100.f;
		if (PUBGItemData::GetHealthItem(Item.ID, Value, Limit, UseTime))
		{
			Health->ServerHeal(Value, Limit);
		}
	}
	else
	{
		float Boost = 0.f;
		if (PUBGItemData::GetBoostItem(Item.ID, Boost, UseTime))
		{
			Health->ServerAddEnergy(Boost);
		}
	}
	// The Blueprint enforces the use time locally; the server enforces it too.
	NextConsumeAllowed = Now + FMath::Max(0.5f, UseTime * 0.8f);
}

void UPUBGPlayerNetComponent::GatherPickups(uint8 Type, FName ID, TArray<AActor*>& Out) const
{
	Out.Reset();
	const APawn* Pawn = GetPawn();
	const UPUBGSettings* S = UPUBGSettings::Get();
	const TSubclassOf<AActor> PickupClass = S->GetPickupBaseClass();
	if (!Pawn || !PickupClass)
	{
		return;
	}
	const FVector Center = Pawn->GetActorLocation();
	const float RadiusSq = FMath::Square(S->PickupClaimRadius);
	TArray<TPair<float, AActor*>> Candidates;
	for (TActorIterator<AActor> It(GetWorld(), PickupClass); It; ++It)
	{
		AActor* Pickup = *It;
		if (!Pickup || Pickup->IsPendingKill() || !Pickup->GetIsReplicated())
		{
			continue;
		}
		const float DistSq = FVector::DistSquared(Center, Pickup->GetActorLocation());
		if (DistSq > RadiusSq)
		{
			continue;
		}
		uint8 PickupType = 255;
		FName PickupID;
		if (!PUBGBridge::GetByte(Pickup, S->BlueprintNames.ItemType, PickupType) || !PUBGBridge::GetName(Pickup, S->BlueprintNames.ItemID, PickupID))
		{
			continue;
		}
		// Helmet / Vest / Backpack pickups are one Blueprint class; compare the exact type too.
		if (PickupType == Type && PickupID == ID)
		{
			Candidates.Add(TPair<float, AActor*>(DistSq, Pickup));
		}
	}
	Candidates.Sort([](const TPair<float, AActor*>& A, const TPair<float, AActor*>& B) { return A.Key < B.Key; });
	for (const TPair<float, AActor*>& C : Candidates)
	{
		Out.Add(C.Value);
	}
}

int32 UPUBGPlayerNetComponent::CountClaimable(uint8 Type, FName ID) const
{
	TArray<AActor*> Pickups;
	GatherPickups(Type, ID, Pickups);
	int32 Total = 0;
	for (const AActor* Pickup : Pickups)
	{
		int32 Amount = 1;
		PUBGBridge::GetInt(Pickup, UPUBGSettings::Get()->BlueprintNames.Amount, Amount);
		Total += FMath::Max(1, Amount);
	}
	return Total;
}

int32 UPUBGPlayerNetComponent::ClaimFromWorld(uint8 Type, FName ID, int32 Amount)
{
	if (Amount <= 0)
	{
		return 0;
	}
	const FPUBGBlueprintNames& Names = UPUBGSettings::Get()->BlueprintNames;
	TArray<AActor*> Pickups;
	GatherPickups(Type, ID, Pickups);
	int32 Claimed = 0;
	for (AActor* Pickup : Pickups)
	{
		int32 Available = 1;
		PUBGBridge::GetInt(Pickup, Names.Amount, Available);
		Available = FMath::Max(1, Available);
		const int32 Take = FMath::Min(Available, Amount - Claimed);
		Claimed += Take;
		if (Take >= Available)
		{
			Pickup->Destroy(); // removed for every player
		}
		else
		{
			PUBGBridge::SetInt(Pickup, Names.Amount, Available - Take);
			if (UPUBGPickupReplicationComponent* Rep = Pickup->FindComponentByClass<UPUBGPickupReplicationComponent>())
			{
				Rep->ServerCaptureFromActor();
			}
		}
		if (Claimed >= Amount)
		{
			break;
		}
	}
	return Claimed;
}

void UPUBGPlayerNetComponent::SpawnDroppedPickup(const FPUBGItemRecord& Item, const FVector& Location)
{
	const UPUBGSettings* S = UPUBGSettings::Get();
	const TSubclassOf<AActor> PickupClass = S->GetPickupClassForType(Item.ItemType);
	UWorld* World = GetWorld();
	if (!PickupClass || !World)
	{
		UE_LOG(LogPUBG, Warning, TEXT("No pickup class configured for item type %d."), Item.ItemType);
		return;
	}
	// Put it on the ground below the requested point.
	FVector SpawnLocation = Location;
	FHitResult Ground;
	FCollisionQueryParams Params(SCENE_QUERY_STAT(PUBGDropTrace), false, GetPawn());
	if (World->LineTraceSingleByChannel(Ground, Location + FVector(0, 0, 100), Location - FVector(0, 0, 500), ECC_Visibility, Params))
	{
		SpawnLocation = Ground.ImpactPoint + FVector(0, 0, 5);
	}
	const FTransform Transform(FRotator(0.f, FMath::FRandRange(0.f, 360.f), 0.f), SpawnLocation);
	AActor* Pickup = World->SpawnActorDeferred<AActor>(PickupClass, Transform, nullptr, nullptr, ESpawnActorCollisionHandlingMethod::AlwaysSpawn);
	if (!Pickup)
	{
		return;
	}
	PUBGBridge::SetByte(Pickup, S->BlueprintNames.ItemType, Item.ItemType);
	PUBGBridge::SetName(Pickup, S->BlueprintNames.ItemID, Item.ID);
	PUBGBridge::SetInt(Pickup, S->BlueprintNames.Amount, Item.Amount);
	PUBGBridge::SetString(Pickup, S->BlueprintNames.SN, FGuid::NewGuid().ToString(EGuidFormats::Digits));
	Pickup->SetReplicates(true);
	UGameplayStatics::FinishSpawningActor(Pickup, Transform);
}

void UPUBGPlayerNetComponent::PublishLoadout()
{
	UPUBGLoadoutVisualComponent* Loadout = UPUBGLoadoutVisualComponent::Find(GetPawn());
	if (!Loadout)
	{
		return;
	}
	FPUBGVisualLoadout L;
	L.Weapon1ID = SlotWeapon[1];
	L.Weapon2ID = SlotWeapon[2];
	L.HeldSlot = HeldSlot;
	L.HelmetID = FindVerifiedOfType((uint8)EPUBGItemType::Helmet);
	L.VestID = FindVerifiedOfType((uint8)EPUBGItemType::Vest);
	L.BackpackID = FindVerifiedOfType((uint8)EPUBGItemType::Backpack);
	for (const TPair<FName, FPUBGItemRecord>& P : Verified)
	{
		if (P.Value.ItemType == (uint8)EPUBGItemType::Fashion && P.Value.Amount > 0 && L.FashionIDs.Num() < 6)
		{
			L.FashionIDs.Add(P.Value.ID);
		}
	}
	Loadout->ServerSetLoadout(L);
}

FName UPUBGPlayerNetComponent::FindVerifiedOfType(uint8 Type) const
{
	for (const TPair<FName, FPUBGItemRecord>& P : Verified)
	{
		if (P.Value.ItemType == Type && P.Value.Amount > 0)
		{
			return P.Value.ID;
		}
	}
	return NAME_None;
}

void UPUBGPlayerNetComponent::Notice(const FString& Message, const FString& DedupKey)
{
	const double Now = GetWorld()->GetTimeSeconds();
	double& Next = NoticeCooldown.FindOrAdd(DedupKey);
	if (Now >= Next)
	{
		Next = Now + 10.0;
		ClientNotice(Message);
	}
}

// ---------------------------------------------------------------------------
// Server queries
// ---------------------------------------------------------------------------

bool UPUBGPlayerNetComponent::GetHeldWeapon(FName& OutWeaponID, int32& OutSlot) const
{
	if (IsTrustedLocal())
	{
		OutSlot = LastReported.HeldSlot;
		OutWeaponID = OutSlot == 1 ? LastReported.Weapon1ID : (OutSlot == 2 ? LastReported.Weapon2ID : NAME_None);
		return !OutWeaponID.IsNone();
	}
	OutSlot = HeldSlot;
	OutWeaponID = (HeldSlot >= 1 && HeldSlot <= 2) ? SlotWeapon[HeldSlot] : NAME_None;
	return !OutWeaponID.IsNone();
}

int32 UPUBGPlayerNetComponent::GetAmmoBudget(FName AmmoID) const
{
	if (const int32* Found = AmmoTotal.Find(AmmoID))
	{
		return *Found;
	}
	// Ammo ids could not be matched to the weapon's UseAmmoID: fall back to all owned ammo.
	int32 Sum = 0;
	for (const TPair<FName, int32>& P : AmmoTotal)
	{
		Sum += FMath::Max(0, P.Value);
	}
	return Sum;
}

bool UPUBGPlayerNetComponent::ServerTryConsumeShot(double Now)
{
	if (IsTrustedLocal())
	{
		return true;
	}
	FName WeaponID;
	int32 Slot = 0;
	if (!GetHeldWeapon(WeaponID, Slot))
	{
		return false;
	}
	const FName AmmoID = PUBGItemData::GetWeaponStats(WeaponID).AmmoID;
	int32 Budget = GetAmmoBudget(AmmoID);
	if (!Mags[Slot].TryFire(Now, Budget))
	{
		return false;
	}
	if (int32* Total = AmmoTotal.Find(AmmoID))
	{
		*Total = FMath::Max(0, *Total - 1);
	}
	else
	{
		// Fallback pool: take the bullet from any ammo type.
		for (TPair<FName, int32>& P : AmmoTotal)
		{
			if (P.Value > 0)
			{
				--P.Value;
				break;
			}
		}
	}
	return true;
}

float UPUBGPlayerNetComponent::GetArmorReduction(bool bHead) const
{
	const UPUBGSettings* S = UPUBGSettings::Get();
	const FName ID = FindVerifiedOfType(bHead ? (uint8)EPUBGItemType::Helmet : (uint8)EPUBGItemType::Vest);
	if (ID.IsNone())
	{
		return 0.f;
	}
	if (const float* Custom = S->ArmorReductionById.Find(ID))
	{
		return *Custom;
	}
	return bHead ? S->DefaultHelmetReduction : S->DefaultVestReduction;
}
