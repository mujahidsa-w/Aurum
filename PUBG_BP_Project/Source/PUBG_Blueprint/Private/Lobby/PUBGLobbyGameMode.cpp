#include "Lobby/PUBGLobbyGameMode.h"

#include "PUBG_Blueprint.h"
#include "Core/PUBGSettings.h"
#include "Lobby/PUBGLobbyGameState.h"
#include "Lobby/PUBGLobbyPlayerController.h"
#include "Lobby/PUBGLobbyPlayerState.h"
#include "Network/PUBGPlayerProfileComponent.h"
#include "Sessions/PUBGSessionSubsystem.h"
#include "Sessions/PUBGRoomServiceSubsystem.h"

#include "Engine/World.h"
#include "GameFramework/GameSession.h"
#include "GameFramework/HUD.h"
#include "GameFramework/PlayerState.h"
#include "GameFramework/SpectatorPawn.h"
#include "Kismet/GameplayStatics.h"
#include "Misc/Paths.h"

APUBGLobbyGameMode::APUBGLobbyGameMode()
{
	PlayerControllerClass = APUBGLobbyPlayerController::StaticClass();
	PlayerStateClass = APUBGLobbyPlayerState::StaticClass();
	GameStateClass = APUBGLobbyGameState::StaticClass();
	HUDClass = AHUD::StaticClass();
	SpectatorClass = ASpectatorPawn::StaticClass();
	DefaultPawnClass = nullptr;
	bStartPlayersAsSpectators = true;
	bUseSeamlessTravel = true;
	PrimaryActorTick.bCanEverTick = true;
	PrimaryActorTick.TickInterval = 0.25f;
}

bool APUBGLobbyGameMode::IsDedicated() const
{
	return GetNetMode() == NM_DedicatedServer;
}

APUBGLobbyGameState* APUBGLobbyGameMode::GetLobbyState() const
{
	return GetGameState<APUBGLobbyGameState>();
}

void APUBGLobbyGameMode::InitGame(const FString& MapName, const FString& Options, FString& ErrorMessage)
{
	Super::InitGame(MapName, Options, ErrorMessage);
	Room = UPUBGSessionSubsystem::ParseRoomOptions(Options);
	if (UPUBGSessionSubsystem* Sessions = UPUBGSessionSubsystem::Get(this))
	{
		Sessions->SetActiveRoomSettings(Room);
		if (IsDedicated())
		{
			Sessions->RegisterDedicatedSession(Room);
		}
	}
	UE_LOG(LogPUBG, Log, TEXT("Lobby '%s' max=%d password=%s"), *Room.RoomName, Room.MaxPlayers, Room.Password.IsEmpty() ? TEXT("no") : TEXT("yes"));
}

void APUBGLobbyGameMode::InitGameState()
{
	Super::InitGameState();
	if (APUBGLobbyGameState* LS = GetLobbyState())
	{
		LS->RoomName = Room.RoomName;
		LS->bHasPassword = !Room.Password.IsEmpty();
		LS->MaxPlayers = Room.MaxPlayers;
		LS->BattleMapName = FPaths::GetBaseFilename(UPUBGSettings::Get()->GetBattleMap(Room.BattleMapIndex));
		LS->bDedicatedServer = IsDedicated();
		if (UPUBGRoomServiceSubsystem* RoomService = UPUBGRoomServiceSubsystem::Get(this))
		{
			LS->JoinCode = RoomService->GetServedRoomCode();
		}
	}
}

void APUBGLobbyGameMode::PreLogin(const FString& Options, const FString& Address, const FUniqueNetIdRepl& UniqueId, FString& ErrorMessage)
{
	Super::PreLogin(Options, Address, UniqueId, ErrorMessage);
	if (!ErrorMessage.IsEmpty())
	{
		return; // e.g. "Server full." from AGameSession
	}
	if (bTravelling)
	{
		ErrorMessage = TEXT("The match is starting.");
		return;
	}

	// Dedicated room-service servers validate a signed ticket instead of a password.
	UPUBGRoomServiceSubsystem* RoomService = UPUBGRoomServiceSubsystem::Get(this);
	if (RoomService && RoomService->IsServingRoom())
	{
		const FString Ticket = UPUBGSessionSubsystem::DecodeOption(UGameplayStatics::ParseOption(Options, TEXT("Ticket")));
		FString TicketError;
		if (!RoomService->VerifyJoinTicket(Ticket, TicketError))
		{
			ErrorMessage = TicketError;
		}
		return;
	}

	if (!Room.Password.IsEmpty())
	{
		const FString Given = UPUBGSessionSubsystem::DecodeOption(UGameplayStatics::ParseOption(Options, TEXT("Password")));
		if (Given != Room.Password)
		{
			ErrorMessage = TEXT("Wrong room password.");
		}
	}
}

