// Owns the C++ (Slate) user interface:
//   * main menu  (front-end map)       -> SPUBGMainMenu
//   * lobby      (lobby map)           -> SPUBGLobbyPanel
//   * gameplay   (any other map)       -> SPUBGGameHud + SPUBGTouchControls (touch devices) + in-game menu
// The original Blueprint HUD (MyHUD / MainUI / InventoryUI) keeps running underneath.
// Also applies the saved graphics / FPS settings once at startup.

#pragma once

#include "CoreMinimal.h"
#include "Subsystems/GameInstanceSubsystem.h"
#include "Tickable.h"
#include "PUBGUISubsystem.generated.h"

class APlayerController;
class SWidget;
class UInputComponent;

UCLASS()
class PUBG_BLUEPRINT_API UPUBGUISubsystem : public UGameInstanceSubsystem, public FTickableGameObject
{
	GENERATED_BODY()

public:
	static UPUBGUISubsystem* Get(const UObject* WorldContext);

	virtual void Initialize(FSubsystemCollectionBase& Collection) override;
	virtual void Deinitialize() override;

	// FTickableGameObject
	virtual void Tick(float DeltaTime) override;
	virtual TStatId GetStatId() const override;
	virtual bool IsTickable() const override { return bActive; }
	virtual bool IsTickableWhenPaused() const override { return true; }
	virtual bool IsTickableInEditor() const override { return false; }

	UFUNCTION(BlueprintCallable, Category = "PUBG|UI") void ShowMainMenu(APlayerController* PC);
	UFUNCTION(BlueprintCallable, Category = "PUBG|UI") void ShowLobby(APlayerController* PC);
	UFUNCTION(BlueprintCallable, Category = "PUBG|UI") void ToggleInGameMenu(APlayerController* PC);
	UFUNCTION(BlueprintCallable, Category = "PUBG|UI") void CloseInGameMenu();
	UFUNCTION(BlueprintCallable, Category = "PUBG|UI") void OpenTouchLayoutEditor();
	UFUNCTION(BlueprintPure, Category = "PUBG|UI") bool IsInGameMenuOpen() const { return MenuWidget.IsValid(); }

private:
	void EnsureGameplayUI(APlayerController* PC);
	void ResetForNewController();
	bool AddWidget(APlayerController* PC, const TSharedRef<SWidget>& Widget, int32 ZOrder);
	void RemoveWidget(TSharedPtr<SWidget>& Widget);
	void HandleMenuKey();
	void SetUIInput(APlayerController* PC, const TSharedPtr<SWidget>& Focus, bool bUIOnly);

	bool bActive = false;
	float TickTimer = 0.f;
	TWeakObjectPtr<APlayerController> UIController;
	TWeakObjectPtr<class ULocalPlayer> UIPlayer;
	TSharedPtr<SWidget> ScreenWidget;   // main menu or lobby
	TSharedPtr<SWidget> TouchWidget;
	TSharedPtr<SWidget> HudWidget;
	TSharedPtr<SWidget> MenuWidget;
	TWeakObjectPtr<UInputComponent> MenuInput;
	bool bPausedByMenu = false;
};
