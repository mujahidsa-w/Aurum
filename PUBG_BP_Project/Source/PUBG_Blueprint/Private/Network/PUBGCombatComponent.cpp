#include "Network/PUBGCombatComponent.h"

#include "PUBG_Blueprint.h"
#include "Core/PUBGBlueprintBridge.h"
#include "Core/PUBGItemData.h"
#include "Core/PUBGSettings.h"
#include "Network/PUBGHealthComponent.h"
#include "Network/PUBGPlayerNetComponent.h"

#include "Animation/AnimInstance.h"
#include "Animation/AnimMontage.h"
#include "Components/CapsuleComponent.h"
#include "Components/SkeletalMeshComponent.h"
#include "Engine/World.h"
#include "GameFramework/Character.h"
#include "GameFramework/DamageType.h"
#include "GameFramework/PlayerController.h"
#include "GameFramework/PlayerState.h"
#include "Kismet/GameplayStatics.h"
#include "Sound/SoundBase.h"

UPUBGCombatComponent::UPUBGCombatComponent()
{
	SetIsReplicatedByDefault(true);
	PrimaryComponentTick.bCanEverTick = false;
}

UPUBGCombatComponent* UPUBGCombatComponent::Find(const AActor* Actor)
{
	return Actor ? Actor->FindComponentByClass<UPUBGCombatComponent>() : nullptr;
}

bool UPUBGCombatComponent::BuildLocalShot(FPUBGShot& OutShot) const
{
	ACharacter* Character = Cast<ACharacter>(GetOwner());
	APlayerController* PC = Character ? Cast<APlayerController>(Character->GetController()) : nullptr;
	if (!PC)
	{
		return false;
	}
	const UPUBGSettings* S = UPUBGSettings::Get();

	FVector CameraLocation;
	FRotator CameraRotation;
	PC->GetPlayerViewPoint(CameraLocation, CameraRotation);

	// Hitscan from the crosshair, with a cone depending on the Blueprint aim state.
	bool bSightAiming = false, bAiming = false;
	PUBGBridge::GetBool(Character, S->BlueprintNames.IsSightAiming, bSightAiming);
	PUBGBridge::GetBool(Character, S->BlueprintNames.IsAiming, bAiming);
	float SpreadDegrees = bSightAiming ? 0.15f : (bAiming ? 0.6f : 1.8f);
	if (Character->GetVelocity().Size2D() > 50.f)
	{
		SpreadDegrees += 0.8f;
	}
	const FVector Direction = FMath::VRandCone(CameraRotation.Vector(), FMath::DegreesToRadians(SpreadDegrees));

	// Third-person camera sits behind the character: start the trace at the point of
	// the camera ray closest to the character so walls behind the player are ignored.
	const FVector Eye = Character->GetPawnViewLocation();
	const float Along = FMath::Max(0.f, FVector::DotProduct(Eye - CameraLocation, Direction));
	const FVector Start = CameraLocation + Direction * Along;
	const FVector End = Start + Direction * S->MaxShotRange;

	FCollisionQueryParams Params(SCENE_QUERY_STAT(PUBGLocalShot), true, Character);
	TArray<AActor*> Attached;
	Character->GetAttachedActors(Attached);
	Params.AddIgnoredActors(Attached);

	FCollisionObjectQueryParams Objects;
	Objects.AddObjectTypesToQuery(ECC_WorldStatic);
	Objects.AddObjectTypesToQuery(ECC_WorldDynamic);
	Objects.AddObjectTypesToQuery(ECC_Pawn);
	Objects.AddObjectTypesToQuery(ECC_PhysicsBody);
	Objects.AddObjectTypesToQuery(ECC_Destructible);
	Objects.AddObjectTypesToQuery(ECC_GameTraceChannel1); // project object channel "Ground"

	FHitResult Hit;
	const bool bHit = GetWorld()->LineTraceSingleByObjectType(Hit, Start, End, Objects, Params);

	OutShot = FPUBGShot();
	OutShot.Origin = Start;
	OutShot.Direction = Direction;
	OutShot.bBlockingHit = bHit;
	OutShot.HitLocation = bHit ? Hit.ImpactPoint : End;
	OutShot.ImpactNormal = bHit ? Hit.ImpactNormal : -Direction;

	APawn* HitPawn = bHit ? Cast<APawn>(Hit.GetActor()) : nullptr;
	if (HitPawn && UPUBGHealthComponent::Find(HitPawn))
	{
		OutShot.HitActor = HitPawn;
		OutShot.HitBone = Hit.BoneName;
		// The capsule is usually hit first; refine against the physics asset for the bone.
		ACharacter* HitCharacter = Cast<ACharacter>(HitPawn);
		USkeletalMeshComponent* Mesh = HitCharacter ? HitCharacter->GetMesh() : nullptr;
		if (Mesh && Hit.GetComponent() != Mesh)
		{
			FHitResult MeshHit;
			if (Mesh->LineTraceComponent(MeshHit, Start, End, FCollisionQueryParams(SCENE_QUERY_STAT(PUBGBoneTrace), true)))
			{
				OutShot.HitBone = MeshHit.BoneName;
				OutShot.HitLocation = MeshHit.ImpactPoint;
			}
		}
	}
	return true;
}