FString APUBGLobbyGameMode::InitNewPlayer(APlayerController* NewPlayerController, const FUniqueNetIdRepl& UniqueId, const FString& Options, const FString& Portal)
{
	const FString Result = Super::InitNewPlayer(NewPlayerController, UniqueId, Options, Portal);
	if (NewPlayerController && NewPlayerController->PlayerState)
	{
		if (UPUBGPlayerProfileComponent* Profile = UPUBGPlayerProfileComponent::Find(NewPlayerController->PlayerState))
		{
			Profile->SetCharacterIndex(UGameplayStatics::GetIntOption(Options, TEXT("Character"), 0));
		}
	}
	return Result;
}

void APUBGLobbyGameMode::PostLogin(APlayerController* NewPlayer)
{
	Super::PostLogin(NewPlayer);
	RestoreTravelProfile(NewPlayer);
	UpdateHost();
	UE_LOG(LogPUBG, Log, TEXT("Lobby: %s joined (%d players)."), NewPlayer && NewPlayer->PlayerState ? *NewPlayer->PlayerState->GetPlayerName() : TEXT("?"), CountPlayers());
}

void APUBGLobbyGameMode::HandleSeamlessTravelPlayer(AController*& C)
{
	Super::HandleSeamlessTravelPlayer(C);
	if (APlayerController* PC = Cast<APlayerController>(C))
	{
		RestoreTravelProfile(PC);
	}
	UpdateHost();
}

void APUBGLobbyGameMode::RestoreTravelProfile(APlayerController* PC)
{
	UPUBGPlayerProfileComponent* Profile = PC ? UPUBGPlayerProfileComponent::Find(PC->PlayerState) : nullptr;
	UPUBGSessionSubsystem* Sessions = UPUBGSessionSubsystem::Get(this);
	if (!Profile || !Sessions)
	{
		return;
	}
	int32 Character = 0;
	if (Sessions->GetTravelProfile(Profile->GetTravelKey(), Character))
	{
		Profile->SetCharacterIndex(Character);
	}
	Profile->ResetForMatch();
}

void APUBGLobbyGameMode::Logout(AController* Exiting)
{
	Super::Logout(Exiting);
	UpdateHost();
	FString Reason;
	if (bCountdownRunning && !CanStart(Reason))
	{
		CancelCountdown();
	}
}

void APUBGLobbyGameMode::UpdateHost()
{
	APUBGLobbyGameState* LS = GetLobbyState();
	if (!LS)
	{
		return;
	}
	APlayerState* HostPS = nullptr;
	if (!IsDedicated())
	{
		// Listen server: the local player is the host.
		for (FConstPlayerControllerIterator It = GetWorld()->GetPlayerControllerIterator(); It; ++It)
		{
			if (It->IsValid() && (*It)->IsLocalController())
			{
				HostPS = (*It)->PlayerState;
				break;
			}
		}
		if (UPUBGSessionSubsystem* Sessions = UPUBGSessionSubsystem::Get(this))
		{
			LS->HostAddress = Sessions->GetLocalAddressHint();
		}
	}
	else
	{
		// Dedicated server: keep the current host, otherwise the longest-connected player.
		for (APlayerState* PS : LS->PlayerArray)
		{
			if (const UPUBGPlayerProfileComponent* Profile = UPUBGPlayerProfileComponent::Find(PS))
			{
				if (Profile->bIsHost && !PS->IsInactive())
				{
					HostPS = PS;
					break;
				}
			}
		}
		if (!HostPS)
		{
			for (APlayerState* PS : LS->PlayerArray)
			{
				if (PS && !PS->IsInactive() && UPUBGPlayerProfileComponent::Find(PS))
				{
					HostPS = PS;
					break;
				}
			}
		}
	}
	for (APlayerState* PS : LS->PlayerArray)
	{
		if (UPUBGPlayerProfileComponent* Profile = UPUBGPlayerProfileComponent::Find(PS))
		{
			const bool bHost = PS == HostPS;
			if (Profile->bIsHost != bHost)
			{
				Profile->SetIsHost(bHost);
			}
		}
	}
}

int32 APUBGLobbyGameMode::CountPlayers(int32* OutReady, bool bExcludeHost) const
{
	int32 Total = 0, Ready = 0;
	if (const APUBGLobbyGameState* LS = GetLobbyState())
	{
		for (const APlayerState* PS : LS->PlayerArray)
		{
			const UPUBGPlayerProfileComponent* Profile = UPUBGPlayerProfileComponent::Find(PS);
			if (!Profile || PS->IsInactive() || (bExcludeHost && Profile->bIsHost))
			{
				continue;
			}
			++Total;
			Ready += Profile->bReady ? 1 : 0;
		}
	}
	if (OutReady)
	{
		*OutReady = Ready;
	}
	return Total;
}

