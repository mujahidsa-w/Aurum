#include "Lobby/PUBGFrontEndGameMode.h"

#include "UI/PUBGUISubsystem.h"
#include "PUBG_Blueprint.h"
#include "Core/PUBGSettings.h"
#include "Engine/World.h"
#include "GameFramework/HUD.h"
#include "GameFramework/GameStateBase.h"
#include "GameFramework/PlayerState.h"
#include "GameFramework/SpectatorPawn.h"

APUBGFrontEndGameMode::APUBGFrontEndGameMode()
{
	PlayerControllerClass = APUBGFrontEndPlayerController::StaticClass();
	PlayerStateClass = APlayerState::StaticClass();
	GameStateClass = AGameStateBase::StaticClass();
	HUDClass = AHUD::StaticClass();
	SpectatorClass = ASpectatorPawn::StaticClass();
	DefaultPawnClass = nullptr;
	bStartPlayersAsSpectators = true;
}

void APUBGFrontEndGameMode::BeginPlay()
{
	Super::BeginPlay();
	if (GetNetMode() == NM_DedicatedServer)
	{
		const UPUBGSettings* S = UPUBGSettings::Get();
		const FString URL = S->LobbyMap + TEXT("?game=") + S->LobbyGameAlias;
		UE_LOG(LogPUBG, Warning, TEXT("Dedicated server started on the menu map; switching to the lobby (%s)."), *URL);
		GetWorld()->ServerTravel(URL, true);
	}
}

void APUBGFrontEndPlayerController::BeginPlay()
{
	Super::BeginPlay();
	if (IsLocalController())
	{
		if (UPUBGUISubsystem* UI = UPUBGUISubsystem::Get(this))
		{
			UI->ShowMainMenu(this);
		}
	}
}
