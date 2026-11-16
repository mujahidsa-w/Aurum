// Battle-royale match flow for networked games, attached at runtime to the
// existing GameState (MyGameState): alive count, kill feed, placements, winner
// and the automatic return to the lobby. Server-authoritative, replicated.

#pragma once

#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "Core/PUBGTypes.h"
#include "PUBGMatchStateComponent.generated.h"

class APawn;
class AController;

UCLASS(ClassGroup = (PUBG))
class PUBG_BLUEPRINT_API UPUBGMatchStateComponent : public UActorComponent
{
	GENERATED_BODY()

public:
	UPUBGMatchStateComponent();

	/** Component on the current world's GameState, or nullptr (lobby / standalone). */
	static UPUBGMatchStateComponent* Get(const UObject* WorldContext);

	virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;
	virtual void BeginPlay() override;
	virtual void EndPlay(const EEndPlayReason::Type EndPlayReason) override;
	virtual void TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction) override;

	void ServerNotifyElimination(APawn* Victim, AController* Killer, FName WeaponID, bool bHeadshot);

	UFUNCTION(BlueprintPure, Category = "PUBG|Match") EPUBGMatchPhase GetPhase() const { return Phase; }
	UFUNCTION(BlueprintPure, Category = "PUBG|Match") int32 GetAliveCount() const { return AliveCount; }
	UFUNCTION(BlueprintPure, Category = "PUBG|Match") int32 GetTotalPlayers() const { return TotalPlayers; }
	UFUNCTION(BlueprintPure, Category = "PUBG|Match") FString GetWinnerName() const { return WinnerName; }
	UFUNCTION(BlueprintPure, Category = "PUBG|Match") TArray<FPUBGKillFeedEntry> GetKillFeed() const { return KillFeed; }
	/** Seconds until everybody returns to the lobby (< 0 = not scheduled). */
	UFUNCTION(BlueprintPure, Category = "PUBG|Match") float GetReturnToLobbyRemaining() const;

protected:
	UPROPERTY(Replicated) EPUBGMatchPhase Phase = EPUBGMatchPhase::WaitingForPlayers;
	UPROPERTY(Replicated) int32 AliveCount = 0;
	UPROPERTY(Replicated) int32 TotalPlayers = 0;
	UPROPERTY(Replicated) FString WinnerName;
	UPROPERTY(Replicated) TArray<FPUBGKillFeedEntry> KillFeed;
	UPROPERTY(Replicated) float ReturnToLobbyTime = -1.f;

private:
	void RecountPlayers();
	void FinishMatch(APawn* WinnerPawn);
	void HandleLogout(class AGameModeBase* GameMode, AController* Exiting);

	FDelegateHandle LogoutHandle;
	float RecountTimer = 0.f;
	bool bReturnTriggered = false;
};
