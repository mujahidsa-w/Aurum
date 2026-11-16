// Makes other players SEE the correct pose and movement.
//
// MyAnimeBlueprint reads MyCharacter's own bools (isCrouching, isProne,
// isAiming, isHoldWeapon, isFreeFalling, ...). Those are local Blueprint
// variables, so this component copies them from the owning client to the server
// and to every other machine, together with yaw, velocity and walk speed.
//
// It also configures movement for the original control code: MyPlayerController
// moves the pawn with SetActorLocation, which the CharacterMovementComponent
// would otherwise correct back (rubber-banding). The server accepts the client
// position and bounds it with a speed check (PUBGLogic::FSpeedValidator).

#pragma once

#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "Core/PUBGTypes.h"
#include "Logic/PUBGNetLogic.h"
#include "PUBGStateMirrorComponent.generated.h"

class ACharacter;

UCLASS(ClassGroup = (PUBG))
class PUBG_BLUEPRINT_API UPUBGStateMirrorComponent : public UActorComponent
{
	GENERATED_BODY()

public:
	UPUBGStateMirrorComponent();

	static UPUBGStateMirrorComponent* Find(const AActor* Actor);

	virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;
	virtual void BeginPlay() override;
	virtual void TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction) override;

	/** Server: move the pawn and tell its owner (spawn spreading, anti-cheat). */
	void ServerTeleport(const FVector& Location);

	const FPUBGMirrorState& GetState() const { return State; }

protected:
	UFUNCTION(Server, Reliable, WithValidation) void ServerSetStateReliable(const FPUBGMirrorState& NewState, FVector_NetQuantize10 Velocity);
	UFUNCTION(Server, Unreliable, WithValidation) void ServerSetStateUnreliable(const FPUBGMirrorState& NewState, FVector_NetQuantize10 Velocity);
	UFUNCTION(Client, Reliable) void ClientCorrectLocation(FVector_NetQuantize Location);

	UPROPERTY(ReplicatedUsing = OnRep_State) FPUBGMirrorState State;
	UPROPERTY(Replicated) FVector_NetQuantize10 MirroredVelocity;

	UFUNCTION() void OnRep_State();

private:
	ACharacter* GetCharacter() const;
	bool CaptureLocal(FPUBGMirrorState& Out) const;
	void AcceptState(const FPUBGMirrorState& NewState, const FVector& Velocity);
	void ApplyToCharacter(bool bApplyYaw);
	void TickOwner(float DeltaTime);
	void TickServerValidation(float DeltaTime);
	void PlayReloadMontage();
	bool IsAirborneState(const FPUBGMirrorState& InState) const;

	// owner
	FPUBGMirrorState LastSent;
	float SendTimer = 0.f;
	float KeepAliveTimer = 0.f;
	FVector LastOwnerLocation = FVector::ZeroVector;
	FVector SmoothedVelocity = FVector::ZeroVector;
	bool bHasLastLocation = false;

	// server
	PUBGLogic::FSpeedValidator SpeedValidator;
	FVector SafeLocation = FVector::ZeroVector;
	FVector PreviousTickLocation = FVector::ZeroVector;
	bool bHasValidatedLocation = false;
	float ValidationGrace = 2.f;

	// remote view
	float TargetYaw = 0.f;
	uint32 PreviousFlags = 0;
	int32 ReloadBit = -1;
};
