#include "Network/PUBGStateMirrorComponent.h"

#include "PUBG_Blueprint.h"
#include "Core/PUBGBlueprintBridge.h"
#include "Core/PUBGSettings.h"
#include "Network/PUBGHealthComponent.h"

#include "Animation/AnimInstance.h"
#include "Animation/AnimMontage.h"
#include "Components/SkeletalMeshComponent.h"
#include "Engine/World.h"
#include "GameFramework/Character.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "Net/UnrealNetwork.h"

namespace
{
	constexpr float SendInterval = 1.f / 15.f;
	constexpr float KeepAliveInterval = 0.5f;
}

UPUBGStateMirrorComponent::UPUBGStateMirrorComponent()
{
	SetIsReplicatedByDefault(true);
	PrimaryComponentTick.bCanEverTick = true;
	PrimaryComponentTick.TickGroup = TG_PostPhysics;
}

UPUBGStateMirrorComponent* UPUBGStateMirrorComponent::Find(const AActor* Actor)
{
	return Actor ? Actor->FindComponentByClass<UPUBGStateMirrorComponent>() : nullptr;
}

void UPUBGStateMirrorComponent::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
	Super::GetLifetimeReplicatedProps(OutLifetimeProps);
	DOREPLIFETIME_CONDITION(UPUBGStateMirrorComponent, State, COND_SkipOwner);
	DOREPLIFETIME_CONDITION(UPUBGStateMirrorComponent, MirroredVelocity, COND_SkipOwner);
}

ACharacter* UPUBGStateMirrorComponent::GetCharacter() const
{
	return Cast<ACharacter>(GetOwner());
}

void UPUBGStateMirrorComponent::BeginPlay()
{
	Super::BeginPlay();
	ACharacter* Character = GetCharacter();
	if (!Character)
	{
		return;
	}
	const UPUBGSettings* S = UPUBGSettings::Get();
	ReloadBit = S->MirroredBoolVariables.IndexOfByKey(FName(TEXT("isReload")));

	if (Character->HasAuthority() && S->bClientAuthoritativeMovement)
	{
		if (UCharacterMovementComponent* Movement = Character->GetCharacterMovement())
		{
			// See class comment: accept client positions, validate them with the speed check.
			Movement->bIgnoreClientMovementErrorChecksAndCorrection = true;
			Movement->bServerAcceptClientAuthoritativePosition = true;
		}
	}
	TargetYaw = Character->GetActorRotation().Yaw;
	if (UCharacterMovementComponent* Movement = Character->GetCharacterMovement())
	{
		AddTickPrerequisiteComponent(Movement);
	}
}

bool UPUBGStateMirrorComponent::CaptureLocal(FPUBGMirrorState& Out) const
{
	const ACharacter* Character = GetCharacter();
	if (!Character)
	{
		return false;
	}
	const UPUBGSettings* S = UPUBGSettings::Get();
	Out = FPUBGMirrorState();
	const int32 Count = FMath::Min(S->MirroredBoolVariables.Num(), 32);
	for (int32 i = 0; i < Count; ++i)
	{
		bool bValue = false;
		if (PUBGBridge::GetBool(Character, S->MirroredBoolVariables[i], bValue) && bValue)
		{
			Out.Flags |= (1u << i);
		}
	}
	PUBGBridge::GetFloat(Character, S->BlueprintNames.ForwardValue, Out.ForwardValue);
	PUBGBridge::GetByte(Character, S->BlueprintNames.PlayingMontageType, Out.MontageType);
	Out.Yaw = FRotator::NormalizeAxis(Character->GetActorRotation().Yaw);
	if (const UCharacterMovementComponent* Movement = Character->GetCharacterMovement())
	{
		Out.MaxWalkSpeed = Movement->MaxWalkSpeed;
	}
	return true;
}

void UPUBGStateMirrorComponent::TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction)
{
	Super::TickComponent(DeltaTime, TickType, ThisTickFunction);
	ACharacter* Character = GetCharacter();
	if (!Character)
	{
		return;
	}
	if (Character->IsLocallyControlled())
	{
		TickOwner(DeltaTime);
	}
	else
	{
		if (Character->HasAuthority())
		{
			TickServerValidation(DeltaTime);
		}
		if (GetNetMode() != NM_DedicatedServer)
		{
			// Smooth remote yaw and feed the Blueprint AnimInstance a realistic velocity.
			FRotator Rotation = Character->GetActorRotation();
			Rotation.Yaw = FMath::FixedTurn(Rotation.Yaw, TargetYaw, 720.f * DeltaTime);
			Character->SetActorRotation(Rotation);
			if (UCharacterMovementComponent* Movement = Character->GetCharacterMovement())
			{
				Movement->Velocity = MirroredVelocity;
			}
		}
	}
}

