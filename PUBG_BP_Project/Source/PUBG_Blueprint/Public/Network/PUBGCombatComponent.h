// Server-authoritative shooting for a player pawn.
//
// The ORIGINAL weapon Blueprint (ItemWeapon) keeps doing everything the shooter
// sees and hears locally (fire rate, recoil, sound, cosmetic projectile). The
// owning client notices each real shot by watching ItemWeapon.Ammo decrease and
// sends the aim ray + local hit to the server (UPUBGPlayerNetComponent::ServerShot).
// This component then validates the shot on the server (verified weapon, fire
// rate, magazine/ammo, geometry, line of sight), applies damage, and plays the
// shot for everybody else.

#pragma once

#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "Engine/NetSerialization.h"
#include "Logic/PUBGNetLogic.h"
#include "PUBGCombatComponent.generated.h"

class UPUBGPlayerNetComponent;
class UAnimMontage;
class USoundBase;

USTRUCT()
struct FPUBGShot
{
	GENERATED_BODY()

	UPROPERTY() FVector_NetQuantize Origin;
	UPROPERTY() FVector_NetQuantizeNormal Direction;
	UPROPERTY() FVector_NetQuantize HitLocation;
	UPROPERTY() FVector_NetQuantizeNormal ImpactNormal;
	UPROPERTY() AActor* HitActor = nullptr;
	UPROPERTY() FName HitBone;
	UPROPERTY() bool bBlockingHit = false;
};

UCLASS(ClassGroup = (PUBG))
class PUBG_BLUEPRINT_API UPUBGCombatComponent : public UActorComponent
{
	GENERATED_BODY()

public:
	UPUBGCombatComponent();

	static UPUBGCombatComponent* Find(const AActor* Actor);

	/** Owning client: builds a shot from the camera ray (local trace). */
	bool BuildLocalShot(FPUBGShot& OutShot) const;

	/** Server: validates and applies a shot reported by the owning client. */
	void ServerProcessShot(const FPUBGShot& Shot, UPUBGPlayerNetComponent* Ledger);

	// ---- Hit marker for the local HUD
	double LastConfirmedHitTime = -100.0;
	bool bLastHitHeadshot = false;
	bool bLastHitKilled = false;
	float LastHitDamage = 0.f;

protected:
	UFUNCTION(Client, Unreliable) void ClientHitConfirmed(float Damage, bool bHeadshot, bool bKilled);
	UFUNCTION(NetMulticast, Unreliable) void MulticastShotFX(FVector_NetQuantize Origin, FVector_NetQuantize End, FVector_NetQuantizeNormal ImpactNormal, bool bHitPawn, bool bBlockingHit, FName WeaponID);

private:
	bool HasLineOfSight(const FVector& From, const FVector& To, const AActor* Shooter, const AActor* Target) const;
	static PUBGLogic::EHitZone ZoneFromBone(FName Bone);
	UAnimMontage* GetFireMontage() const;
	USoundBase* GetFireSound(FName WeaponID) const;

	PUBGLogic::FFireRateLimiter FireLimiter;
	mutable TMap<FName, TWeakObjectPtr<USoundBase>> SoundCache;
};
