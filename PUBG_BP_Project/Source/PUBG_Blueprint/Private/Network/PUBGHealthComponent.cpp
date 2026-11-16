#include "Network/PUBGHealthComponent.h"

#include "PUBG_Blueprint.h"
#include "Core/PUBGBlueprintBridge.h"
#include "Core/PUBGSettings.h"
#include "Network/PUBGMatchStateComponent.h"

#include "Components/CapsuleComponent.h"
#include "GameFramework/Character.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "GameFramework/Controller.h"
#include "GameFramework/PlayerController.h"
#include "GameFramework/PlayerState.h"
#include "Engine/World.h"
#include "Net/UnrealNetwork.h"

UPUBGHealthComponent::UPUBGHealthComponent()
{
	SetIsReplicatedByDefault(true);
	PrimaryComponentTick.bCanEverTick = true;
	PrimaryComponentTick.TickInterval = 0.25f;
}

UPUBGHealthComponent* UPUBGHealthComponent::Find(const AActor* Actor)
{
	return Actor ? Actor->FindComponentByClass<UPUBGHealthComponent>() : nullptr;
}

void UPUBGHealthComponent::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
	Super::GetLifetimeReplicatedProps(OutLifetimeProps);
	DOREPLIFETIME(UPUBGHealthComponent, Health);
	DOREPLIFETIME(UPUBGHealthComponent, MaxHealth);
	DOREPLIFETIME_CONDITION(UPUBGHealthComponent, Energy, COND_OwnerOnly);
	DOREPLIFETIME(UPUBGHealthComponent, bDead);
}

void UPUBGHealthComponent::BeginPlay()
{
	Super::BeginPlay();
	AActor* Owner = GetOwner();
	if (Owner && Owner->HasAuthority())
	{
		MaxHealth = FMath::Max(1.f, UPUBGSettings::Get()->MaxHealth);
		Health = MaxHealth;
		Owner->OnTakeAnyDamage.AddDynamic(this, &UPUBGHealthComponent::HandleAnyDamage);
	}
	PushToBlueprint();
}

void UPUBGHealthComponent::TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction)
{
	Super::TickComponent(DeltaTime, TickType, ThisTickFunction);
	if (!GetOwner() || !GetOwner()->HasAuthority() || bDead || Energy <= 0.f)
	{
		return;
	}
	// Boost energy drains over time and slowly regenerates health (server side).
	const UPUBGSettings* S = UPUBGSettings::Get();
	Energy = FMath::Max(0.f, Energy - S->EnergyDrainPerSecond * DeltaTime);
	OnRep_Energy();
	if (Health < MaxHealth)
	{
		SetHealthInternal(FMath::Min(MaxHealth, Health + S->EnergyHealPerSecond * DeltaTime));
	}
}

void UPUBGHealthComponent::HandleAnyDamage(AActor* DamagedActor, float Damage, const UDamageType* DamageType, AController* InstigatedBy, AActor* DamageCauser)
{
	if (bDead || Damage <= 0.f || !GetOwner()->HasAuthority())
	{
		return;
	}
	SetHealthInternal(Health - Damage);
	if (Health <= 0.f)
	{
		Die(InstigatedBy);
	}
}

void UPUBGHealthComponent::SetHealthInternal(float NewHealth)
{
	const float Old = Health;
	Health = FMath::Clamp(NewHealth, 0.f, MaxHealth);
	if (!FMath::IsNearlyEqual(Old, Health))
	{
		OnRep_Health(Old); // server-side notify (listen host UI, delegates)
	}
}

void UPUBGHealthComponent::ServerHeal(float Amount, float Limit)
{
	if (bDead || Amount <= 0.f || !GetOwner()->HasAuthority())
	{
		return;
	}
	const float Cap = FMath::Clamp(Limit <= 0.f ? MaxHealth : Limit, 0.f, MaxHealth);
	if (Health < Cap)
	{
		SetHealthInternal(FMath::Min(Cap, Health + Amount));
	}
}

