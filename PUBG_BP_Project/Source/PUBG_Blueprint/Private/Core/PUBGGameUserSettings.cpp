#include "Core/PUBGGameUserSettings.h"

#include "PUBG_Blueprint.h"
#include "Engine/Engine.h"
#include "HAL/IConsoleManager.h"
#include "DeviceProfiles/DeviceProfileManager.h"

UPUBGGameUserSettings::UPUBGGameUserSettings()
{
}

UPUBGGameUserSettings* UPUBGGameUserSettings::GetPUBGSettings()
{
	if (GEngine)
	{
		if (UPUBGGameUserSettings* Settings = Cast<UPUBGGameUserSettings>(GEngine->GetGameUserSettings()))
		{
			return Settings;
		}
	}
	static bool bWarned = false;
	if (!bWarned)
	{
		bWarned = true;
		UE_LOG(LogPUBG, Warning, TEXT("GameUserSettingsClassName is not PUBGGameUserSettings; using the class default object."));
	}
	return GetMutableDefault<UPUBGGameUserSettings>();
}

void UPUBGGameUserSettings::SetToDefaults()
{
	Super::SetToDefaults();
	GraphicsPresetIndex = -1;
	FrameRateCap = 60;
	RenderScale = 1.f;
	bShowFPS = false;
	LookSensitivity = 1.f;
	AimSensitivity = 0.6f;
	bInvertLook = false;
	TouchOpacity = 0.55f;
	TouchScale = 1.f;
	bFloatingJoystick = true;
	bAnalogWalk = true;
	bSprintGesture = true;
	TouchLayout.Reset();
	// Profile (name / character) is intentionally kept.
}

void UPUBGGameUserSettings::EnsureInitialized()
{
	bool bChanged = false;
	if (PlayerDisplayName.IsEmpty())
	{
		PlayerDisplayName = FString::Printf(TEXT("Player%04d"), FMath::RandRange(0, 9999));
		bChanged = true;
	}
	if (GraphicsPresetIndex < 0)
	{
#if PLATFORM_ANDROID || PLATFORM_IOS
		// First run: pick the preset from the engine's device tier (Android_Low / _Mid / _High ...).
		const FString Profile = UDeviceProfileManager::Get().GetActiveProfileName();
		if (Profile.Contains(TEXT("_Low")))
		{
			GraphicsPresetIndex = (int32)EPUBGGraphicsPreset::Low;
		}
		else if (Profile.Contains(TEXT("_High")))
		{
			GraphicsPresetIndex = (int32)EPUBGGraphicsPreset::High;
		}
		else
		{
			GraphicsPresetIndex = (int32)EPUBGGraphicsPreset::Medium;
		}
		FrameRateCap = 30;
		UE_LOG(LogPUBG, Log, TEXT("Device profile %s -> graphics preset %d"), *Profile, GraphicsPresetIndex);
#else
		GraphicsPresetIndex = (int32)EPUBGGraphicsPreset::High;
		FrameRateCap = 60;
#endif
		bChanged = true;
	}
	if (bChanged)
	{
		SaveSettings();
	}
}

void UPUBGGameUserSettings::SetGraphicsPreset(EPUBGGraphicsPreset Preset)
{
	GraphicsPresetIndex = FMath::Clamp<int32>((int32)Preset, 0, 3);
}

EPUBGGraphicsPreset UPUBGGameUserSettings::GetGraphicsPreset() const
{
	return (EPUBGGraphicsPreset)FMath::Clamp<int32>(GraphicsPresetIndex < 0 ? 1 : GraphicsPresetIndex, 0, 3);
}

TArray<int32> UPUBGGameUserSettings::GetSupportedFrameRates()
{
	return { 30, 60, 90, 120 };
}

void UPUBGGameUserSettings::SetFrameRateCap(int32 Fps)
{
	FrameRateCap = FMath::Clamp(Fps, 20, 240);
}

void UPUBGGameUserSettings::SetRenderScale(float Scale)
{
	RenderScale = FMath::Clamp(Scale, 0.5f, 1.f);
}

void UPUBGGameUserSettings::ApplyPUBGSettings()
{
	// Scalability groups (sg.*) — values per level come from Config/DefaultScalability.ini.
	SetOverallScalabilityLevel((int32)GetGraphicsPreset());

	// sg.ResolutionQuality expects a screen percentage. SetResolutionScaleNormalized
	// maps 0..1 to the engine's min..max screen percentage.
	SetResolutionScaleNormalized(FMath::GetMappedRangeValueClamped(FVector2D(0.5f, 1.f), FVector2D(0.f, 1.f), RenderScale));

	// t.MaxFPS (engine-level cap, works on every platform).
	SetFrameRateLimit((float)FrameRateCap);

#if PLATFORM_ANDROID || PLATFORM_IOS
	// On mobile the display sync interval limits the frame rate as well:
	// 1 = every vsync (60/90/120 Hz panels), 2 = every other vsync (30 fps on 60 Hz).
	if (IConsoleVariable* SyncInterval = IConsoleManager::Get().FindConsoleVariable(TEXT("rhi.SyncInterval")))
	{
		SyncInterval->Set(FrameRateCap <= 30 ? 2 : 1, ECVF_SetByGameSetting);
	}
#endif

	ApplySettings(false);
	UE_LOG(LogPUBG, Log, TEXT("Applied settings: preset=%d fps=%d renderScale=%.2f"), GraphicsPresetIndex, FrameRateCap, RenderScale);
}
