#include "Mobile/PUBGTouchInputComponent.h"

#include "PUBG_Blueprint.h"
#include "Core/PUBGBlueprintBridge.h"
#include "Core/PUBGGameUserSettings.h"
#include "Core/PUBGSettings.h"
#include "Mobile/PUBGTouchKeys.h"
#include "Network/PUBGHealthComponent.h"
#include "UI/PUBGUISubsystem.h"

#include "Blueprint/UserWidget.h"
#include "Engine/Texture2D.h"
#include "GameFramework/InputSettings.h"
#include "GameFramework/Pawn.h"
#include "GameFramework/PlayerController.h"
#include "GameFramework/PlayerState.h"
#include "HAL/PlatformMisc.h"
#include "Logic/PUBGNetLogic.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"

namespace
{
	/** Slate units -> mouse counts. The original MouseX/MouseY axes then apply their 0.07 sensitivity. */
	constexpr float LookBaseScale = 1.5f;
	constexpr float AnalogWalkThreshold = 0.5f;
	constexpr float SprintGestureHoldSeconds = 0.5f;
}

UPUBGTouchInputComponent::UPUBGTouchInputComponent()
{
	PrimaryComponentTick.bCanEverTick = true;
	SetIsReplicatedByDefault(false);
}

UPUBGTouchInputComponent* UPUBGTouchInputComponent::FindOrAdd(APlayerController* PC)
{
	if (!PC)
	{
		return nullptr;
	}
	if (UPUBGTouchInputComponent* Existing = PC->FindComponentByClass<UPUBGTouchInputComponent>())
	{
		return Existing;
	}
	UPUBGTouchInputComponent* Component = NewObject<UPUBGTouchInputComponent>(PC, TEXT("PUBGTouchInput"));
	Component->RegisterComponent();
	return Component;
}

bool UPUBGTouchInputComponent::ShouldUseTouchControls()
{
	return FPlatformMisc::SupportsTouchInput() || GetDefault<UInputSettings>()->bAlwaysShowTouchInterface ||
		UPUBGSettings::Get()->bForceTouchControls || FParse::Param(FCommandLine::Get(), TEXT("ForceTouchUI"));
}

APlayerController* UPUBGTouchInputComponent::GetPC() const
{
	return Cast<APlayerController>(GetOwner());
}

void UPUBGTouchInputComponent::BeginPlay()
{
	Super::BeginPlay();
	BuildControls();

	CircleTexture = CreateCircleTexture(false);
	RingTexture = CreateCircleTexture(true);
	CircleBrush.SetResourceObject(CircleTexture);
	CircleBrush.ImageSize = FVector2D(128.f, 128.f);
	CircleBrush.DrawAs = ESlateBrushDrawType::Image;
	RingBrush.SetResourceObject(RingTexture);
	RingBrush.ImageSize = FVector2D(128.f, 128.f);
	RingBrush.DrawAs = ESlateBrushDrawType::Image;

	if (APlayerController* PC = GetPC())
	{
		// Our controls replace the engine's default virtual joysticks.
		PC->ActivateTouchInterface(nullptr);
	}
}

void UPUBGTouchInputComponent::EndPlay(const EEndPlayReason::Type EndPlayReason)
{
	ReleaseAll();
	Super::EndPlay(EndPlayReason);
}

UTexture2D* UPUBGTouchInputComponent::CreateCircleTexture(bool bRing)
{
	const int32 Size = 128;
	UTexture2D* Texture = UTexture2D::CreateTransient(Size, Size, PF_B8G8R8A8);
	FTexturePlatformData* PlatformData = Texture ? Texture->GetPlatformData() : nullptr;
	if (!PlatformData || PlatformData->Mips.Num() == 0)
	{
		return nullptr;
	}
	Texture->SRGB = true;
	Texture->Filter = TF_Bilinear;
	FTexture2DMipMap& Mip = PlatformData->Mips[0];
	uint8* Pixels = static_cast<uint8*>(Mip.BulkData.Lock(LOCK_READ_WRITE));
	const float Center = Size * 0.5f;
	const float Outer = Center - 1.5f;
	const float Thickness = 5.f;
	for (int32 Y = 0; Y < Size; ++Y)
	{
		for (int32 X = 0; X < Size; ++X)
		{
			const float DX = X + 0.5f - Center, DY = Y + 0.5f - Center;
			const float Dist = FMath::Sqrt(DX * DX + DY * DY);
			float Alpha;
			if (bRing)
			{
				// anti-aliased ring of the given thickness at the outer edge
				const float Mid = Outer - Thickness * 0.5f;
				Alpha = FMath::Clamp(Thickness * 0.5f + 0.75f - FMath::Abs(Dist - Mid), 0.f, 1.f);
			}
			else
			{
				Alpha = FMath::Clamp(Outer - Dist + 0.5f, 0.f, 1.f);
			}
			uint8* P = Pixels + (Y * Size + X) * 4;
			P[0] = 255; // B
			P[1] = 255; // G
			P[2] = 255; // R
			P[3] = (uint8)FMath::RoundToInt(Alpha * 255.f);
		}
	}
	Mip.BulkData.Unlock();
	Texture->UpdateResource();
	return Texture;
}

