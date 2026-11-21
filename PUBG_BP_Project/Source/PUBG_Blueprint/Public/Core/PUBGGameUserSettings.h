// Per-player settings saved in GameUserSettings.ini (graphics, FPS, controls,
// touch layout, profile). Registered through DefaultEngine.ini:
//   [/Script/Engine.Engine] GameUserSettingsClassName=/Script/PUBG_Blueprint.PUBGGameUserSettings

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameUserSettings.h"
#include "Core/PUBGTypes.h"
#include "PUBGGameUserSettings.generated.h"

UCLASS(config = GameUserSettings, configdonotcheckdefaults)
class PUBG_BLUEPRINT_API UPUBGGameUserSettings : public UGameUserSettings
{
	GENERATED_BODY()

public:
	UPUBGGameUserSettings();

	/** Never null: falls back to the class default object if the engine uses another settings class. */
	UFUNCTION(BlueprintPure, Category = "PUBG|Settings")
	static UPUBGGameUserSettings* GetPUBGSettings();

	/** Fills first-run defaults (random display name, graphics preset by platform). */
	void EnsureInitialized();

	virtual void SetToDefaults() override;

	// ------------------------------------------------------------ Graphics
	UFUNCTION(BlueprintCallable, Category = "PUBG|Settings") void SetGraphicsPreset(EPUBGGraphicsPreset Preset);
	UFUNCTION(BlueprintPure, Category = "PUBG|Settings") EPUBGGraphicsPreset GetGraphicsPreset() const;
	UFUNCTION(BlueprintCallable, Category = "PUBG|Settings") void SetFrameRateCap(int32 Fps);
	UFUNCTION(BlueprintPure, Category = "PUBG|Settings") int32 GetFrameRateCap() const { return FrameRateCap; }
	/** 0.5 .. 1.0 of native resolution. */
	UFUNCTION(BlueprintCallable, Category = "PUBG|Settings") void SetRenderScale(float Scale);
	UFUNCTION(BlueprintPure, Category = "PUBG|Settings") float GetRenderScale() const { return RenderScale; }

	/** Applies preset, render scale and FPS cap to the running game, then saves. */
	UFUNCTION(BlueprintCallable, Category = "PUBG|Settings") void ApplyPUBGSettings();

	static TArray<int32> GetSupportedFrameRates();

	// ------------------------------------------------------------ Profile
	UPROPERTY(config, BlueprintReadWrite, Category = "PUBG|Profile") FString PlayerDisplayName;
	UPROPERTY(config, BlueprintReadWrite, Category = "PUBG|Profile") int32 SelectedCharacter = 0;

	// ------------------------------------------------------------ Display
	UPROPERTY(config, BlueprintReadWrite, Category = "PUBG|Display") bool bShowFPS = false;

	// ------------------------------------------------------------ Controls
	UPROPERTY(config, BlueprintReadWrite, Category = "PUBG|Controls") float LookSensitivity = 1.f;
	UPROPERTY(config, BlueprintReadWrite, Category = "PUBG|Controls") float AimSensitivity = 0.6f;
	UPROPERTY(config, BlueprintReadWrite, Category = "PUBG|Controls") bool bInvertLook = false;
	UPROPERTY(config, BlueprintReadWrite, Category = "PUBG|Controls") float TouchOpacity = 0.55f;
	UPROPERTY(config, BlueprintReadWrite, Category = "PUBG|Controls") float TouchScale = 1.f;
	/** Joystick re-centres under the finger anywhere in the left zone. */
	UPROPERTY(config, BlueprintReadWrite, Category = "PUBG|Controls") bool bFloatingJoystick = true;
	/** Small stick deflection walks (injects the original "Walk" action). */
	UPROPERTY(config, BlueprintReadWrite, Category = "PUBG|Controls") bool bAnalogWalk = true;
	/** Push the stick far up to lock sprint. */
	UPROPERTY(config, BlueprintReadWrite, Category = "PUBG|Controls") bool bSprintGesture = true;
	/** Custom positions; controls missing from this list use the defaults. */
	UPROPERTY(config, BlueprintReadWrite, Category = "PUBG|Controls") TArray<FPUBGTouchControlLayout> TouchLayout;

protected:
	UPROPERTY(config) int32 GraphicsPresetIndex = -1;
	UPROPERTY(config) int32 FrameRateCap = 60;
	UPROPERTY(config) float RenderScale = 1.f;
};
