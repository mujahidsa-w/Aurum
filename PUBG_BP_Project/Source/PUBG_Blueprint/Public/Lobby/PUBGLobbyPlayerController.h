#pragma once

#include "CoreMinimal.h"
#include "GameFramework/PlayerController.h"
#include "PUBGLobbyPlayerController.generated.h"

/** Player controller of the pre-match lobby: shows the lobby UI and sends lobby commands to the server. */
UCLASS()
class PUBG_BLUEPRINT_API APUBGLobbyPlayerController : public APlayerController
{
	GENERATED_BODY()

public:
	virtual void BeginPlay() override;

	UFUNCTION(Server, Reliable, WithValidation, BlueprintCallable, Category = "PUBG|Lobby") void ServerSetReady(bool bReady);
	UFUNCTION(Server, Reliable, WithValidation, BlueprintCallable, Category = "PUBG|Lobby") void ServerSetCharacter(int32 Index);
	UFUNCTION(Server, Reliable, WithValidation, BlueprintCallable, Category = "PUBG|Lobby") void ServerRequestStart();
	UFUNCTION(Server, Reliable, WithValidation, BlueprintCallable, Category = "PUBG|Lobby") void ServerKick(APlayerState* Target);

	UFUNCTION(Client, Reliable) void ClientLobbyMessage(const FString& Message);

	/** Last server message (e.g. why the match cannot start yet). */
	FString LastMessage;
	double LastMessageTime = -100.0;
};
