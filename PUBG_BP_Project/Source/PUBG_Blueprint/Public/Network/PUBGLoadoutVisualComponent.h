// What OTHER players see of someone's equipment.
//
// The original Blueprints attach weapons / equipment only on the owning
// machine. The server publishes the verified loadout (from the ledger) and every
// other machine attaches matching meshes, taken from the original DataTables, to
// the original sockets (MyGameInstance: Socket_Gun_Stand, Socket_BackLeft_Normal,
// Socket_Helmet, ...). Also applies the outfit chosen on the character screen.

#pragma once

#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "Core/PUBGTypes.h"
#include "PUBGLoadoutVisualComponent.generated.h"

class USkeletalMeshComponent;
class UStaticMeshComponent;
class ACharacter;

UCLASS(ClassGroup = (PUBG))
class PUBG_BLUEPRINT_API UPUBGLoadoutVisualComponent : public UActorComponent
{
	GENERATED_BODY()

public:
	UPUBGLoadoutVisualComponent();

	static UPUBGLoadoutVisualComponent* Find(const AActor* Actor);

	virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;
	virtual void BeginPlay() override;
	virtual void TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction) override;

	void ServerSetLoadout(const FPUBGVisualLoadout& NewLoadout);
	void ServerSetCharacterPreset(int32 PresetIndex);

	UFUNCTION(BlueprintPure, Category = "PUBG|Loadout") FPUBGVisualLoadout GetLoadout() const { return Loadout; }

protected:
	UPROPERTY(ReplicatedUsing = OnRep_Loadout) FPUBGVisualLoadout Loadout;
	UPROPERTY(ReplicatedUsing = OnRep_Preset) int32 CharacterPreset = -1;

	UFUNCTION() void OnRep_Loadout();
	UFUNCTION() void OnRep_Preset();

	UPROPERTY(Transient) TArray<USkeletalMeshComponent*> WeaponMeshes;
	UPROPERTY(Transient) TArray<UStaticMeshComponent*> EquipmentMeshes;

private:
	ACharacter* GetCharacter() const;
	bool ShowsRemoteVisuals() const;
	void RefreshRemoteVisuals();
	void UpdateWeaponSockets();
	void ApplyPreset();
	void ApplyFashion();
	FName GetSocketName(FName GameInstanceVariable, const TCHAR* Fallback) const;
	USkeletalMeshComponent* FindNamedMesh(const TCHAR* ComponentName) const;
	USkeletalMeshComponent* EnsureWeaponMesh(int32 Index);
	UStaticMeshComponent* EnsureEquipmentMesh(int32 Index);

	FName CurrentWeaponSockets[2];
	float SocketTimer = 0.f;
	float PresetRetryTimer = 0.f;
	int32 PresetApplications = 0;
};
