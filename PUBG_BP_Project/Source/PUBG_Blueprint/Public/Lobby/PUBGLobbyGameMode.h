// Pre-match lobby (server side). Loaded with "?game=Lobby" on the lobby map, so
// no lobby .umap asset is required. Handles room password / ticket checks,
// host assignment, ready states, character choice and the start countdown.

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "Core/PUBGTypes.h"
#include "PUBGLobbyGameMode.generated.h"

class APUBGLobbyPlayerController;
class APUBGLobbyGameState;

UCLASS()
class PUBG_BLUEPRINT_API APUBGLobbyGameMode : public AGameModeBase
{
	GENERATED_BODY()

public:
	APUBGLobbyGameMode();

	virtual void InitGame(const FString& MapName, const FString& Options, FString& ErrorMessage) override;
	virtual void InitGameState() override;
	virtual void PreLogin(const FString& Options, const FString& Address, const FUniqueNetIdRepl& UniqueId, FString& ErrorMessage) override;
	virtual FString InitNewPlayer(APlayerController* NewPlayerController, const FUniqueNetIdRepl& UniqueId, const FString& Options, const FString& Portal = TEXT("")) override;
	virtual void PostLogin(APlayerController* NewPlayer) override;
	virtual void Logout(AController* Exiting) override;
	virtual void HandleSeamlessTravelPlayer(AController*& C) override;
	virtual void Tick(float DeltaSeconds) override;

	void SetPlayerReady(APlayerController* PC, bool bReady);
	void SetPlayerCharacter(APlayerController* PC, int32 Index);
	void RequestStart(APUBGLobbyPlayerController* Requester);
	void KickPlayer(APlayerController* Requester, APlayerState* Target);

	/** Returns false and a human readable reason when the match cannot start. */
	bool CanStart(FString& OutReason) const;

private:
	APUBGLobbyGameState* GetLobbyState() const;
	void UpdateHost();
	void RestoreTravelProfile(APlayerController* PC);
	void BeginCountdown();
	void CancelCountdown();
	void StartMatchTravel();
	bool IsDedicated() const;
	int32 CountPlayers(int32* OutReady = nullptr, bool bExcludeHost = false) const;

	FPUBGRoomSettings Room;
	bool bCountdownRunning = false;
	bool bTravelling = false;
};
