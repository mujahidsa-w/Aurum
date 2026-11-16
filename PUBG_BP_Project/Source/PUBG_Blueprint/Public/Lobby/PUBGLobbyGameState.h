#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameStateBase.h"
#include "PUBGLobbyGameState.generated.h"

/** Replicated room information for the lobby screen. Players are in PlayerArray. */
UCLASS()
class PUBG_BLUEPRINT_API APUBGLobbyGameState : public AGameStateBase
{
	GENERATED_BODY()

public:
	virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;

	UPROPERTY(Replicated, BlueprintReadOnly, Category = "PUBG|Lobby") FString RoomName;
	UPROPERTY(Replicated, BlueprintReadOnly, Category = "PUBG|Lobby") bool bHasPassword = false;
	UPROPERTY(Replicated, BlueprintReadOnly, Category = "PUBG|Lobby") int32 MaxPlayers = 8;
	UPROPERTY(Replicated, BlueprintReadOnly, Category = "PUBG|Lobby") FString BattleMapName;
	UPROPERTY(Replicated, BlueprintReadOnly, Category = "PUBG|Lobby") bool bDedicatedServer = false;
	/** Room-service join code (online rooms). */
	UPROPERTY(Replicated, BlueprintReadOnly, Category = "PUBG|Lobby") FString JoinCode;
	/** Address other players can use with "Direct IP" (listen servers). */
	UPROPERTY(Replicated, BlueprintReadOnly, Category = "PUBG|Lobby") FString HostAddress;
	/** Server world time at which the match starts; < 0 when no countdown. */
	UPROPERTY(Replicated, BlueprintReadOnly, Category = "PUBG|Lobby") float CountdownEndTime = -1.f;
	UPROPERTY(Replicated, BlueprintReadOnly, Category = "PUBG|Lobby") bool bTravelling = false;

	UFUNCTION(BlueprintPure, Category = "PUBG|Lobby") float GetCountdownRemaining() const;
};