void UPUBGTouchInputComponent::BuildControls()
{
	Controls.Reset();
	for (int32 i = 0; i < PUBGLogic::GTouchDefaultsCount; ++i)
	{
		const PUBGLogic::FTouchControlDefault& Def = PUBGLogic::GTouchDefaults[i];
		FPUBGTouchControl Control;
		Control.Id = FName(Def.Id);
		Control.Label = Def.Label;
		Control.Kind = Def.Kind;
		Control.DefaultPosition = FVector2D(Def.NX, Def.NY);
		Control.Position = Control.DefaultPosition;
		Control.Radius = Def.Radius;
		Control.bDefaultVisible = Def.bVisible;
		Control.bVisible = Def.bVisible;
		Controls.Add(Control);
	}
	for (const FPUBGTouchControlLayout& Saved : UPUBGGameUserSettings::GetPUBGSettings()->TouchLayout)
	{
		const int32 Index = FindControl(Saved.Id);
		if (Controls.IsValidIndex(Index))
		{
			Controls[Index].Position = FVector2D(FMath::Clamp(Saved.Position.X, 0.f, 1.f), FMath::Clamp(Saved.Position.Y, 0.f, 1.f));
			Controls[Index].Scale = FMath::Clamp(Saved.Scale, 0.5f, 2.f);
			Controls[Index].bVisible = Saved.bVisible;
		}
	}
}

int32 UPUBGTouchInputComponent::FindControl(FName Id) const
{
	return Controls.IndexOfByPredicate([Id](const FPUBGTouchControl& C) { return C.Id == Id; });
}

void UPUBGTouchInputComponent::SaveLayout()
{
	UPUBGGameUserSettings* Settings = UPUBGGameUserSettings::GetPUBGSettings();
	Settings->TouchLayout.Reset();
	for (const FPUBGTouchControl& Control : Controls)
	{
		FPUBGTouchControlLayout Saved;
		Saved.Id = Control.Id;
		Saved.Position = Control.Position;
		Saved.Scale = Control.Scale;
		Saved.bVisible = Control.bVisible;
		Settings->TouchLayout.Add(Saved);
	}
	Settings->SaveSettings();
}

void UPUBGTouchInputComponent::ResetLayout()
{
	for (FPUBGTouchControl& Control : Controls)
	{
		Control.Position = Control.DefaultPosition;
		Control.Scale = 1.f;
		Control.bVisible = Control.bDefaultVisible;
	}
	UPUBGGameUserSettings* Settings = UPUBGGameUserSettings::GetPUBGSettings();
	Settings->TouchLayout.Reset();
	Settings->SaveSettings();
}

void UPUBGTouchInputComponent::SetEditingLayout(bool bEdit)
{
	ReleaseAll();
	bEditingLayout = bEdit;
	if (!bEdit)
	{
		SaveLayout();
	}
}

float UPUBGTouchInputComponent::GetOpacity() const
{
	return FMath::Clamp(UPUBGGameUserSettings::GetPUBGSettings()->TouchOpacity, 0.15f, 1.f);
}

float UPUBGTouchInputComponent::GetGlobalScale() const
{
	return FMath::Clamp(UPUBGGameUserSettings::GetPUBGSettings()->TouchScale, 0.6f, 1.6f);
}

bool UPUBGTouchInputComponent::IsFloatingStick() const
{
	return UPUBGGameUserSettings::GetPUBGSettings()->bFloatingJoystick;
}

bool UPUBGTouchInputComponent::IsInventoryOpen() const
{
	const UUserWidget* Inventory = Cast<UUserWidget>(PUBGBridge::GetObject(GetPC(), UPUBGSettings::Get()->BlueprintNames.InventoryUI));
	return Inventory && Inventory->IsInViewport();
}

