#include "UI/PUBGUISubsystem.h"

#include "PUBG_Blueprint.h"
#include "Core/PUBGGameUserSettings.h"
#include "Lobby/PUBGFrontEndGameMode.h"
#include "Lobby/PUBGLobbyPlayerController.h"
#include "Mobile/PUBGTouchInputComponent.h"
#include "Mobile/SPUBGTouchControls.h"
#include "UI/SPUBGGameHud.h"
#include "UI/SPUBGLobbyPanel.h"
#include "UI/SPUBGMainMenu.h"

#include "Components/InputComponent.h"
#include "Engine/Engine.h"
#include "Engine/GameInstance.h"
#include "Engine/GameViewportClient.h"
#include "Engine/LocalPlayer.h"
#include "Engine/World.h"
#include "Framework/Application/SlateApplication.h"
#include "GameFramework/PlayerController.h"
#include "Kismet/GameplayStatics.h"
#include "Misc/CoreMisc.h"

namespace
{
	constexpr int32 ZOrderTouch = 5;
	constexpr int32 ZOrderHud = 6;
	constexpr int32 ZOrderScreen = 10;
	constexpr int32 ZOrderMenu = 20;
}

UPUBGUISubsystem* UPUBGUISubsystem::Get(const UObject* WorldContext)
{
	const UWorld* World = GEngine ? GEngine->GetWorldFromContextObject(WorldContext, EGetWorldErrorMode::ReturnNull) : nullptr;
	UGameInstance* GameInstance = World ? World->GetGameInstance() : nullptr;
	return GameInstance ? GameInstance->GetSubsystem<UPUBGUISubsystem>() : nullptr;
}

void UPUBGUISubsystem::Initialize(FSubsystemCollectionBase& Collection)
{
	Super::Initialize(Collection);
	bActive = !IsRunningDedicatedServer();
	if (bActive)
	{
		UPUBGGameUserSettings* Settings = UPUBGGameUserSettings::GetPUBGSettings();
		Settings->EnsureInitialized();
		// In the editor (PIE) scalability is shared with the editor viewport: only
		// apply when the player changes a setting, not automatically at startup.
		if (!GIsEditor)
		{
			Settings->ApplyPUBGSettings();
		}
	}
}

void UPUBGUISubsystem::Deinitialize()
{
	bActive = false;
	ResetForNewController();
	Super::Deinitialize();
}

TStatId UPUBGUISubsystem::GetStatId() const
{
	RETURN_QUICK_DECLARE_CYCLE_STAT(UPUBGUISubsystem, STATGROUP_Tickables);
}

bool UPUBGUISubsystem::AddWidget(APlayerController* PC, const TSharedRef<SWidget>& Widget, int32 ZOrder)
{
	UGameViewportClient* Viewport = GetGameInstance() ? GetGameInstance()->GetGameViewportClient() : nullptr;
	ULocalPlayer* LocalPlayer = PC ? PC->GetLocalPlayer() : nullptr;
	if (!Viewport || !LocalPlayer)
	{
		return false;
	}
	Viewport->AddViewportWidgetForPlayer(LocalPlayer, Widget, ZOrder);
	UIPlayer = LocalPlayer;
	return true;
}

void UPUBGUISubsystem::RemoveWidget(TSharedPtr<SWidget>& Widget)
{
	if (!Widget.IsValid())
	{
		return;
	}
	UGameViewportClient* Viewport = GetGameInstance() ? GetGameInstance()->GetGameViewportClient() : nullptr;
	if (Viewport && UIPlayer.IsValid())
	{
		Viewport->RemoveViewportWidgetForPlayer(UIPlayer.Get(), Widget.ToSharedRef());
	}
	Widget.Reset();
}

void UPUBGUISubsystem::ResetForNewController()
{
	// After a map change the viewport already dropped our widgets; just forget them.
	RemoveWidget(MenuWidget);
	RemoveWidget(HudWidget);
	RemoveWidget(TouchWidget);
	RemoveWidget(ScreenWidget);
	if (UIController.IsValid() && MenuInput.IsValid())
	{
		UIController->PopInputComponent(MenuInput.Get());
	}
	MenuInput.Reset();
	UIController.Reset();
	bPausedByMenu = false;
}

void UPUBGUISubsystem::SetUIInput(APlayerController* PC, const TSharedPtr<SWidget>& Focus, bool bUIOnly)
{
	if (!PC)
	{
		return;
	}
	if (bUIOnly)
	{
		FInputModeUIOnly Mode;
		if (Focus.IsValid())
		{
			Mode.SetWidgetToFocus(Focus);
		}
		Mode.SetLockMouseToViewportBehavior(EMouseLockMode::DoNotLock);
		PC->SetInputMode(Mode);
		PC->bShowMouseCursor = true;
	}
	else
	{
		PC->SetInputMode(FInputModeGameOnly());
		PC->bShowMouseCursor = false;
	}
}

void UPUBGUISubsystem::ShowMainMenu(APlayerController* PC)
{
	if (!bActive || !PC)
	{
		return;
	}
	ResetForNewController();
	UIController = PC;
	TSharedRef<SPUBGMainMenu> Menu = SNew(SPUBGMainMenu).OwnerPC(PC);
	ScreenWidget = Menu;
	AddWidget(PC, Menu, ZOrderScreen);
	SetUIInput(PC, Menu, true);
}

