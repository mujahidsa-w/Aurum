// Server-authoritative health, energy (boost) and death for a player pawn.
//
// The original project stores HealthPoint in MyPlayerState but never applies
// damage. In networked games this component owns the real value: damage is only
// applied on the server (UE damage pipeline: ApplyPointDamage / OnTakeAnyDamage),
// health replicates, and the owning client's MyPlayerState.SetHealthPoint() is
// called so the original UserInfoUI keeps showing the correct number.

#pragma once

#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "PUBGHealthComponent.generated.h"

class AController;
class UDamageType;

DECLARE_DYNAMIC_MULTICAST_DELEGATE_TwoParams(FPUBGOnHealthChanged, float, Health, float, MaxHealth);
DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FPUBGOnDied, AActor*, Victim);

UCLASS(ClassGroup = (PUBG), meta = (BlueprintSpawnableComponent))
class PUBG_BLUEPRINT_API UPUBGHealthComponent : public UActorComponent
{
	GENERATED_BODY()

public:
	UPUBGHealthComponent();

	UFUNCTION(BlueprintPure, Category = "PUBG|Health", meta = (DisplayName = "Find PUBG Health"))
	static UPUBGHealthComponent* Find(const AActor* Actor);

	virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;
	virtual void BeginPlay() override;
	virtual void TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction) override;

	UFUNCTION(BlueprintPure, Category = "PUBG|Health") float GetHealth() const { return Health; }
	UFUNCTION(BlueprintPure, Category = "PUBG|Health") float GetMaxHealth() const { return MaxHealth; }
	UFUNCTION(BlueprintPure, Category = "PUBG|Health") float GetEnergy() const { return Energy; }
	UFUNCTION(BlueprintPure, Category = "PUBG|Health") bool IsDead() const { return bDead; }

	// ---- Server only
	/** Heals Amount but never above Limit (DT_Item_Health "Limit", e.g. bandages stop at 75). */
	void ServerHeal(float Amount, float Limit);
	void ServerAddEnergy(float Amount);
	/** Used by the combat component right before ApplyPointDamage, for the kill feed. */
	void ServerSetLastHit(FName WeaponID, bool bHeadshot);
	void ServerKill(AController* Killer);

	/** Local time of the last health decrease (UI damage flash). */
	double LastDamageTime = -100.0;

	UPROPERTY(BlueprintAssignable, Category = "PUBG|Health") FPUBGOnHealthChanged OnHealthChanged;
	UPROPERTY(BlueprintAssignable, Category = "PUBG|Health") FPUBGOnDied OnDied;

protected:
	UPROPERTY(ReplicatedUsing = OnRep_Health, BlueprintReadOnly, Category = "PUBG|Health") float Health = 100.f;
	UPROPERTY(Replicated, BlueprintReadOnly, Category = "PUBG|Health") float MaxHealth = 100.f;
	UPROPERTY(ReplicatedUsing = OnRep_Energy, BlueprintReadOnly, Category = "PUBG|Health") float Energy = 0.f;
	UPROPERTY(ReplicatedUsing = OnRep_Dead, BlueprintReadOnly, Category = "PUBG|Health") bool bDead = false;

	UFUNCTION() void OnRep_Health(float OldHealth);
	UFUNCTION() void OnRep_Energy();
	UFUNCTION() void OnRep_Dead();

	UFUNCTION() void HandleAnyDamage(AActor* DamagedActor, float Damage, const UDamageType* DamageType, AController* InstigatedBy, AActor* DamageCauser);

private:
	void SetHealthInternal(float NewHealth);
	void Die(AController* Killer);
	void ApplyDeathLocally();
	void PushToBlueprint();

	FName LastHitWeapon;
	bool bLastHitHeadshot = false;
	bool bDeathApplied = false;
	float RegenAccumulator = 0.f;
};