bool UPUBGTouchInputComponent::IsPlayerDead() const
{
	const APlayerController* PC = GetPC();
	const UPUBGHealthComponent* Health = PC ? UPUBGHealthComponent::Find(PC->GetPawn()) : nullptr;
	return Health && Health->IsDead();
}

bool UPUBGTouchInputComponent::IsAimingNow() const
{
	const APlayerController* PC = GetPC();
	const APawn* Pawn = PC ? PC->GetPawn() : nullptr;
	if (!Pawn)
	{
		return false;
	}
	const FPUBGBlueprintNames& Names = UPUBGSettings::Get()->BlueprintNames;
	bool bAiming = false, bSight = false;
	PUBGBridge::GetBool(Pawn, Names.IsAiming, bAiming);
	PUBGBridge::GetBool(Pawn, Names.IsSightAiming, bSight);
	return bAiming || bSight;
}

FKey UPUBGTouchInputComponent::KeyForControl(const FPUBGTouchControl& Control) const
{
	static const TMap<FName, FKey> Map = {
		{ TEXT("Fire"), PUBGTouchKeys::Fire },
		{ TEXT("FireLeft"), PUBGTouchKeys::Fire },
		{ TEXT("ADS"), PUBGTouchKeys::Aim },
		{ TEXT("Scope"), PUBGTouchKeys::Aim },
		{ TEXT("Jump"), PUBGTouchKeys::Jump },
		{ TEXT("Crouch"), PUBGTouchKeys::Crouch },
		{ TEXT("Prone"), PUBGTouchKeys::Prone },
		{ TEXT("Sprint"), PUBGTouchKeys::Sprint },
		{ TEXT("Walk"), PUBGTouchKeys::Walk },
		{ TEXT("Reload"), PUBGTouchKeys::Reload },
		{ TEXT("Weapon1"), PUBGTouchKeys::Weapon1 },
		{ TEXT("Weapon2"), PUBGTouchKeys::Weapon2 },
		{ TEXT("Inventory"), PUBGTouchKeys::Inventory },
		{ TEXT("Pickup"), PUBGTouchKeys::Interact },
		{ TEXT("Interact"), PUBGTouchKeys::Interact },
		{ TEXT("FireMode"), PUBGTouchKeys::FireMode },
		{ TEXT("Holster"), PUBGTouchKeys::Holster },
		{ TEXT("Drop"), PUBGTouchKeys::Drop },
		{ TEXT("FreeLook"), PUBGTouchKeys::FreeLook },
	};
	const FKey* Found = Map.Find(Control.Id);
	return Found ? *Found : EKeys::Invalid;
}

void UPUBGTouchInputComponent::PressKey(const FKey& Key)
{
	APlayerController* PC = GetPC();
	if (!PC || !Key.IsValid())
	{
		return;
	}
	int32& Count = KeyRefCount.FindOrAdd(Key);
	if (Count++ == 0)
	{
		PC->InputKey(Key, IE_Pressed, 1.f, true);
	}
}

void UPUBGTouchInputComponent::ReleaseKey(const FKey& Key)
{
	APlayerController* PC = GetPC();
	int32* Count = KeyRefCount.Find(Key);
	if (!PC || !Count || *Count <= 0)
	{
		return;
	}
	if (--(*Count) == 0)
	{
		PC->InputKey(Key, IE_Released, 0.f, true);
	}
}

void UPUBGTouchInputComponent::TapKey(const FKey& Key)
{
	PressKey(Key);
	PendingTapReleases.Add(Key); // released next tick so the press is processed first
}

void UPUBGTouchInputComponent::TapInventory()
{
	TapKey(PUBGTouchKeys::Inventory);
}

