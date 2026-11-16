// State and input injection for the on-screen touch controls (local player only).
//
// Every control resolves to one of the virtual keys in PUBGTouchKeys, injected
// with APlayerController::InputKey / InputAxis. DefaultInput.ini maps those keys
// to the ORIGINAL action names, so MyPlayerController's existing input events
// (Fire, Jump, Crouch, Prone, Reload, KeyBoard1/2, Interaction, ShowInventory,
// ...) run unchanged. Camera drag is injected as MouseX / MouseY, exactly what
// the original Turn / LookUp axes already read.

#pragma once

#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "InputCoreTypes.h"
#include "Brushes/SlateImageBrush.h"
#include "Logic/PUBGTouchLayoutDefaults.h"
#include "PUBGTouchInputComponent.generated.h"

class APlayerController;
class UTexture2D;

struct FPUBGTouchControl
{
	FName Id;
	FString Label;
	PUBGLogic::ETouchKind Kind = PUBGLogic::ETouchKind::Tap;
	FVector2D DefaultPosition = FVector2D::ZeroVector;
	FVector2D Position = FVector2D::ZeroVector;   // normalized to the safe area
	float Radius = 40.f;
	float Scale = 1.f;
	bool bDefaultVisible = true;
	bool bVisible = true;

	// runtime
	bool bPressed = false;
	bool bToggledOn = false;
};

UCLASS(ClassGroup = (PUBG))
class PUBG_BLUEPRINT_API UPUBGTouchInputComponent : public UActorComponent
{
	GENERATED_BODY()

public:
	UPUBGTouchInputComponent();

	/** Adds the component to a local player controller if missing. */
	static UPUBGTouchInputComponent* FindOrAdd(APlayerController* PC);

	/** Touch controls are shown on touch devices, or when forced (settings / -ForceTouchUI). */
	static bool ShouldUseTouchControls();

	virtual void BeginPlay() override;
	virtual void EndPlay(const EEndPlayReason::Type EndPlayReason) override;
	virtual void TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction) override;

	// ---- Called by the Slate surface
	void PressControl(int32 Index);
	void ReleaseControl(int32 Index);
	void SetStick(float X, float Y, float Magnitude, bool bSprintGesture);
	void ReleaseStick();
	void AddLookDelta(const FVector2D& Delta);
	void ReleaseAll();

	// ---- Layout
	TArray<FPUBGTouchControl>& GetControls() { return Controls; }
	const TArray<FPUBGTouchControl>& GetControls() const { return Controls; }
	int32 FindControl(FName Id) const;
	void SaveLayout();
	void ResetLayout();
	bool IsEditingLayout() const { return bEditingLayout; }
	void SetEditingLayout(bool bEdit);

	// ---- Presentation
	bool IsInventoryOpen() const;
	bool IsPlayerDead() const;
	bool IsSprintLocked() const { return bSprintLocked; }
	bool IsPickupAvailable() const { return bPickupAvailable; }
	FString GetPickupLabel() const { return PickupLabel; }
	float GetOpacity() const;
	float GetGlobalScale() const;
	bool IsFloatingStick() const;
	/** Closes the original inventory (taps the ShowInventory key). */
	void TapInventory();

	/** Increments every time all input is released; the surface drops its finger tracking then. */
	int32 GetReleaseCounter() const { return ReleaseCounter; }

	const FSlateBrush* GetCircleBrush() const { return &CircleBrush; }
	const FSlateBrush* GetRingBrush() const { return &RingBrush; }

protected:
	UPROPERTY(Transient) UTexture2D* CircleTexture = nullptr;
	UPROPERTY(Transient) UTexture2D* RingTexture = nullptr;

private:
	APlayerController* GetPC() const;
	void BuildControls();
	static UTexture2D* CreateCircleTexture(bool bRing);
	FKey KeyForControl(const FPUBGTouchControl& Control) const;
	void PressKey(const FKey& Key);
	void ReleaseKey(const FKey& Key);
	void TapKey(const FKey& Key);
	void UpdateContext();
	bool IsAimingNow() const;

	TArray<FPUBGTouchControl> Controls;
	TMap<FKey, int32> KeyRefCount;
	TArray<FKey> PendingTapReleases;

	FVector2D Stick = FVector2D::ZeroVector;
	float StickMagnitude = 0.f;
	bool bStickActive = false;
	bool bStickWasActive = false;
	float SprintGestureTime = 0.f;
	bool bSprintGestureActive = false;
	bool bSprintLocked = false;
	bool bAnalogWalkHeld = false;
	FVector2D PendingLook = FVector2D::ZeroVector;

	bool bEditingLayout = false;
	bool bPickupAvailable = false;
	FString PickupLabel;
	float ContextTimer = 0.f;

	FSlateBrush CircleBrush;
	FSlateBrush RingBrush;
	int32 ReleaseCounter = 0;
};
