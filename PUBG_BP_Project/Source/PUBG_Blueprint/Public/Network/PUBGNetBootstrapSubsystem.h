// Attaches the multiplayer layer to the ORIGINAL Blueprint actors at runtime.
//
// No Blueprint is reparented or edited. On a listen / dedicated server, every
// relevant actor gets its network components right after it spawns:
//   MyPlayerState      -> UPUBGPlayerProfileComponent
//   MyPlayerController -> UPUBGPlayerNetComponent
//   MyCharacter        -> Health, Combat, StateMirror, LoadoutVisual
//   MyGameState        -> UPUBGMatchStateComponent
//   PickupBase (any)   -> bReplicates + UPUBGPickupReplicationComponent
// Replicated components created at runtime on the server are re-created on
// clients by Unreal's subobject replication.
//
// Standalone (single-player) worlds are left completely untouched, so the
// original game behaves exactly as before. Lobby / main-menu worlds use their
// own C++ classes and are skipped too.

#pragma once

#include "CoreMinimal.h"
#include "Subsystems/WorldSubsystem.h"
#include "PUBGNetBootstrapSubsystem.generated.h"

class AGameModeBase;
class APawn;

UCLASS()
class PUBG_BLUEPRINT_API UPUBGNetBootstrapSubsystem : public UWorldSubsystem
{
	GENERATED_BODY()

public:
	virtual bool ShouldCreateSubsystem(UObject* Outer) const override;
	virtual void Initialize(FSubsystemCollectionBase& Collection) override;
	virtual void Deinitialize() override;

private:
	bool IsNetworkedServer() const;
	bool IsMenuOrLobbyWorld() const;
	void HandleActorSpawned(AActor* Actor);
	void HandlePreLogin(AGameModeBase* GameMode, const FUniqueNetIdRepl& NewPlayer, FString& ErrorMessage);
	void ScanExistingActors();
	void SetupActor(AActor* Actor, bool bFromScan);
	void ReplaceLevelPickup(AActor* Pickup);
	void FinishPawnSetup(TWeakObjectPtr<APawn> WeakPawn, int32 Attempt);
	void SpreadSpawn(APawn* Pawn);

	FDelegateHandle SpawnHandle;
	FDelegateHandle PreLoginHandle;
	bool bScanned = false;
};