void UPUBGTouchInputComponent::PressControl(int32 Index)
{
	if (!Controls.IsValidIndex(Index) || bEditingLayout)
	{
		return;
	}
	FPUBGTouchControl& Control = Controls[Index];
	Control.bPressed = true;

	if (Control.Id == TEXT("Menu"))
	{
		ReleaseAll();
		if (UPUBGUISubsystem* UI = UPUBGUISubsystem::Get(this))
		{
			UI->ToggleInGameMenu(GetPC());
		}
		return;
	}
	if (IsPlayerDead())
	{
		return;
	}
	if (Control.Id == TEXT("Switch"))
	{
		// Cycle between the two weapon slots, using the Blueprint's own state.
		const APlayerController* PC = GetPC();
		const APlayerState* PS = PC ? PC->PlayerState : nullptr;
		const FPUBGBlueprintNames& Names = UPUBGSettings::Get()->BlueprintNames;
		const UObject* W1 = PUBGBridge::GetObject(PS, Names.Weapon1);
		const UObject* W2 = PUBGBridge::GetObject(PS, Names.Weapon2);
		const UObject* Hold = PUBGBridge::GetObject(PS, Names.HoldGun);
		const bool bHoldingFirst = Hold && Hold == W1;
		TapKey((bHoldingFirst && W2) || (!W1 && W2) ? PUBGTouchKeys::Weapon2 : PUBGTouchKeys::Weapon1);
		return;
	}

	const FKey Key = KeyForControl(Control);
	switch (Control.Kind)
	{
	case PUBGLogic::ETouchKind::Hold:
		PressKey(Key);
		break;
	case PUBGLogic::ETouchKind::Tap:
		if (Control.Id == TEXT("Scope"))
		{
			TapKey(Key); // a quick right-click opens the sight in the original controls
		}
		else
		{
			PressKey(Key); // released when the finger lifts, like a real key
		}
		break;
	case PUBGLogic::ETouchKind::Toggle:
		Control.bToggledOn = !Control.bToggledOn;
		if (Control.Id == TEXT("Sprint"))
		{
			bSprintLocked = Control.bToggledOn;
		}
		if (Control.bToggledOn)
		{
			PressKey(Key);
		}
		else
		{
			ReleaseKey(Key);
		}
		break;
	default:
		break;
	}
}

void UPUBGTouchInputComponent::ReleaseControl(int32 Index)
{
	if (!Controls.IsValidIndex(Index))
	{
		return;
	}
	FPUBGTouchControl& Control = Controls[Index];
	if (!Control.bPressed)
	{
		return;
	}
	Control.bPressed = false;
	if (Control.Id == TEXT("Menu") || Control.Id == TEXT("Switch") || Control.Id == TEXT("Scope") || Control.Kind == PUBGLogic::ETouchKind::Toggle)
	{
		return;
	}
	ReleaseKey(KeyForControl(Control));
}

void UPUBGTouchInputComponent::SetStick(float X, float Y, float Magnitude, bool bSprintGesture)
{
	Stick = FVector2D(X, Y);
	StickMagnitude = Magnitude;
	bStickActive = true;
	bSprintGestureActive = bSprintGesture && UPUBGGameUserSettings::GetPUBGSettings()->bSprintGesture;
}

void UPUBGTouchInputComponent::ReleaseStick()
{
	bStickActive = false;
	Stick = FVector2D::ZeroVector;
	StickMagnitude = 0.f;
	SprintGestureTime = 0.f;
	bSprintGestureActive = false;
}

void UPUBGTouchInputComponent::AddLookDelta(const FVector2D& Delta)
{
	if (!bEditingLayout)
	{
		PendingLook += Delta;
	}
}

void UPUBGTouchInputComponent::ReleaseAll()
{
	APlayerController* PC = GetPC();
	if (PC)
	{
		for (const TPair<FKey, int32>& Pair : KeyRefCount)
		{
			if (Pair.Value > 0)
			{
				PC->InputKey(Pair.Key, IE_Released, 0.f, true);
			}
		}
		if (bStickWasActive)
		{
			PC->InputAxis(PUBGTouchKeys::MoveX, 0.f, 0.f, 1, true);
			PC->InputAxis(PUBGTouchKeys::MoveY, 0.f, 0.f, 1, true);
		}
	}
	KeyRefCount.Reset();
	PendingTapReleases.Reset();
	for (FPUBGTouchControl& Control : Controls)
	{
		Control.bPressed = false;
		Control.bToggledOn = false;
	}
	ReleaseStick();
	bStickWasActive = false;
	bSprintLocked = false;
	bAnalogWalkHeld = false;
	PendingLook = FVector2D::ZeroVector;
	++ReleaseCounter;
}