PUBGLogic::EHitZone UPUBGCombatComponent::ZoneFromBone(FName Bone)
{
	if (Bone.IsNone())
	{
		return PUBGLogic::EHitZone::Body;
	}
	const FString Name = Bone.ToString().ToLower();
	if (Name.Contains(TEXT("head")) || Name.Contains(TEXT("neck")))
	{
		return PUBGLogic::EHitZone::Head;
	}
	static const TCHAR* LimbTokens[] = { TEXT("arm"), TEXT("hand"), TEXT("finger"), TEXT("thigh"), TEXT("calf"), TEXT("leg"), TEXT("foot"), TEXT("toe") };
	for (const TCHAR* Token : LimbTokens)
	{
		if (Name.Contains(Token))
		{
			return PUBGLogic::EHitZone::Limb;
		}
	}
	return PUBGLogic::EHitZone::Body;
}

bool UPUBGCombatComponent::HasLineOfSight(const FVector& From, const FVector& To, const AActor* Shooter, const AActor* Target) const
{
	FCollisionQueryParams Params(SCENE_QUERY_STAT(PUBGShotLOS), false, Shooter);
	Params.AddIgnoredActor(Target);
	TArray<AActor*> Attached;
	if (Shooter)
	{
		Shooter->GetAttachedActors(Attached);
		Params.AddIgnoredActors(Attached);
	}
	if (Target)
	{
		Target->GetAttachedActors(Attached);
		Params.AddIgnoredActors(Attached);
	}
	FHitResult Hit;
	if (!GetWorld()->LineTraceSingleByChannel(Hit, From, To, ECC_Visibility, Params))
	{
		return true;
	}
	return FVector::DistSquared(Hit.ImpactPoint, To) < FMath::Square(30.f);
}

