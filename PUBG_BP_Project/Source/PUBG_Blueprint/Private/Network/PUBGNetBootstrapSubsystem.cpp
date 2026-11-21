#include "Network/PUBGNetBootstrapSubsystem.h"

#include "PUBG_Blueprint.h"
#include "Core/PUBGSettings.h"
#include "Lobby/PUBGFrontEndGameMode.h"
#include "Lobby/PUBGLobbyGameMode.h"
#include "Network/PUBGCombatComponent.h"
#include "Network/PUBGHealthComponent.h"
#include "Network/PUBGLoadoutVisualComponent.h"
#include "Network/PUBGMatchStateComponent.h"
#include "Network/PUBGPickupReplicationComponent.h"
#include "Network/PUBGPlayerNetComponent.h"
#include "Network/PUBGPlayerProfileComponent.h"
#include "Network/PUBGStateMirrorComponent.h"
#include "Sessions/PUBGSessionSubsystem.h"

#include "Engine/World.h"
#include "EngineUtils.h"
#include "GameFramework/Character.h"
#include "GameFramework/GameModeBase.h"
#include "GameFramework/GameStateBase.h"
#include "GameFramework/PlayerController.h"
#include "GameFramework/PlayerState.h"
#include "TimerManager.h"
#include "Core/PUBGBlueprintBridge.h"
#include "Kismet/GameplayStatics.h"

namespace
{
	template <typename T>
	T* EnsureComponent(AActor* Actor, const TCHAR* Name)
	{
		if (T* Existing = Actor->FindComponentByClass<T>())
		{
			return Existing;
		}
		T* Component = NewObject<T>(Actor, T::StaticClass(), FName(Name));
		Component->SetIsReplicated(true);
		Component->RegisterComponent();
		Actor->AddInstanceComponent(Component);
		return Component;
	}

	/** Seconds after the battle map starts during which (re)connections are still accepted. */
	constexpr float JoinGraceSeconds = 60.f;
}

bool UPUBGNetBootstrapSubsystem::ShouldCreateSubsystem(UObject* Outer) const
{
	const UWorld* World = Cast<UWorld>(Outer);
	return World && (World->WorldType == EWorldType::Game || World->WorldType == EWorldType::PIE);
}

void UPUBGNetBootstrapSubsystem::Initialize(FSubsystemCollectionBase& Collection)
{
	Super::Initialize(Collection);
	if (UWorld* World = GetWorld())
	{
		SpawnHandle = World->AddOnActorSpawnedHandler(FOnActorSpawned::FDelegate::CreateUObject(this, &UPUBGNetBootstrapSubsystem::HandleActorSpawned));
	}
	PreLoginHandle = FGameModeEvents::GameModePreLoginEvent.AddUObject(this, &UPUBGNetBootstrapSubsystem::HandlePreLogin);
}

void UPUBGNetBootstrapSubsystem::Deinitialize()
{
	if (UWorld* World = GetWorld())
	{
		World->RemoveOnActorSpawnedHandler(SpawnHandle);
	}
	FGameModeEvents::GameModePreLoginEvent.Remove(PreLoginHandle);
	Super::Deinitialize();
}

bool UPUBGNetBootstrapSubsystem::IsNetworkedServer() const
{
	const UWorld* World = GetWorld();
	const ENetMode Mode = World ? World->GetNetMode() : NM_Standalone;
	return Mode == NM_ListenServer || Mode == NM_DedicatedServer;
}

bool UPUBGNetBootstrapSubsystem::IsMenuOrLobbyWorld() const
{
	const AGameModeBase* GameMode = GetWorld() ? GetWorld()->GetAuthGameMode() : nullptr;
	return GameMode && (GameMode->IsA<APUBGLobbyGameMode>() || GameMode->IsA<APUBGFrontEndGameMode>());
}

void UPUBGNetBootstrapSubsystem::HandlePreLogin(AGameModeBase* GameMode, const FUniqueNetIdRepl& NewPlayer, FString& ErrorMessage)
{
	if (!GameMode || GameMode->GetWorld() != GetWorld() || !ErrorMessage.IsEmpty() || IsMenuOrLobbyWorld())
	{
		return;
	}
	// A battle-royale match cannot be joined once it is under way (players coming
	// back from a non-seamless travel are still accepted during the grace period).
	const UPUBGMatchStateComponent* Match = UPUBGMatchStateComponent::Get(GetWorld());
	if (Match && Match->GetPhase() != EPUBGMatchPhase::WaitingForPlayers && GetWorld()->GetTimeSeconds() > JoinGraceSeconds)
	{
		ErrorMessage = TEXT("The match is already in progress.");
	}
}