void UPUBGUISubsystem::ShowLobby(APlayerController* PC)
{
	APUBGLobbyPlayerController* LobbyPC = Cast<APUBGLobbyPlayerController>(PC);
	if (!bActive || !LobbyPC)
	{
		return;
	}
	ResetForNewController();
	UIController = PC;
	TSharedRef<SPUBGLobbyPanel> Panel = SNew(SPUBGLobbyPanel).OwnerPC(LobbyPC);
	ScreenWidget = Panel;
	AddWidget(PC, Panel, ZOrderScreen);
	SetUIInput(PC, Panel, true);
}

void UPUBGUISubsystem::Tick(float DeltaTime)
{
	TickTimer -= DeltaTime;
	if (TickTimer > 0.f)
	{
		return;
	}
	TickTimer = 0.25f;

	UGameInstance* GameInstance = GetGameInstance();
	UWorld* World = GameInstance ? GameInstance->GetWorld() : nullptr;
	APlayerController* PC = World ? GameInstance->GetFirstLocalPlayerController(World) : nullptr;
	if (!PC)
	{
		return;
	}
	if (UIController.Get() != PC)
	{
		// New map / new controller: widgets of the previous one are gone.
		MenuWidget.Reset();
		HudWidget.Reset();
		TouchWidget.Reset();
		ScreenWidget.Reset();
		MenuInput.Reset();
		UIController.Reset();
		bPausedByMenu = false;
	}
	// Menu and lobby controllers create their screens themselves (BeginPlay).
	if (PC->IsA<APUBGFrontEndPlayerController>() || PC->IsA<APUBGLobbyPlayerController>())
	{
		return;
	}
	if (!HudWidget.IsValid() && PC->GetPawn())
	{
		EnsureGameplayUI(PC);
	}
}

void UPUBGUISubsystem::EnsureGameplayUI(APlayerController* PC)
{
	UIController = PC;
	if (UPUBGTouchInputComponent::ShouldUseTouchControls())
	{
		UPUBGTouchInputComponent* Touch = UPUBGTouchInputComponent::FindOrAdd(PC);
		TSharedRef<SPUBGTouchControls> Controls = SNew(SPUBGTouchControls).Input(Touch);
		TouchWidget = Controls;
		AddWidget(PC, Controls, ZOrderTouch);
	}
	TSharedRef<SPUBGGameHud> Hud = SNew(SPUBGGameHud).OwnerPC(PC);
	HudWidget = Hud;
	AddWidget(PC, Hud, ZOrderHud);

	// Esc / F10 open the in-game menu with keyboard (touch devices use the MENU button).
	UInputComponent* Input = NewObject<UInputComponent>(PC, TEXT("PUBGMenuInput"));
	Input->RegisterComponent();
	Input->bBlockInput = false;
	FInputKeyBinding& Esc = Input->BindKey(EKeys::Escape, IE_Pressed, this, &UPUBGUISubsystem::HandleMenuKey);
	Esc.bConsumeInput = false;
	FInputKeyBinding& F10 = Input->BindKey(EKeys::F10, IE_Pressed, this, &UPUBGUISubsystem::HandleMenuKey);
	F10.bConsumeInput = false;
	PC->PushInputComponent(Input);
	MenuInput = Input;
	UE_LOG(LogPUBG, Log, TEXT("Gameplay UI created (touch controls: %s)."), TouchWidget.IsValid() ? TEXT("yes") : TEXT("no"));
}

void UPUBGUISubsystem::HandleMenuKey()
{
	ToggleInGameMenu(UIController.Get());
}

void UPUBGUISubsystem::ToggleInGameMenu(APlayerController* PC)
{
	if (MenuWidget.IsValid())
	{
		CloseInGameMenu();
		return;
	}
	if (!PC)
	{
		return;
	}
	if (UPUBGTouchInputComponent* Touch = PC->FindComponentByClass<UPUBGTouchInputComponent>())
	{
		Touch->ReleaseAll();
	}
	TSharedRef<SPUBGInGameMenu> Menu = SNew(SPUBGInGameMenu).OwnerPC(PC);
	MenuWidget = Menu;
	AddWidget(PC, Menu, ZOrderMenu);
	SetUIInput(PC, Menu, true);
	if (PC->GetNetMode() == NM_Standalone)
	{
		bPausedByMenu = UGameplayStatics::SetGamePaused(PC, true);
	}
}

void UPUBGUISubsystem::CloseInGameMenu()
{
	RemoveWidget(MenuWidget);
	APlayerController* PC = UIController.Get();
	if (!PC)
	{
		return;
	}
	if (bPausedByMenu)
	{
		UGameplayStatics::SetGamePaused(PC, false);
		bPausedByMenu = false;
	}
	SetUIInput(PC, nullptr, false);
}

void UPUBGUISubsystem::OpenTouchLayoutEditor()
{
	CloseInGameMenu();
	if (APlayerController* PC = UIController.Get())
	{
		if (UPUBGTouchInputComponent* Touch = PC->FindComponentByClass<UPUBGTouchInputComponent>())
		{
			Touch->SetEditingLayout(true);
		}
	}
}
