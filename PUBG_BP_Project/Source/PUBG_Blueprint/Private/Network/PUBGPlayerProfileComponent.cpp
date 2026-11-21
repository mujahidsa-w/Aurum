#include "Network/PUBGPlayerProfileComponent.h"

#include "Core/PUBGBlueprintBridge.h"
#include "Core/PUBGSettings.h"
#include "Lobby/PUBGLobbyGameState.h"
#include "GameFramework/PlayerController.h"
#include "GameFramework/PlayerState.h"
#include "Engine/World.h"
#include "Net/UnrealNetwork.h"

UPUBGPlayerProfileComponent::UPUBGPlayerProfileComponent()
{
	SetIsReplicatedByDefault(true);
	PrimaryComponentTick.bCanEverTick = true;
	PrimaryComponentTick.bStartWithTickEnabled = true;
}

UPUBGPlayerProfileComponent* UPUBGPlayerProfileComponent::Find(const APlayerState* PlayerState)
{
	return PlayerState ? PlayerState->FindComponentByClass<UPUBGPlayerProfileComponent>() : nullptr;
}

void UPUBGPlayerProfileComponent::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
	Super::GetLifetimeReplicatedProps(OutLifetimeProps);
	DOREPLIFETIME(UPUBGPlayerProfileComponent, CharacterIndex);
	DOREPLIFETIME(UPUBGPlayerProfileComponent, bReady);
	DOREPLIFETIME(UPUBGPlayerProfileComponent, bIsHost);
	DOREPLIFETIME(UPUBGPlayerProfileComponent, ConnectionState);
	DOREPLIFETIME(UPUBGPlayerProfileComponent, Kills);
	DOREPLIFETIME(UPUBGPlayerProfileComponent, bAlive);
	DOREPLIFETIME(UPUBGPlayerProfileComponent, Placement);
}

void UPUBGPlayerProfileComponent::TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction)
{
	Super::TickComponent(DeltaTime, TickType, ThisTickFunction);
	if (!GetOwner() || !GetOwner()->HasAuthority())
	{
		SetComponentTickEnabled(false);
		return;
	}
	ConnectionTimer -= DeltaTime;
	if (ConnectionTimer <= 0.f)
	{
		ConnectionTimer = 1.f;
		UpdateConnectionState();
	}
}

void UPUBGPlayerProfileComponent::UpdateConnectionState()
{
	const APlayerState* PS = Cast<APlayerState>(GetOwner());
	if (!PS)
	{
		return;
	}
	EPUBGConnectionState NewState;
	const APlayerController* PC = Cast<APlayerController>(PS->GetOwner());
	if (PS->IsInactive() || !PC)
	{
		NewState = EPUBGConnectionState::Disconnected;
	}
	else if (!PC->HasClientLoadedCurrentWorld())
	{
		NewState = EPUBGConnectionState::Loading;
	}
	else
	{
		const UWorld* World = GetWorld();
		const bool bInLobby = World && World->GetGameState() && World->GetGameState()->IsA<APUBGLobbyGameState>();
		NewState = bInLobby ? EPUBGConnectionState::InLobby : EPUBGConnectionState::InGame;
	}
	if (NewState != ConnectionState)
	{
		ConnectionState = NewState;
		OnRep_Profile();
	}
}

void UPUBGPlayerProfileComponent::SetCharacterIndex(int32 Index)
{
	const int32 Count = UPUBGSettings::Get()->CharacterPresets.Num();
	CharacterIndex = Count > 0 ? FMath::Clamp(Index, 0, Count - 1) : 0;
	OnRep_Profile();
}

void UPUBGPlayerProfileComponent::SetReady(bool bInReady)
{
	bReady = bInReady;
	OnRep_Profile();
}

void UPUBGPlayerProfileComponent::SetIsHost(bool bInHost)
{
	bIsHost = bInHost;
	OnRep_Profile();
}

void UPUBGPlayerProfileComponent::AddKill()
{
	++Kills;
	OnRep_Profile();
}

void UPUBGPlayerProfileComponent::MarkEliminated(int32 InPlacement)
{
	bAlive = InPlacement == 1;
	Placement = InPlacement;
	OnRep_Profile();
}

void UPUBGPlayerProfileComponent::ResetForMatch()
{
	Kills = 0;
	bAlive = true;
	Placement = 0;
	bReady = false;
	OnRep_Profile();
}

FString UPUBGPlayerProfileComponent::GetTravelKey() const
{
	const APlayerState* PS = Cast<APlayerState>(GetOwner());
	if (!PS)
	{
		return FString();
	}
	const FUniqueNetIdRepl& Id = PS->GetUniqueId();
	return Id.IsValid() ? Id.ToString() : PS->GetPlayerName();
}

FString UPUBGPlayerProfileComponent::GetConnectionStateText() const
{
	switch (ConnectionState)
	{
	case EPUBGConnectionState::Loading: return TEXT("Loading");
	case EPUBGConnectionState::InLobby: return TEXT("In lobby");
	case EPUBGConnectionState::InGame: return TEXT("In game");
	default: return TEXT("Disconnected");
	}
}

void UPUBGPlayerProfileComponent::OnRep_Profile()
{
	PushToBlueprint();
	OnProfileChanged.Broadcast();
}

void UPUBGPlayerProfileComponent::PushToBlueprint()
{
	// MyPlayerState.KilledAmount drives the original UI; harmless no-op on the lobby PlayerState.
	UObject* PS = GetOwner();
	const FName KilledAmount = UPUBGSettings::Get()->BlueprintNames.KilledAmount;
	if (PS && PUBGBridge::HasProperty(PS, KilledAmount))
	{
		PUBGBridge::SetInt(PS, KilledAmount, Kills);
	}
}