void UPUBGNetBootstrapSubsystem::HandleActorSpawned(AActor* Actor)
{
	if (!Actor || !IsNetworkedServer() || IsMenuOrLobbyWorld())
	{
		return;
	}
	if (!bScanned)
	{
		ScanExistingActors(); // GameState etc. were spawned before the world started listening
	}
	// Defer one tick: deferred spawns (Blueprint SpawnActor) set their variables after this callback.
	TWeakObjectPtr<AActor> WeakActor(Actor);
	TWeakObjectPtr<UPUBGNetBootstrapSubsystem> WeakThis(this);
	GetWorld()->GetTimerManager().SetTimerForNextTick(FTimerDelegate::CreateLambda([WeakThis, WeakActor]()
	{
		if (WeakThis.IsValid() && WeakActor.IsValid() && !WeakActor->IsPendingKill())
		{
			WeakThis->SetupActor(WeakActor.Get(), false);
		}
	}));
}

void UPUBGNetBootstrapSubsystem::ScanExistingActors()
{
	bScanned = true;
	UE_LOG(LogPUBG, Log, TEXT("Multiplayer layer active on %s (%s)."), *GetWorld()->GetMapName(),
		GetWorld()->GetNetMode() == NM_DedicatedServer ? TEXT("dedicated") : TEXT("listen"));
	TArray<AActor*> Existing;
	for (TActorIterator<AActor> It(GetWorld()); It; ++It)
	{
		if (!It->IsPendingKill())
		{
			Existing.Add(*It);
		}
	}
	for (AActor* Actor : Existing)
	{
		SetupActor(Actor, true);
	}
}

void UPUBGNetBootstrapSubsystem::SetupActor(AActor* Actor, bool bFromScan)
{
	const UPUBGSettings* S = UPUBGSettings::Get();

	if (AGameStateBase* GameState = Cast<AGameStateBase>(Actor))
	{
		EnsureComponent<UPUBGMatchStateComponent>(GameState, TEXT("PUBGMatchState"));
		return;
	}
	if (APlayerState* PS = Cast<APlayerState>(Actor))
	{
		UPUBGPlayerProfileComponent* Profile = EnsureComponent<UPUBGPlayerProfileComponent>(PS, TEXT("PUBGProfile"));
		int32 Character = 0;
		UPUBGSessionSubsystem* Sessions = UPUBGSessionSubsystem::Get(GetWorld());
		if (Sessions && Sessions->GetTravelProfile(Profile->GetTravelKey(), Character))
		{
			Profile->SetCharacterIndex(Character);
		}
		return;
	}
	if (APlayerController* PC = Cast<APlayerController>(Actor))
	{
		EnsureComponent<UPUBGPlayerNetComponent>(PC, TEXT("PUBGPlayerNet"));
		return;
	}
	if (ACharacter* Character = Cast<ACharacter>(Actor))
	{
		EnsureComponent<UPUBGHealthComponent>(Character, TEXT("PUBGHealth"));
		EnsureComponent<UPUBGCombatComponent>(Character, TEXT("PUBGCombat"));
		EnsureComponent<UPUBGStateMirrorComponent>(Character, TEXT("PUBGStateMirror"));
		EnsureComponent<UPUBGLoadoutVisualComponent>(Character, TEXT("PUBGLoadout"));
		FinishPawnSetup(Character, 0);
		return;
	}
	const TSubclassOf<AActor> PickupClass = S->GetPickupBaseClass();
	if (PickupClass && Actor->IsA(PickupClass))
	{
		if (Actor->HasAnyFlags(RF_WasLoaded) && !Actor->GetIsReplicated())
		{
			// Placed in the map: every client loaded its own copy, so replicating this
			// one would duplicate it. Replace it by a replicated copy instead (clients
			// remove their local level copies, see UPUBGPlayerNetComponent::BeginPlay).
			ReplaceLevelPickup(Actor);
			return;
		}
		if (bFromScan)
		{
			return; // spawned at runtime: handled by its own spawn event once fully constructed
		}
		if (!Actor->GetIsReplicated())
		{
			Actor->SetReplicates(true);
		}
		Actor->SetReplicateMovement(false);
		Actor->NetUpdateFrequency = 2.f; // pickups rarely change
		Actor->NetPriority = 0.5f;
		EnsureComponent<UPUBGPickupReplicationComponent>(Actor, TEXT("PUBGPickupRep"));
	}
}

