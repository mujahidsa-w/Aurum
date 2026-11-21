#include "Network/PUBGMatchStateComponent.h"

#include "PUBG_Blueprint.h"
#include "Core/PUBGSettings.h"
#include "Network/PUBGHealthComponent.h"
#include "Network/PUBGPlayerProfileComponent.h"
#include "Sessions/PUBGSessionSubsystem.h"

#include "Engine/Engine.h"
#include "Engine/World.h"
#include "GameFramework/Controller.h"
#include "GameFramework/GameModeBase.h"
#include "GameFramework/GameStateBase.h"
#include "GameFramework/Pawn.h"
#include "GameFramework/PlayerState.h"
#include "Net/UnrealNetwork.h"

UPUBGMatchStateComponent::UPUBGMatchStateComponent()
{
	SetIsReplicatedByDefault(true);
	PrimaryComponentTick.bCanEverTick = true;
	PrimaryComponentTick.TickInterval = 0.5f;
}

UPUBGMatchStateComponent* UPUBGMatchStateComponent::Get(const UObject* WorldContext)
{
	const UWorld* World = GEngine ? GEngine->GetWorldFromContextObject(WorldContext, EGetWorldErrorMode::ReturnNull) : nullptr;
	const AGameStateBase* GameState = World ? World->GetGameState() : nullptr;
	return GameState ? GameState->FindComponentByClass<UPUBGMatchStateComponent>() : nullptr;
}

void UPUBGMatchStateComponent::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
	Super::GetLifetimeReplicatedProps(OutLifetimeProps);
	DOREPLIFETIME(UPUBGMatchStateComponent, Phase);
	DOREPLIFETIME(UPUBGMatchStateComponent, AliveCount);
	DOREPLIFETIME(UPUBGMatchStateComponent, TotalPlayers);
	DOREPLIFETIME(UPUBGMatchStateComponent, WinnerName);
	DOREPLIFETIME(UPUBGMatchStateComponent, KillFeed);
	DOREPLIFETIME(UPUBGMatchStateComponent, ReturnToLobbyTime);
}

void UPUBGMatchStateComponent::BeginPlay()
{
	Super::BeginPlay();
	if (GetOwner()->HasAuthority())
	{
		LogoutHandle = FGameModeEvents::GameModeLogoutEvent.AddUObject(this, &UPUBGMatchStateComponent::HandleLogout);
		RecountPlayers();
	}
}

void UPUBGMatchStateComponent::EndPlay(const EEndPlayReason::Type EndPlayReason)
{
	FGameModeEvents::GameModeLogoutEvent.Remove(LogoutHandle);
	Super::EndPlay(EndPlayReason);
}

void UPUBGMatchStateComponent::HandleLogout(AGameModeBase* GameMode, AController* Exiting)
{
	if (!GameMode || GameMode->GetWorld() != GetWorld())
	{
		return;
	}
	// Leaving mid-match counts as an elimination without a killer.
	if (APawn* Pawn = Exiting ? Exiting->GetPawn() : nullptr)
	{
		if (UPUBGHealthComponent* Health = UPUBGHealthComponent::Find(Pawn))
		{
			Health->ServerKill(nullptr);
		}
	}
	RecountTimer = 0.f; // recount on next tick
}

float UPUBGMatchStateComponent::GetReturnToLobbyRemaining() const
{
	const AGameStateBase* GameState = Cast<AGameStateBase>(GetOwner());
	if (ReturnToLobbyTime < 0.f || !GameState)
	{
		return -1.f;
	}
	return FMath::Max(0.f, ReturnToLobbyTime - GameState->GetServerWorldTimeSeconds());
}

void UPUBGMatchStateComponent::TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction)
{
	Super::TickComponent(DeltaTime, TickType, ThisTickFunction);
	AGameStateBase* GameState = Cast<AGameStateBase>(GetOwner());
	if (!GameState || !GameState->HasAuthority())
	{
		return;
	}
	RecountTimer -= DeltaTime;
	if (RecountTimer <= 0.f)
	{
		RecountTimer = 1.f;
		RecountPlayers();
	}
	if (Phase == EPUBGMatchPhase::Finished && !bReturnTriggered && ReturnToLobbyTime >= 0.f &&
		GameState->GetServerWorldTimeSeconds() >= ReturnToLobbyTime)
	{
		bReturnTriggered = true;
		FGameModeEvents::GameModeLogoutEvent.Remove(LogoutHandle);
		if (UPUBGSessionSubsystem* Sessions = UPUBGSessionSubsystem::Get(this))
		{
			Sessions->ServerTravelToLobby();
		}
	}
}