void UPUBGCombatComponent::ServerProcessShot(const FPUBGShot& Shot, UPUBGPlayerNetComponent* Ledger)
{
	ACharacter* Shooter = Cast<ACharacter>(GetOwner());
	if (!Shooter || !Shooter->HasAuthority() || !Ledger)
	{
		return;
	}
	const UPUBGHealthComponent* ShooterHealth = UPUBGHealthComponent::Find(Shooter);
	if (ShooterHealth && ShooterHealth->IsDead())
	{
		return;
	}
	const UPUBGSettings* S = UPUBGSettings::Get();
	const double Now = GetWorld()->GetTimeSeconds();

	FName WeaponID;
	int32 Slot = 0;
	if (!Ledger->GetHeldWeapon(WeaponID, Slot))
	{
		UE_LOG(LogPUBG, Verbose, TEXT("Shot rejected (%s): no verified weapon in hand."), *Shooter->GetName());
		return;
	}
	const FPUBGWeaponStats Stats = PUBGItemData::GetWeaponStats(WeaponID);
	if (!FireLimiter.TryConsume(Now, Stats.FiringInterval, S->FireRateTolerance))
	{
		UE_LOG(LogPUBG, Verbose, TEXT("Shot rejected (%s): fire rate."), *Shooter->GetName());
		return;
	}
	if (!Ledger->ServerTryConsumeShot(Now))
	{
		UE_LOG(LogPUBG, Verbose, TEXT("Shot rejected (%s): magazine empty / reloading / no ammo."), *Shooter->GetName());
		return;
	}

	bool bHitPawn = false;
	APawn* Target = Cast<APawn>(Shot.HitActor);
	UPUBGHealthComponent* TargetHealth = UPUBGHealthComponent::Find(Target);
	if (Target && Target != Shooter && TargetHealth && !TargetHealth->IsDead())
	{
		const ACharacter* TargetCharacter = Cast<ACharacter>(Target);
		const UCapsuleComponent* Capsule = TargetCharacter ? TargetCharacter->GetCapsuleComponent() : nullptr;
		const float Radius = Capsule ? Capsule->GetScaledCapsuleRadius() : 40.f;
		const float HalfHeight = Capsule ? Capsule->GetScaledCapsuleHalfHeight() : 90.f;
		const APlayerState* PS = Shooter->GetPlayerState();
		const float Latency = PS ? PS->GetPing() * 4.f / 1000.f : 0.1f;

		PUBGLogic::FHitCheckTuning Tuning;
		Tuning.MaxOriginOffset = S->MaxCameraOffset;
		Tuning.MaxRange = S->MaxShotRange;
		Tuning.TargetTolerance = S->HitTargetTolerance;
		Tuning.MaxLatencyCompensation = S->MaxLatencyCompensation;

		const FVector ShooterLocation = Shooter->GetPawnViewLocation();
		const PUBGLogic::EHitCheck Check = PUBGLogic::ValidateHitGeometry(ShooterLocation, (FVector)Shot.Origin, (FVector)Shot.HitLocation,
			Target->GetActorLocation(), Target->GetVelocity(), Radius, HalfHeight, Latency, Tuning);

		if (Check == PUBGLogic::EHitCheck::Ok && HasLineOfSight(ShooterLocation, Shot.HitLocation, Shooter, Target))
		{
			PUBGLogic::EHitZone Zone = ZoneFromBone(Shot.HitBone);
			const PUBGLogic::EHitZone HeightZone = PUBGLogic::ZoneFromHeight(Shot.HitLocation.Z, Target->GetActorLocation().Z, HalfHeight);
			if (Shot.HitBone.IsNone())
			{
				Zone = HeightZone;
			}
			else if (Zone == PUBGLogic::EHitZone::Head && HeightZone != PUBGLogic::EHitZone::Head)
			{
				Zone = PUBGLogic::EHitZone::Body; // reported head bone does not match the hit height
			}

			const UPUBGPlayerNetComponent* VictimLedger = UPUBGPlayerNetComponent::Find(Target->GetController());
			PUBGLogic::FDamageTuning DamageTuning;
			DamageTuning.HeadMultiplier = S->HeadshotMultiplier;
			DamageTuning.LimbMultiplier = S->LimbMultiplier;
			const float Damage = PUBGLogic::ComputeDamage(Stats.Damage, Zone,
				VictimLedger ? VictimLedger->GetArmorReduction(true) : 0.f,
				VictimLedger ? VictimLedger->GetArmorReduction(false) : 0.f, DamageTuning);

			TargetHealth->ServerSetLastHit(WeaponID, Zone == PUBGLogic::EHitZone::Head);
			FHitResult HitInfo(Target, TargetCharacter ? TargetCharacter->GetMesh() : nullptr, Shot.HitLocation, -Shot.Direction);
			HitInfo.BoneName = Shot.HitBone;
			UGameplayStatics::ApplyPointDamage(Target, Damage, Shot.Direction, HitInfo, Shooter->GetController(), Shooter, UDamageType::StaticClass());
			bHitPawn = true;
			ClientHitConfirmed(Damage, Zone == PUBGLogic::EHitZone::Head, TargetHealth->IsDead());
		}
		else
		{
			UE_LOG(LogPUBG, Verbose, TEXT("Hit rejected (%s -> %s): check=%d"), *Shooter->GetName(), *Target->GetName(), (int32)Check);
		}
	}

	MulticastShotFX(Shot.Origin, Shot.HitLocation, Shot.ImpactNormal, bHitPawn, Shot.bBlockingHit, WeaponID);
}

