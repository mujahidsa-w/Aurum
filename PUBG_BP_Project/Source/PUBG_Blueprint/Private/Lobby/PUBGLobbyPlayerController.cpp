#include "Lobby/PUBGLobbyPlayerController.h"

#include "Lobby/PUBGLobbyGameMode.h"
#include "UI/PUBGUISubsystem.h"
#include "Engine/World.h"
#include "GameFramework/PlayerState.h"

void APUBGLobbyPlayerController::BeginPlay()
{
	Super::BeginPlay();
	if (IsLocalController())
	{
		if (UPUBGUISubsystem* UI = UPUBGUISubsystem::Get(this))
		{
			UI->ShowLobby(this);
		}
	}
}

bool APUBGLobbyPlayerController::ServerSetReady_Validate(bool bReady) { return true; }
void APUBGLobbyPlayerController::ServerSetReady_Implementation(bool bReady)
{
	if (APUBGLobbyGameMode* GM = GetWorld()->GetAuthGameMode<APUBGLobbyGameMode>())
	{
		GM->SetPlayerReady(this, bReady);
	}
}

bool APUBGLobbyPlayerController::ServerSetCharacter_Validate(int32 Index) { return Index >= 0 && Index < 256; }
void APUBGLobbyPlayerController::ServerSetCharacter_Implementation(int32 Index)
{
	if (APUBGLobbyGameMode* GM = GetWorld()->GetAuthGameMode<APUBGLobbyGameMode>())
	{
		GM->SetPlayerCharacter(this, Index);
	}
}

bool APUBGLobbyPlayerController::ServerRequestStart_Validate() { return true; }
void APUBGLobbyPlayerController::ServerRequestStart_Implementation()
{
	if (APUBGLobbyGameMode* GM = GetWorld()->GetAuthGameMode<APUBGLobbyGameMode>())
	{
		GM->RequestStart(this);
	}
}

bool APUBGLobbyPlayerController::ServerKick_Validate(APlayerState* Target) { return true; }
void APUBGLobbyPlayerController::ServerKick_Implementation(APlayerState* Target)
{
	if (APUBGLobbyGameMode* GM = GetWorld()->GetAuthGameMode<APUBGLobbyGameMode>())
	{
		GM->KickPlayer(this, Target);
	}
}

void APUBGLobbyPlayerController::ClientLobbyMessage_Implementation(const FString& Message)
{
	LastMessage = Message;
	LastMessageTime = FPlatformTime::Seconds();
}