void UPUBGNetBootstrapSubsystem::ReplaceLevelPickup(AActor* Pickup)
{
	const FPUBGBlueprintNames& Names = UPUBGSettings::Get()->BlueprintNames;
	uint8 ItemType = 255;
	FName ID;
	int32 Amount = 1;
	FString SN;
	PUBGBridge::GetByte(Pickup, Names.ItemType, ItemType);
	PUBGBridge::GetName(Pickup, Names.ItemID, ID);
	PUBGBridge::GetInt(Pickup, Names.Amount, Amount);
	PUBGBridge::GetString(Pickup, Names.SN, SN);
	const FTransform Transform = Pickup->GetActorTransform();
	UClass* PickupClass = Pickup->GetClass();
	Pickup->Destroy();

	AActor* Copy = GetWorld()->SpawnActorDeferred<AActor>(PickupClass, Transform, nullptr, nullptr, ESpawnActorCollisionHandlingMethod::AlwaysSpawn);
	if (!Copy)
	{
		return;
	}
	PUBGBridge::SetByte(Copy, Names.ItemType, ItemType);
	PUBGBridge::SetName(Copy, Names.ItemID, ID);
	PUBGBridge::SetInt(Copy, Names.Amount, Amount);
	PUBGBridge::SetString(Copy, Names.SN, SN);
	Copy->SetReplicates(true);
	UGameplayStatics::FinishSpawningActor(Copy, Transform); // its spawn event adds the replication component
}

void UPUBGNetBootstrapSubsystem::FinishPawnSetup(TWeakObjectPtr<APawn> WeakPawn, int32 Attempt)
{
	APawn* Pawn = WeakPawn.Get();
	if (!Pawn || Pawn->IsPendingKill())
	{
		return;
	}
	APlayerController* PC = Cast<APlayerController>(Pawn->GetController());
	if (!PC)
	{
		// Possession happens right after spawning; retry for a few seconds.
		if (Attempt < 20)
		{
			FTimerHandle Handle;
			TWeakObjectPtr<UPUBGNetBootstrapSubsystem> WeakThis(this);
			GetWorld()->GetTimerManager().SetTimer(Handle, FTimerDelegate::CreateLambda([WeakThis, WeakPawn, Attempt]()
			{
				if (WeakThis.IsValid())
				{
					WeakThis->FinishPawnSetup(WeakPawn, Attempt + 1);
				}
			}), 0.25f, false);
		}
		return;
	}
	if (UPUBGLoadoutVisualComponent* Loadout = UPUBGLoadoutVisualComponent::Find(Pawn))
	{
		if (const UPUBGPlayerProfileComponent* Profile = UPUBGPlayerProfileComponent::Find(PC->PlayerState))
		{
			Loadout->ServerSetCharacterPreset(Profile->CharacterIndex);
		}
	}
	SpreadSpawn(Pawn);
}

void UPUBGNetBootstrapSubsystem::SpreadSpawn(APawn* Pawn)
{
	// Several players often start on the same PlayerStart: move this one to a free spot nearby.
	const FVector Base = Pawn->GetActorLocation();
	bool bCrowded = false;
	for (FConstPlayerControllerIterator It = GetWorld()->GetPlayerControllerIterator(); It; ++It)
	{
		const APawn* Other = It->IsValid() ? (*It)->GetPawn() : nullptr;
		if (Other && Other != Pawn && FVector::Dist2D(Other->GetActorLocation(), Base) < 150.f)
		{
			bCrowded = true;
			break;
		}
	}
	if (!bCrowded)
	{
		return;
	}
	for (int32 Ring = 1; Ring <= 3; ++Ring)
	{
		for (int32 Step = 0; Step < 8; ++Step)
		{
			const float Angle = (Step / 8.f) * 2.f * PI + Ring;
			FVector Candidate = Base + FVector(FMath::Cos(Angle), FMath::Sin(Angle), 0.f) * (250.f * Ring);
			if (!GetWorld()->FindTeleportSpot(Pawn, Candidate, Pawn->GetActorRotation()))
			{
				continue;
			}
			bool bFree = true;
			for (FConstPlayerControllerIterator It = GetWorld()->GetPlayerControllerIterator(); It; ++It)
			{
				const APawn* Other = It->IsValid() ? (*It)->GetPawn() : nullptr;
				if (Other && Other != Pawn && FVector::Dist2D(Other->GetActorLocation(), Candidate) < 150.f)
				{
					bFree = false;
					break;
				}
			}
			if (bFree)
			{
				if (UPUBGStateMirrorComponent* Mirror = UPUBGStateMirrorComponent::Find(Pawn))
				{
					Mirror->ServerTeleport(Candidate);
				}
				else
				{
					Pawn->SetActorLocation(Candidate);
				}
				return;
			}
		}
	}
}
