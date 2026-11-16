// Replicated per-player data shown in the lobby and the in-game scoreboard.
// Lives on the PlayerState: created as a default subobject on the lobby
// PlayerState, and attached at runtime to the Blueprint MyPlayerState by
// UPUBGNetBootstrapSubsystem during networked matches.

#pragma once

#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "Core/PUBGTypes.h"
#include "PUBGPlayerProfileComponent.generated.h"

class APlayerState;

UCLASS(ClassGroup = (PUBG), meta = (BlueprintSpawnableComponent))
class PUBG_BLUEPRINT_API UPUBGPlayerProfileComponent : public UActorComponent
{
	GENERATED_BODY()

public:
	UPUBGPlayerProfileComponent();

	UFUNCTION(BlueprintPure, Category = "PUBG|Profile", meta = (DisplayName = "Find PUBG Profile"))
	static UPUBGPlayerProfileComponent* Find(const APlayerState* PlayerState);

	virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;
	virtual void TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction) override;

	// -------- Server setters
	void SetCharacterIndex(int32 Index);
	void SetReady(bool bInReady);
	void SetIsHost(bool bInHost);
	void AddKill();
	void MarkEliminated(int32 InPlacement);
	void ResetForMatch();

	/** Key used to carry choices over server travel. */
	FString GetTravelKey() const;

	UFUNCTION(BlueprintPure, Category = "PUBG|Profile") FString GetConnectionStateText() const;

	UPROPERTY(ReplicatedUsing = OnRep_Profile, BlueprintReadOnly, Category = "PUBG|Profile") int32 CharacterIndex = 0;
	UPROPERTY(ReplicatedUsing = OnRep_Profile, BlueprintReadOnly, Category = "PUBG|Profile") bool bReady = false;
	UPROPERTY(ReplicatedUsing = OnRep_Profile, BlueprintReadOnly, Category = "PUBG|Profile") bool bIsHost = false;
	UPROPERTY(ReplicatedUsing = OnRep_Profile, BlueprintReadOnly, Category = "PUBG|Profile") EPUBGConnectionState ConnectionState = EPUBGConnectionState::Loading;
	UPROPERTY(ReplicatedUsing = OnRep_Profile, BlueprintReadOnly, Category = "PUBG|Profile") int32 Kills = 0;
	UPROPERTY(ReplicatedUsing = OnRep_Profile, BlueprintReadOnly, Category = "PUBG|Profile") bool bAlive = true;
	/** 1 = winner, 0 = still playing. */
	UPROPERTY(ReplicatedUsing = OnRep_Profile, BlueprintReadOnly, Category = "PUBG|Profile") int32 Placement = 0;

	DECLARE_MULTICAST_DELEGATE(FOnProfileChanged);
	FOnProfileChanged OnProfileChanged;

protected:
	UFUNCTION() void OnRep_Profile();

private:
	void UpdateConnectionState();
	void PushToBlueprint();
	float ConnectionTimer = 0.f;
};