bool APUBGLobbyGameMode::CanStart(FString& OutReason) const
{
	const UPUBGSettings* S = UPUBGSettings::Get();
	const int32 MinPlayers = IsDedicated() ? S->MinPlayersToStartDedicated : S->MinPlayersToStart;
	const int32 Total = CountPlayers();
	if (Total < MinPlayers)
	{
		OutReason = FString::Printf(TEXT("Need at least %d player(s)."), MinPlayers);
		return false;
	}
	int32 Ready = 0;
	// On a listen server the host starts the match, so only the others must be ready.
	const int32 Others = CountPlayers(&Ready, !IsDedicated());
	if (Ready < Others)
	{
		OutReason = FString::Printf(TEXT("Waiting for players to be ready (%d/%d)."), Ready, Others);
		return false;
	}
	return true;
}

void APUBGLobbyGameMode::SetPlayerReady(APlayerController* PC, bool bReady)
{
	if (bTravelling)
	{
		return;
	}
	if (UPUBGPlayerProfileComponent* Profile = PC ? UPUBGPlayerProfileComponent::Find(PC->PlayerState) : nullptr)
	{
		Profile->SetReady(bReady);
	}
	FString Reason;
	if (bCountdownRunning && !CanStart(Reason))
	{
		CancelCountdown();
	}
}

void APUBGLobbyGameMode::SetPlayerCharacter(APlayerController* PC, int32 Index)
{
	if (UPUBGPlayerProfileComponent* Profile = PC ? UPUBGPlayerProfileComponent::Find(PC->PlayerState) : nullptr)
	{
		Profile->SetCharacterIndex(Index);
	}
}

void APUBGLobbyGameMode::RequestStart(APUBGLobbyPlayerController* Requester)
{
	if (!Requester || bTravelling)
	{
		return;
	}
	const UPUBGPlayerProfileComponent* Profile = UPUBGPlayerProfileComponent::Find(Requester->PlayerState);
	if (!Profile || !Profile->bIsHost)
	{
		Requester->ClientLobbyMessage(TEXT("Only the host can start the match."));
		return;
	}
	FString Reason;
	if (!CanStart(Reason))
	{
		Requester->ClientLobbyMessage(Reason);
		return;
	}
	BeginCountdown();
}

void APUBGLobbyGameMode::KickPlayer(APlayerController* Requester, APlayerState* Target)
{
	const UPUBGPlayerProfileComponent* Profile = Requester ? UPUBGPlayerProfileComponent::Find(Requester->PlayerState) : nullptr;
	if (!Profile || !Profile->bIsHost || !Target || Target == Requester->PlayerState || !GameSession)
	{
		return;
	}
	if (APlayerController* TargetPC = Cast<APlayerController>(Target->GetOwner()))
	{
		GameSession->KickPlayer(TargetPC, FText::FromString(TEXT("Removed from the room by the host.")));
	}
}

void APUBGLobbyGameMode::BeginCountdown()
{
	APUBGLobbyGameState* LS = GetLobbyState();
	if (!LS || bCountdownRunning)
	{
		return;
	}
	bCountdownRunning = true;
	LS->CountdownEndTime = LS->GetServerWorldTimeSeconds() + UPUBGSettings::Get()->LobbyCountdownSeconds;
}

void APUBGLobbyGameMode::CancelCountdown()
{
	bCountdownRunning = false;
	if (APUBGLobbyGameState* LS = GetLobbyState())
	{
		LS->CountdownEndTime = -1.f;
	}
}

void APUBGLobbyGameMode::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);
	APUBGLobbyGameState* LS = GetLobbyState();
	if (!LS || bTravelling)
	{
		return;
	}
	FString Reason;
	const bool bCanStart = CanStart(Reason);
	if (IsDedicated() && !bCountdownRunning && bCanStart)
	{
		BeginCountdown(); // dedicated servers start on their own once everybody is ready
	}
	if (bCountdownRunning)
	{
		if (!bCanStart)
		{
			CancelCountdown();
		}
		else if (LS->GetCountdownRemaining() <= 0.f)
		{
			StartMatchTravel();
		}
	}
}

void APUBGLobbyGameMode::StartMatchTravel()
{
	UPUBGSessionSubsystem* Sessions = UPUBGSessionSubsystem::Get(this);
	APUBGLobbyGameState* LS = GetLobbyState();
	if (!Sessions || !LS)
	{
		return;
	}
	for (APlayerState* PS : LS->PlayerArray)
	{
		if (const UPUBGPlayerProfileComponent* Profile = UPUBGPlayerProfileComponent::Find(PS))
		{
			Sessions->StoreTravelProfile(Profile->GetTravelKey(), Profile->CharacterIndex);
		}
	}
	bTravelling = true;
	bCountdownRunning = false;
	LS->bTravelling = true;
	LS->CountdownEndTime = -1.f;
	if (!Sessions->ServerTravelToBattle())
	{
		bTravelling = false;
		LS->bTravelling = false;
		UE_LOG(LogPUBG, Error, TEXT("Server travel to the battle map failed."));
	}
}
