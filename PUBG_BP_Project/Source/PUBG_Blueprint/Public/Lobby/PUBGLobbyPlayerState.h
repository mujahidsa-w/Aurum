#pragma once

#include "CoreMinimal.h"
#include "GameFramework/PlayerState.h"
#include "PUBGLobbyPlayerState.generated.h"

class UPUBGPlayerProfileComponent;

UCLASS()
class PUBG_BLUEPRINT_API APUBGLobbyPlayerState : public APlayerState
{
	GENERATED_BODY()

public:
	APUBGLobbyPlayerState();

	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "PUBG|Lobby")
	UPUBGPlayerProfileComponent* Profile;
};