void UPUBGTouchInputComponent::UpdateContext()
{
	const APlayerController* PC = GetPC();
	const FPUBGBlueprintNames& Names = UPUBGSettings::Get()->BlueprintNames;
	TArray<UObject*> InRange;
	bPickupAvailable = PUBGBridge::GetObjectArray(PC, Names.ItemsInRange, InRange) && InRange.Num() > 0;
	PickupLabel.Reset();
	if (bPickupAvailable)
	{
		FText Name;
		if (const UObject* Ready = PUBGBridge::GetObject(PC, Names.ReadyPickupItem))
		{
			if (PUBGBridge::GetText(Ready, TEXT("Name"), Name))
			{
				PickupLabel = Name.ToString().Left(14);
			}
		}
	}
}

void UPUBGTouchInputComponent::TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction)
{
	Super::TickComponent(DeltaTime, TickType, ThisTickFunction);
	APlayerController* PC = GetPC();
	if (!PC || !PC->IsLocalController())
	{
		return;
	}

	// Taps pressed last frame are released now.
	if (PendingTapReleases.Num() > 0)
	{
		TArray<FKey> ToRelease = MoveTemp(PendingTapReleases);
		PendingTapReleases.Reset();
		for (const FKey& Key : ToRelease)
		{
			ReleaseKey(Key);
		}
	}

	ContextTimer -= DeltaTime;
	if (ContextTimer <= 0.f)
	{
		ContextTimer = 0.2f;
		UpdateContext();
		if ((IsInventoryOpen() || IsPlayerDead()) && (bStickActive || KeyRefCount.Num() > 0))
		{
			ReleaseAll(); // never leave keys stuck while the controls are hidden
		}
	}

	const UPUBGGameUserSettings* Settings = UPUBGGameUserSettings::GetPUBGSettings();

	// Movement stick
	if (bStickActive)
	{
		PC->InputAxis(PUBGTouchKeys::MoveX, Stick.X, DeltaTime, 1, true);
		PC->InputAxis(PUBGTouchKeys::MoveY, Stick.Y, DeltaTime, 1, true);
		bStickWasActive = true;

		// Sprint lock gesture (stick pushed far up and held)
		if (bSprintGestureActive)
		{
			SprintGestureTime += DeltaTime;
			if (SprintGestureTime >= SprintGestureHoldSeconds && !bSprintLocked)
			{
				const int32 SprintIndex = FindControl(TEXT("Sprint"));
				if (Controls.IsValidIndex(SprintIndex))
				{
					Controls[SprintIndex].bToggledOn = true;
				}
				bSprintLocked = true;
				PressKey(PUBGTouchKeys::Sprint);
			}
		}
		else
		{
			SprintGestureTime = 0.f;
		}

		// Small deflection = walk (original "Walk" action)
		const bool bWantWalk = Settings->bAnalogWalk && !bSprintLocked && StickMagnitude > 0.f && StickMagnitude < AnalogWalkThreshold;
		if (bWantWalk != bAnalogWalkHeld)
		{
			bAnalogWalkHeld = bWantWalk;
			bWantWalk ? PressKey(PUBGTouchKeys::Walk) : ReleaseKey(PUBGTouchKeys::Walk);
		}
	}
	else if (bStickWasActive)
	{
		PC->InputAxis(PUBGTouchKeys::MoveX, 0.f, DeltaTime, 1, true);
		PC->InputAxis(PUBGTouchKeys::MoveY, 0.f, DeltaTime, 1, true);
		bStickWasActive = false;
		if (bAnalogWalkHeld)
		{
			bAnalogWalkHeld = false;
			ReleaseKey(PUBGTouchKeys::Walk);
		}
		if (bSprintLocked)
		{
			// Letting go of the stick ends sprint, as in most mobile shooters.
			bSprintLocked = false;
			const int32 SprintIndex = FindControl(TEXT("Sprint"));
			if (Controls.IsValidIndex(SprintIndex))
			{
				Controls[SprintIndex].bToggledOn = false;
			}
			ReleaseKey(PUBGTouchKeys::Sprint);
		}
	}

	// Camera look
	if (!PendingLook.IsNearlyZero())
	{
		const float Scale = LookBaseScale * PUBGLogic::LookScale(FMath::Clamp(Settings->LookSensitivity, 0.1f, 5.f), IsAimingNow(), FMath::Clamp(Settings->AimSensitivity, 0.1f, 2.f));
		const float InvertY = Settings->bInvertLook ? -1.f : 1.f;
		PC->InputAxis(EKeys::MouseX, PendingLook.X * Scale, DeltaTime, 1, false);
		PC->InputAxis(EKeys::MouseY, -PendingLook.Y * Scale * InvertY, DeltaTime, 1, false);
		PendingLook = FVector2D::ZeroVector;
	}
}