void UPUBGHealthComponent::ServerAddEnergy(float Amount)
{
	if (bDead || Amount <= 0.f || !GetOwner()->HasAuthority())
	{
		return;
	}
	Energy = FMath::Clamp(Energy + Amount, 0.f, 100.f);
	OnRep_Energy();
}

void UPUBGHealthComponent::ServerSetLastHit(FName WeaponID, bool bHeadshot)
{
	LastHitWeapon = WeaponID;
	bLastHitHeadshot = bHeadshot;
}

void UPUBGHealthComponent::ServerKill(AController* Killer)
{
	if (!bDead && GetOwner()->HasAuthority())
	{
		SetHealthInternal(0.f);
		Die(Killer);
	}
}

void UPUBGHealthComponent::Die(AController* Killer)
{
	if (bDead)
	{
		return;
	}
	bDead = true;
	Energy = 0.f;
	APawn* Victim = Cast<APawn>(GetOwner());
	UE_LOG(LogPUBG, Log, TEXT("%s eliminated by %s"), *GetNameSafe(Victim), *GetNameSafe(Killer));
	if (UPUBGMatchStateComponent* Match = UPUBGMatchStateComponent::Get(this))
	{
		Match->ServerNotifyElimination(Victim, Killer, LastHitWeapon, bLastHitHeadshot);
	}
	OnRep_Dead();
}

void UPUBGHealthComponent::OnRep_Health(float OldHealth)
{
	if (Health < OldHealth)
	{
		LastDamageTime = FPlatformTime::Seconds();
	}
	PushToBlueprint();
	OnHealthChanged.Broadcast(Health, MaxHealth);
}

void UPUBGHealthComponent::OnRep_Energy()
{
	PushToBlueprint();
}

void UPUBGHealthComponent::OnRep_Dead()
{
	if (bDead)
	{
		ApplyDeathLocally();
		OnDied.Broadcast(GetOwner());
	}
}

void UPUBGHealthComponent::ApplyDeathLocally()
{
	if (bDeathApplied)
	{
		return;
	}
	bDeathApplied = true;
	ACharacter* Character = Cast<ACharacter>(GetOwner());
	if (!Character)
	{
		return;
	}
	const FPUBGBlueprintNames& Names = UPUBGSettings::Get()->BlueprintNames;

	// MyAnimeBlueprint reads MyCharacter.isDead and plays the existing death animations.
	PUBGBridge::SetBool(Character, Names.IsDead, true);

	if (UCharacterMovementComponent* Movement = Character->GetCharacterMovement())
	{
		Movement->StopMovementImmediately();
		Movement->DisableMovement();
	}
	if (UCapsuleComponent* Capsule = Character->GetCapsuleComponent())
	{
		Capsule->SetCollisionResponseToChannel(ECC_Pawn, ECR_Ignore);
	}
	if (Character->IsLocallyControlled())
	{
		if (APlayerController* PC = Cast<APlayerController>(Character->GetController()))
		{
			// MyPlayerController moves the pawn itself (SetActorLocation); its EnableMove flag gates that.
			PUBGBridge::SetBool(PC, TEXT("EnableMove"), false);
			Character->DisableInput(PC);
		}
	}
}

void UPUBGHealthComponent::PushToBlueprint()
{
	// Keep the ORIGINAL HUD (UserInfoUI -> MyPlayerState.HealthPoint) in sync for the local player.
	const APawn* Pawn = Cast<APawn>(GetOwner());
	if (!Pawn || !Pawn->IsLocallyControlled())
	{
		return;
	}
	if (APlayerState* PS = Pawn->GetPlayerState())
	{
		const FPUBGBlueprintNames& Names = UPUBGSettings::Get()->BlueprintNames;
		PUBGBridge::CallWithNumber(PS, Names.SetHealthPoint, Health);
		PUBGBridge::CallWithNumber(PS, Names.SetEnergyPoint, Energy);
	}
}
