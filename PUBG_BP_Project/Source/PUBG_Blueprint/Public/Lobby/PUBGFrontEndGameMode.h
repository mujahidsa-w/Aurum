// Main-menu game mode. Loaded with "?game=FrontEnd" on the menu map (see
// DefaultEngine.ini LocalMapOptions), so no extra .umap asset is needed.

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "GameFramework/PlayerController.h"
#include "PUBGFrontEndGameMode.generated.h"

UCLASS()
class PUBG_BLUEPRINT_API APUBGFrontEndPlayerController : public APlayerController
{
	GENERATED_BODY()

public:
	virtual void BeginPlay() override;
};

UCLASS()
class PUBG_BLUEPRINT_API APUBGFrontEndGameMode : public AGameModeBase
{
	GENERATED_BODY()

public:
	APUBGFrontEndGameMode();

	/** A dedicated server started without a map URL lands here: send it to the lobby. */
	virtual void BeginPlay() override;
};