void UPUBGStateMirrorComponent::TickOwner(float DeltaTime)
{
	ACharacter* Character = GetCharacter();
	const UPUBGHealthComponent* Health = UPUBGHealthComponent::Find(Character);
	if (Health && Health->IsDead())
	{
		return;
	}
	// Velocity from position deltas: the Blueprint moves the pawn with SetActorLocation.
	const FVector Location = Character->GetActorLocation();
	if (bHasLastLocation && DeltaTime > KINDA_SMALL_NUMBER)
	{
		const FVector Instant = (Location - LastOwnerLocation) / DeltaTime;
		SmoothedVelocity = FMath::Lerp(SmoothedVelocity, Instant, FMath::Clamp(DeltaTime * 10.f, 0.f, 1.f));
	}
	LastOwnerLocation = Location;
	bHasLastLocation = true;

	SendTimer -= DeltaTime;
	KeepAliveTimer -= DeltaTime;
	if (SendTimer > 0.f)
	{
		return;
	}
	SendTimer = SendInterval;

	FPUBGMirrorState Now;
	if (!CaptureLocal(Now))
	{
		return;
	}
	const bool bDiscreteChange = Now.Flags != LastSent.Flags || Now.MontageType != LastSent.MontageType;
	const bool bContinuousChange = !FMath::IsNearlyEqual(Now.Yaw, LastSent.Yaw, 1.f) ||
		!FMath::IsNearlyEqual(Now.ForwardValue, LastSent.ForwardValue, 0.05f) ||
		!FMath::IsNearlyEqual(Now.MaxWalkSpeed, LastSent.MaxWalkSpeed, 1.f) ||
		!SmoothedVelocity.IsNearlyZero(10.f);

	if (Character->HasAuthority())
	{
		if (bDiscreteChange || bContinuousChange || KeepAliveTimer <= 0.f)
		{
			KeepAliveTimer = KeepAliveInterval;
			LastSent = Now;
			AcceptState(Now, SmoothedVelocity); // listen-server host
		}
		return;
	}
	if (bDiscreteChange)
	{
		ServerSetStateReliable(Now, SmoothedVelocity);
	}
	else if (bContinuousChange || KeepAliveTimer <= 0.f)
	{
		ServerSetStateUnreliable(Now, SmoothedVelocity);
	}
	else
	{
		return;
	}
	KeepAliveTimer = KeepAliveInterval;
	LastSent = Now;
}

bool UPUBGStateMirrorComponent::ServerSetStateReliable_Validate(const FPUBGMirrorState& NewState, FVector_NetQuantize10 Velocity) { return true; }
void UPUBGStateMirrorComponent::ServerSetStateReliable_Implementation(const FPUBGMirrorState& NewState, FVector_NetQuantize10 Velocity)
{
	AcceptState(NewState, Velocity);
}

bool UPUBGStateMirrorComponent::ServerSetStateUnreliable_Validate(const FPUBGMirrorState& NewState, FVector_NetQuantize10 Velocity) { return true; }
void UPUBGStateMirrorComponent::ServerSetStateUnreliable_Implementation(const FPUBGMirrorState& NewState, FVector_NetQuantize10 Velocity)
{
	AcceptState(NewState, Velocity);
}

void UPUBGStateMirrorComponent::AcceptState(const FPUBGMirrorState& NewState, const FVector& Velocity)
{
	const UPUBGSettings* S = UPUBGSettings::Get();
	FPUBGMirrorState Clean = NewState;
	Clean.Yaw = FRotator::NormalizeAxis(Clean.Yaw);
	Clean.ForwardValue = FMath::Clamp(Clean.ForwardValue, -2.f, 2.f);
	// Walk speed is chosen by the Blueprint (walk/run/crouch/prone); the server caps it.
	Clean.MaxWalkSpeed = FMath::Clamp(Clean.MaxWalkSpeed, 0.f, S->MaxGroundSpeed);
	State = Clean;
	MirroredVelocity = Velocity.GetClampedToMaxSize(S->MaxGroundSpeed * S->SpeedTolerance * 4.f); // free fall can be fast
	if (!GetCharacter()->IsLocallyControlled())
	{
		ApplyToCharacter(true);
	}
	else if (ACharacter* Character = GetCharacter())
	{
		if (UCharacterMovementComponent* Movement = Character->GetCharacterMovement())
		{
			Movement->MaxWalkSpeed = Clean.MaxWalkSpeed;
		}
	}
}

void UPUBGStateMirrorComponent::OnRep_State()
{
	ApplyToCharacter(true);
}

void UPUBGStateMirrorComponent::ApplyToCharacter(bool bApplyYaw)
{
	ACharacter* Character = GetCharacter();
	if (!Character || Character->IsLocallyControlled())
	{
		return;
	}
	const UPUBGSettings* S = UPUBGSettings::Get();
	const int32 Count = FMath::Min(S->MirroredBoolVariables.Num(), 32);
	for (int32 i = 0; i < Count; ++i)
	{
		PUBGBridge::SetBool(Character, S->MirroredBoolVariables[i], (State.Flags & (1u << i)) != 0);
	}
	PUBGBridge::SetFloat(Character, S->BlueprintNames.ForwardValue, State.ForwardValue);
	PUBGBridge::SetByte(Character, S->BlueprintNames.PlayingMontageType, State.MontageType);
	if (UCharacterMovementComponent* Movement = Character->GetCharacterMovement())
	{
		Movement->MaxWalkSpeed = State.MaxWalkSpeed;
	}
	if (bApplyYaw)
	{
		TargetYaw = State.Yaw;
		if (Character->HasAuthority())
		{
			// Server copy: rotation then replicates through ReplicatedMovement.
			FRotator Rotation = Character->GetActorRotation();
			Rotation.Yaw = State.Yaw;
			Character->SetActorRotation(Rotation);
		}
	}
	// Remote reload animation when the owner's isReload flag rises.
	if (ReloadBit >= 0 && GetNetMode() != NM_DedicatedServer)
	{
		const uint32 Mask = 1u << ReloadBit;
		if ((State.Flags & Mask) && !(PreviousFlags & Mask))
		{
			PlayReloadMontage();
		}
	}
	PreviousFlags = State.Flags;
}