void UPUBGCombatComponent::ClientHitConfirmed_Implementation(float Damage, bool bHeadshot, bool bKilled)
{
	LastConfirmedHitTime = FPlatformTime::Seconds();
	LastHitDamage = Damage;
	bLastHitHeadshot = bHeadshot;
	bLastHitKilled = bKilled;
}

UAnimMontage* UPUBGCombatComponent::GetFireMontage() const
{
	static TWeakObjectPtr<UAnimMontage> Cached[3];
	static const TCHAR* Paths[3] = {
		TEXT("/Game/Blueprints/Character/Montage/AS_Rifle_Stand_Fire_Montage.AS_Rifle_Stand_Fire_Montage"),
		TEXT("/Game/Blueprints/Character/Montage/AS_Rifle_Crouch_Fire_Montage.AS_Rifle_Crouch_Fire_Montage"),
		TEXT("/Game/Blueprints/Character/Montage/AS_Rifle_Prone_Fire_Montage.AS_Rifle_Prone_Fire_Montage"),
	};
	const FPUBGBlueprintNames& Names = UPUBGSettings::Get()->BlueprintNames;
	bool bProne = false, bCrouch = false;
	PUBGBridge::GetBool(GetOwner(), Names.IsProne, bProne);
	PUBGBridge::GetBool(GetOwner(), Names.IsCrouching, bCrouch);
	const int32 Index = bProne ? 2 : (bCrouch ? 1 : 0);
	if (!Cached[Index].IsValid())
	{
		Cached[Index] = Cast<UAnimMontage>(FSoftObjectPath(Paths[Index]).TryLoad());
	}
	return Cached[Index].Get();
}

USoundBase* UPUBGCombatComponent::GetFireSound(FName WeaponID) const
{
	if (TWeakObjectPtr<USoundBase>* Found = SoundCache.Find(WeaponID))
	{
		if (Found->IsValid())
		{
			return Found->Get();
		}
	}
	USoundBase* Sound = Cast<USoundBase>(PUBGItemData::GetWeaponStats(WeaponID).FireSound.TryLoad());
	SoundCache.Add(WeaponID, Sound);
	return Sound;
}

void UPUBGCombatComponent::MulticastShotFX_Implementation(FVector_NetQuantize Origin, FVector_NetQuantize End, FVector_NetQuantizeNormal ImpactNormal,
	bool bHitPawn, bool bBlockingHit, FName WeaponID)
{
	if (GetNetMode() == NM_DedicatedServer)
	{
		return;
	}
	ACharacter* Shooter = Cast<ACharacter>(GetOwner());
	if (!Shooter || Shooter->IsLocallyControlled())
	{
		return; // the shooter's own Blueprint already played everything locally
	}
	if (USoundBase* Sound = GetFireSound(WeaponID))
	{
		UGameplayStatics::PlaySoundAtLocation(this, Sound, Shooter->GetActorLocation());
	}
	if (UAnimMontage* Montage = GetFireMontage())
	{
		if (UAnimInstance* Anim = Shooter->GetMesh() ? Shooter->GetMesh()->GetAnimInstance() : nullptr)
		{
			Anim->Montage_Play(Montage);
		}
	}
	if (bBlockingHit && !bHitPawn)
	{
		if (UClass* DecalClass = UPUBGSettings::Get()->ImpactDecalClass.TryLoadClass<AActor>())
		{
			FActorSpawnParameters Params;
			Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
			if (AActor* Decal = GetWorld()->SpawnActor<AActor>(DecalClass, End, ImpactNormal.Rotation(), Params))
			{
				Decal->SetLifeSpan(10.f);
			}
		}
	}
}