void UPUBGMatchStateComponent::RecountPlayers()
{
	const AGameStateBase* GameState = Cast<AGameStateBase>(GetOwner());
	if (!GameState || Phase == EPUBGMatchPhase::Finished)
	{
		return;
	}
	int32 Total = 0, Alive = 0;
	APawn* LastAlive = nullptr;
	for (APlayerState* PS : GameState->PlayerArray)
	{
		if (!PS || PS->IsABot() || PS->IsOnlyASpectator())
		{
			continue;
		}
		++Total;
		// Server side: a PlayerState is owned by its controller.
		const AController* Controller = Cast<AController>(PS->GetOwner());
		APawn* Pawn = Controller ? Controller->GetPawn() : nullptr;
		const UPUBGHealthComponent* Health = UPUBGHealthComponent::Find(Pawn);
		if (Pawn && Health && !Health->IsDead() && !PS->IsInactive())
		{
			++Alive;
			LastAlive = Pawn;
		}
	}
	TotalPlayers = Total;
	AliveCount = Alive;

	if (Phase == EPUBGMatchPhase::WaitingForPlayers && Alive > 0)
	{
		Phase = EPUBGMatchPhase::InProgress;
		UE_LOG(LogPUBG, Log, TEXT("Match in progress with %d player(s)."), Total);
	}
	// A match needs two players to have a winner; alone you can practice indefinitely.
	if (Phase == EPUBGMatchPhase::InProgress && Total >= 2 && Alive <= 1)
	{
		FinishMatch(LastAlive);
	}
}

void UPUBGMatchStateComponent::ServerNotifyElimination(APawn* Victim, AController* Killer, FName WeaponID, bool bHeadshot)
{
	if (!GetOwner()->HasAuthority() || Phase == EPUBGMatchPhase::Finished)
	{
		return;
	}
	APlayerState* VictimPS = Victim ? Victim->GetPlayerState() : nullptr;
	APlayerState* KillerPS = Killer ? Killer->PlayerState : nullptr;

	FPUBGKillFeedEntry Entry;
	Entry.VictimName = VictimPS ? VictimPS->GetPlayerName() : TEXT("?");
	Entry.KillerName = (KillerPS && KillerPS != VictimPS) ? KillerPS->GetPlayerName() : FString();
	Entry.WeaponID = WeaponID;
	Entry.bHeadshot = bHeadshot;
	if (const AGameStateBase* GameState = Cast<AGameStateBase>(GetOwner()))
	{
		Entry.ServerTime = GameState->GetServerWorldTimeSeconds();
	}
	KillFeed.Add(Entry);
	while (KillFeed.Num() > 6)
	{
		KillFeed.RemoveAt(0);
	}

	if (UPUBGPlayerProfileComponent* KillerProfile = UPUBGPlayerProfileComponent::Find(KillerPS))
	{
		if (KillerPS != VictimPS)
		{
			KillerProfile->AddKill();
		}
	}
	// Placement = number of players alive before this elimination.
	const int32 PlacementValue = FMath::Max(1, AliveCount);
	if (UPUBGPlayerProfileComponent* VictimProfile = UPUBGPlayerProfileComponent::Find(VictimPS))
	{
		VictimProfile->MarkEliminated(PlacementValue == 1 ? 2 : PlacementValue);
	}
	RecountPlayers();
}

void UPUBGMatchStateComponent::FinishMatch(APawn* WinnerPawn)
{
	Phase = EPUBGMatchPhase::Finished;
	APlayerState* WinnerPS = WinnerPawn ? WinnerPawn->GetPlayerState() : nullptr;
	WinnerName = WinnerPS ? WinnerPS->GetPlayerName() : FString();
	if (UPUBGPlayerProfileComponent* Profile = UPUBGPlayerProfileComponent::Find(WinnerPS))
	{
		Profile->MarkEliminated(1);
	}
	if (const AGameStateBase* GameState = Cast<AGameStateBase>(GetOwner()))
	{
		ReturnToLobbyTime = GameState->GetServerWorldTimeSeconds() + UPUBGSettings::Get()->ReturnToLobbyDelay;
	}
	UE_LOG(LogPUBG, Log, TEXT("Match finished. Winner: %s"), WinnerName.IsEmpty() ? TEXT("none") : *WinnerName);
}