void UPUBGStateMirrorComponent::PlayReloadMontage()
{
	static TWeakObjectPtr<UAnimMontage> Stand, Prone;
	ACharacter* Character = GetCharacter();
	bool bProne = false;
	PUBGBridge::GetBool(Character, UPUBGSettings::Get()->BlueprintNames.IsProne, bProne);
	TWeakObjectPtr<UAnimMontage>& Slot = bProne ? Prone : Stand;
	if (!Slot.IsValid())
	{
		Slot = Cast<UAnimMontage>(FSoftObjectPath(bProne
			? TEXT("/Game/Blueprints/Character/Montage/AS_Prone_Reload_Montage.AS_Prone_Reload_Montage")
			: TEXT("/Game/Blueprints/Character/Montage/AS_Stand_Reload_Montage.AS_Stand_Reload_Montage")).TryLoad());
	}
	UAnimInstance* Anim = Character && Character->GetMesh() ? Character->GetMesh()->GetAnimInstance() : nullptr;
	if (Anim && Slot.IsValid())
	{
		Anim->Montage_Play(Slot.Get());
	}
}

bool UPUBGStateMirrorComponent::IsAirborneState(const FPUBGMirrorState& InState) const
{
	const UPUBGSettings* S = UPUBGSettings::Get();
	for (const FName& Name : { S->BlueprintNames.IsOnTheAir, S->BlueprintNames.IsFreeFalling, S->BlueprintNames.IsUmbrellaOpened })
	{
		const int32 Bit = S->MirroredBoolVariables.IndexOfByKey(Name);
		if (Bit >= 0 && Bit < 32 && (InState.Flags & (1u << Bit)))
		{
			return true;
		}
	}
	return false;
}

void UPUBGStateMirrorComponent::TickServerValidation(float DeltaTime)
{
	ACharacter* Character = GetCharacter();
	const UPUBGSettings* S = UPUBGSettings::Get();
	if (!S->bClientAuthoritativeMovement)
	{
		return; // the CharacterMovementComponent is authoritative
	}
	const FVector Location = Character->GetActorLocation();
	if (!bHasValidatedLocation)
	{
		SafeLocation = PreviousTickLocation = Location;
		bHasValidatedLocation = true;
		return;
	}
	const UCharacterMovementComponent* Movement = Character->GetCharacterMovement();
	// Spawn grace, plane drop, free fall and parachute legitimately move fast.
	if (ValidationGrace > 0.f || IsAirborneState(State) || (Movement && Movement->IsFalling()))
	{
		ValidationGrace = FMath::Max(0.f, ValidationGrace - DeltaTime);
		SafeLocation = PreviousTickLocation = Location;
		SpeedValidator.Reset();
		return;
	}
	const float Allowed = FMath::Max(State.MaxWalkSpeed, 600.f) * S->SpeedTolerance;
	const float Step = FVector::Dist2D(Location, PreviousTickLocation);
	PreviousTickLocation = Location;
	if (SpeedValidator.AddSample(DeltaTime, Step, Allowed))
	{
		UE_LOG(LogPUBG, Warning, TEXT("Speed check failed for %s, correcting position."), *Character->GetName());
		ServerTeleport(SafeLocation);
		return;
	}
	// A window that just closed without violation makes this position trustworthy.
	if (SpeedValidator.WindowTime <= KINDA_SMALL_NUMBER && SpeedValidator.ConsecutiveViolations == 0)
	{
		SafeLocation = Location;
	}
}

void UPUBGStateMirrorComponent::ServerTeleport(const FVector& Location)
{
	ACharacter* Character = GetCharacter();
	if (!Character || !Character->HasAuthority())
	{
		return;
	}
	Character->SetActorLocation(Location, false, nullptr, ETeleportType::TeleportPhysics);
	SafeLocation = PreviousTickLocation = Location;
	SpeedValidator.Reset();
	ValidationGrace = 1.f;
	if (!Character->IsLocallyControlled())
	{
		ClientCorrectLocation(Location);
	}
}

void UPUBGStateMirrorComponent::ClientCorrectLocation_Implementation(FVector_NetQuantize Location)
{
	if (ACharacter* Character = GetCharacter())
	{
		Character->SetActorLocation(Location, false, nullptr, ETeleportType::TeleportPhysics);
		bHasLastLocation = false;
	}
}
