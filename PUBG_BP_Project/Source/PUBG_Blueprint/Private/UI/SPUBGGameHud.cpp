#include "UI/SPUBGGameHud.h"

#include "Core/PUBGGameUserSettings.h"
#include "Mobile/PUBGTouchInputComponent.h"
#include "Network/PUBGCombatComponent.h"
#include "Network/PUBGHealthComponent.h"
#include "Network/PUBGMatchStateComponent.h"
#include "Network/PUBGPlayerNetComponent.h"
#include "Network/PUBGPlayerProfileComponent.h"
#include "Sessions/PUBGSessionSubsystem.h"
#include "UI/PUBGUIStyle.h"
#include "UI/PUBGUISubsystem.h"
#include "UI/SPUBGSettingsPanel.h"

#include "Engine/World.h"
#include "EngineUtils.h"
#include "GameFramework/GameStateBase.h"
#include "GameFramework/Pawn.h"
#include "GameFramework/PlayerController.h"
#include "GameFramework/PlayerState.h"
#include "Kismet/KismetSystemLibrary.h"
#include "Widgets/Layout/SBorder.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/Layout/SSafeZone.h"
#include "Widgets/Layout/SWidgetSwitcher.h"
#include "Widgets/SBoxPanel.h"
#include "Widgets/SOverlay.h"
#include "Widgets/Text/STextBlock.h"

#define LOCTEXT_NAMESPACE "PUBGHud"

// ---------------------------------------------------------------------------
// SPUBGGameHud
// ---------------------------------------------------------------------------

APawn* SPUBGGameHud::GetPawn() const
{
	return OwnerPC.IsValid() ? OwnerPC->GetPawn() : nullptr;
}

void SPUBGGameHud::Construct(const FArguments& InArgs)
{
	OwnerPC = InArgs._OwnerPC;
	SetVisibility(EVisibility::SelfHitTestInvisible);

	TSharedRef<SVerticalBox> KillFeed = SNew(SVerticalBox);
	for (int32 i = 0; i < 5; ++i)
	{
		KillFeed->AddSlot().AutoHeight().HAlign(HAlign_Right)
		[
			SNew(STextBlock)
			.Text(this, &SPUBGGameHud::GetKillFeedLine, i)
			.Font(PUBGUI::Font(16, true))
			.ColorAndOpacity(FSlateColor(PUBGUI::TextColor()))
			.ShadowOffset(FVector2D(1.f, 1.f))
		];
	}

	ChildSlot
	[
		SNew(SOverlay)
		.Visibility(EVisibility::SelfHitTestInvisible)
		// Damage flash
		+ SOverlay::Slot()
		[
			SNew(SBorder)
			.Visibility(EVisibility::HitTestInvisible)
			.BorderImage(PUBGUI::WhiteBrush())
			.BorderBackgroundColor(this, &SPUBGGameHud::GetDamageFlashColor)
		]
		+ SOverlay::Slot()
		[
			SNew(SSafeZone)
			.IsTitleSafe(true)
			.Visibility(EVisibility::SelfHitTestInvisible)
			[
				SNew(SOverlay)
				.Visibility(EVisibility::SelfHitTestInvisible)
				// Ping / FPS (top-left, right of the MENU button)
				+ SOverlay::Slot().HAlign(HAlign_Left).VAlign(VAlign_Top).Padding(FMargin(110.f, 18.f, 0.f, 0.f))
				[
					SNew(STextBlock).Visibility(EVisibility::HitTestInvisible)
					.Text(this, &SPUBGGameHud::GetTopLeftText)
					.Font(PUBGUI::Font(14, false))
					.ColorAndOpacity(FSlateColor(PUBGUI::Muted()))
					.ShadowOffset(FVector2D(1.f, 1.f))
				]
				// Alive / kills / match status (top-centre)
				+ SOverlay::Slot().HAlign(HAlign_Center).VAlign(VAlign_Top).Padding(FMargin(0.f, 16.f, 0.f, 0.f))
				[
					SNew(SVerticalBox).Visibility(EVisibility::HitTestInvisible)
					+ SVerticalBox::Slot().AutoHeight().HAlign(HAlign_Center)
					[
						SNew(STextBlock).Text(this, &SPUBGGameHud::GetStatusText).Font(PUBGUI::Font(20, true))
						.ColorAndOpacity(FSlateColor(PUBGUI::TextColor())).ShadowOffset(FVector2D(1.f, 1.f))
					]
					+ SVerticalBox::Slot().AutoHeight().HAlign(HAlign_Center).Padding(0.f, 8.f)
					[
						SNew(STextBlock).Text(this, &SPUBGGameHud::GetNoticeText).Font(PUBGUI::Font(16, false))
						.ColorAndOpacity(FSlateColor(PUBGUI::Accent())).ShadowOffset(FVector2D(1.f, 1.f))
					]
				]
				// Kill feed (top-right)
				+ SOverlay::Slot().HAlign(HAlign_Right).VAlign(VAlign_Top).Padding(FMargin(0.f, 110.f, 24.f, 0.f))
				[
					SNew(SBox).Visibility(EVisibility::HitTestInvisible) [ KillFeed ]
				]
				// Hit marker (centre)
				+ SOverlay::Slot().HAlign(HAlign_Center).VAlign(VAlign_Center)
				[
					SNew(STextBlock).Visibility(EVisibility::HitTestInvisible)
					.Text(FText::FromString(TEXT("X")))
					.Font(PUBGUI::Font(28, true))
					.ColorAndOpacity(this, &SPUBGGameHud::GetHitMarkerColor)
				]
				// Elimination / victory panel
				+ SOverlay::Slot().HAlign(HAlign_Center).VAlign(VAlign_Center)
				[
					SNew(SBox)
					.Visibility(this, &SPUBGGameHud::GetEndPanelVisibility)
					.MinDesiredWidth(560.f)
					[
						PUBGUI::MakePanel(
							SNew(SVerticalBox)
							+ SVerticalBox::Slot().AutoHeight().HAlign(HAlign_Center)
							[
								SNew(STextBlock).Text(this, &SPUBGGameHud::GetEndTitle).Font(PUBGUI::Font(40, true)).ColorAndOpacity(FSlateColor(PUBGUI::Accent()))
							]
							+ SVerticalBox::Slot().AutoHeight().HAlign(HAlign_Center).Padding(0.f, 10.f, 0.f, 18.f)
							[
								SNew(STextBlock).Text(this, &SPUBGGameHud::GetEndDetails).Font(PUBGUI::Font(20, false))
								.ColorAndOpacity(FSlateColor(PUBGUI::TextColor())).Justification(ETextJustify::Center)
							]
							+ SVerticalBox::Slot().AutoHeight().HAlign(HAlign_Center)
							[
								SNew(SHorizontalBox)
								+ SHorizontalBox::Slot().AutoWidth().Padding(6.f)
								[
									PUBGUI::MakeButton(LOCTEXT("Spectate", "SPECTATE"), FOnClicked::CreateSP(this, &SPUBGGameHud::SpectateNext), true, false, 20, 200.f)
								]
								+ SHorizontalBox::Slot().AutoWidth().Padding(6.f)
								[
									PUBGUI::MakeButton(LOCTEXT("Leave", "LEAVE MATCH"), FOnClicked::CreateSP(this, &SPUBGGameHud::LeaveMatch), true, true, 20, 200.f)
								]
							], FMargin(32.f))
					]
				]
			]
		]
	];
}

void SPUBGGameHud::Tick(const FGeometry& AllottedGeometry, const double InCurrentTime, const float InDeltaTime)
{
	SCompoundWidget::Tick(AllottedGeometry, InCurrentTime, InDeltaTime);
	if (InDeltaTime > KINDA_SMALL_NUMBER)
	{
		SmoothedFps = FMath::Lerp(SmoothedFps, 1.f / InDeltaTime, 0.05f);
	}
}

FText SPUBGGameHud::GetTopLeftText() const
{
	FString Text;
	const APlayerController* PC = OwnerPC.Get();
	if (PC && PC->GetNetMode() == NM_Client && PC->PlayerState)
	{
		Text = FString::Printf(TEXT("Ping %d ms"), PC->PlayerState->GetPing() * 4);
	}
	if (UPUBGGameUserSettings::GetPUBGSettings()->bShowFPS)
	{
		Text += FString::Printf(TEXT("%s%d FPS"), Text.IsEmpty() ? TEXT("") : TEXT("   "), FMath::RoundToInt(SmoothedFps));
	}
	return FText::FromString(Text);
}

FText SPUBGGameHud::GetStatusText() const
{
	const UPUBGMatchStateComponent* Match = UPUBGMatchStateComponent::Get(OwnerPC.Get());
	if (!Match)
	{
		return FText::GetEmpty(); // single player: the original HUD is enough
	}
	const APlayerController* PC = OwnerPC.Get();
	const UPUBGPlayerProfileComponent* Profile = PC ? UPUBGPlayerProfileComponent::Find(PC->PlayerState) : nullptr;
	const int32 Kills = Profile ? Profile->Kills : 0;
	if (Match->GetPhase() == EPUBGMatchPhase::InProgress && Match->GetTotalPlayers() < 2)
	{
		return FText::FromString(FString::Printf(TEXT("PRACTICE  |  KILLS %d  |  waiting for more players"), Kills));
	}
	return FText::FromString(FString::Printf(TEXT("ALIVE %d  |  KILLS %d"), Match->GetAliveCount(), Kills));
}

FText SPUBGGameHud::GetKillFeedLine(int32 Index) const
{
	const UPUBGMatchStateComponent* Match = UPUBGMatchStateComponent::Get(OwnerPC.Get());
	const APlayerController* PC = OwnerPC.Get();
	const AGameStateBase* GameState = PC && PC->GetWorld() ? PC->GetWorld()->GetGameState() : nullptr;
	if (!Match || !GameState)
	{
		return FText::GetEmpty();
	}
	const TArray<FPUBGKillFeedEntry> Feed = Match->GetKillFeed();
	const int32 EntryIndex = Feed.Num() - 1 - Index; // newest first
	if (!Feed.IsValidIndex(EntryIndex) || GameState->GetServerWorldTimeSeconds() - Feed[EntryIndex].ServerTime > 8.f)
	{
		return FText::GetEmpty();
	}
	const FPUBGKillFeedEntry& Entry = Feed[EntryIndex];
	const FString Weapon = Entry.WeaponID.IsNone() ? FString() : FString::Printf(TEXT(" [%s%s]"), *Entry.WeaponID.ToString(), Entry.bHeadshot ? TEXT(" HS") : TEXT(""));
	return Entry.KillerName.IsEmpty()
		? FText::FromString(FString::Printf(TEXT("%s was eliminated"), *Entry.VictimName))
		: FText::FromString(FString::Printf(TEXT("%s%s  >  %s"), *Entry.KillerName, *Weapon, *Entry.VictimName));
}

FText SPUBGGameHud::GetNoticeText() const
{
	const APlayerController* PC = OwnerPC.Get();
	const UPUBGPlayerNetComponent* Net = UPUBGPlayerNetComponent::Find(PC);
	if (Net && FPlatformTime::Seconds() - Net->LastNoticeTime < 5.0)
	{
		return FText::FromString(Net->LastNotice);
	}
	return FText::GetEmpty();
}

FSlateColor SPUBGGameHud::GetHitMarkerColor() const
{
	const UPUBGCombatComponent* Combat = UPUBGCombatComponent::Find(GetPawn());
	if (!Combat)
	{
		return FSlateColor(FLinearColor::Transparent);
	}
	const float Age = (float)(FPlatformTime::Seconds() - Combat->LastConfirmedHitTime);
	if (Age > 0.3f)
	{
		return FSlateColor(FLinearColor::Transparent);
	}
	const FLinearColor Base = Combat->bLastHitKilled ? PUBGUI::Danger() : (Combat->bLastHitHeadshot ? PUBGUI::Accent() : FLinearColor::White);
	return FSlateColor(Base.CopyWithNewOpacity(1.f - Age / 0.3f));
}

FSlateColor SPUBGGameHud::GetDamageFlashColor() const
{
	const UPUBGHealthComponent* Health = UPUBGHealthComponent::Find(GetPawn());
	if (!Health)
	{
		return FSlateColor(FLinearColor::Transparent);
	}
	const float Age = (float)(FPlatformTime::Seconds() - Health->LastDamageTime);
	const float Alpha = Age < 0.4f ? 0.25f * (1.f - Age / 0.4f) : 0.f;
	return FSlateColor(FLinearColor(0.8f, 0.f, 0.f, Alpha));
}

EVisibility SPUBGGameHud::GetEndPanelVisibility() const
{
	const UPUBGMatchStateComponent* Match = UPUBGMatchStateComponent::Get(OwnerPC.Get());
	if (!Match)
	{
		return EVisibility::Collapsed;
	}
	const APlayerController* PC = OwnerPC.Get();
	const UPUBGPlayerProfileComponent* Profile = PC ? UPUBGPlayerProfileComponent::Find(PC->PlayerState) : nullptr;
	const bool bEliminated = Profile && !Profile->bAlive;
	return (bEliminated || Match->GetPhase() == EPUBGMatchPhase::Finished) ? EVisibility::Visible : EVisibility::Collapsed;
}

FText SPUBGGameHud::GetEndTitle() const
{
	const APlayerController* PC = OwnerPC.Get();
	const UPUBGPlayerProfileComponent* Profile = PC ? UPUBGPlayerProfileComponent::Find(PC->PlayerState) : nullptr;
	if (Profile && Profile->Placement == 1)
	{
		return LOCTEXT("Victory", "VICTORY");
	}
	const UPUBGMatchStateComponent* Match = UPUBGMatchStateComponent::Get(PC);
	if (Match && Match->GetPhase() == EPUBGMatchPhase::Finished && Profile && Profile->bAlive)
	{
		return LOCTEXT("MatchOver", "MATCH OVER");
	}
	return LOCTEXT("Eliminated", "ELIMINATED");
}

FText SPUBGGameHud::GetEndDetails() const
{
	const APlayerController* PC = OwnerPC.Get();
	const UPUBGPlayerProfileComponent* Profile = PC ? UPUBGPlayerProfileComponent::Find(PC->PlayerState) : nullptr;
	const UPUBGMatchStateComponent* Match = UPUBGMatchStateComponent::Get(PC);
	FString Text;
	if (Profile)
	{
		Text = FString::Printf(TEXT("Place #%d of %d   -   %d kill(s)"), FMath::Max(1, Profile->Placement), Match ? Match->GetTotalPlayers() : 1, Profile->Kills);
	}
	if (Match && Match->GetPhase() == EPUBGMatchPhase::Finished)
	{
		if (!Match->GetWinnerName().IsEmpty())
		{
			Text += FString::Printf(TEXT("\nWinner: %s"), *Match->GetWinnerName());
		}
		const float Remaining = Match->GetReturnToLobbyRemaining();
		if (Remaining >= 0.f)
		{
			Text += FString::Printf(TEXT("\nBack to the lobby in %d s"), FMath::CeilToInt(Remaining));
		}
	}
	if (SpectateTarget.IsValid() && SpectateTarget->GetPlayerState())
	{
		Text += FString::Printf(TEXT("\nSpectating %s"), *SpectateTarget->GetPlayerState()->GetPlayerName());
	}
	return FText::FromString(Text);
}

FReply SPUBGGameHud::SpectateNext()
{
	APlayerController* PC = OwnerPC.Get();
	if (!PC || !PC->GetWorld())
	{
		return FReply::Handled();
	}
	TArray<APawn*> Alive;
	for (TActorIterator<APawn> It(PC->GetWorld()); It; ++It)
	{
		const UPUBGHealthComponent* Health = UPUBGHealthComponent::Find(*It);
		if (*It != PC->GetPawn() && Health && !Health->IsDead())
		{
			Alive.Add(*It);
		}
	}
	if (Alive.Num() == 0)
	{
		return FReply::Handled();
	}
	const int32 Current = Alive.IndexOfByKey(SpectateTarget.Get());
	APawn* Next = Alive[(Current + 1) % Alive.Num()];
	SpectateTarget = Next;
	PC->SetViewTargetWithBlend(Next, 0.3f);
	return FReply::Handled();
}

FReply SPUBGGameHud::LeaveMatch()
{
	if (UPUBGSessionSubsystem* Sessions = UPUBGSessionSubsystem::Get(OwnerPC.Get()))
	{
		Sessions->LeaveRoom();
	}
	return FReply::Handled();
}

// ---------------------------------------------------------------------------
// SPUBGInGameMenu
// ---------------------------------------------------------------------------

void SPUBGInGameMenu::Construct(const FArguments& InArgs)
{
	OwnerPC = InArgs._OwnerPC;
	TWeakObjectPtr<APlayerController> WeakPC = OwnerPC;

	auto Close = [WeakPC]()
	{
		if (UPUBGUISubsystem* UI = UPUBGUISubsystem::Get(WeakPC.Get()))
		{
			UI->CloseInGameMenu();
		}
		return FReply::Handled();
	};

	const bool bNetworked = WeakPC.IsValid() && WeakPC->GetNetMode() != NM_Standalone;

	ChildSlot
	[
		SNew(SOverlay)
		+ SOverlay::Slot()
		[
			SNew(SBorder).BorderImage(PUBGUI::WhiteBrush()).BorderBackgroundColor(FSlateColor(PUBGUI::Backdrop()))
		]
		+ SOverlay::Slot().HAlign(HAlign_Center).VAlign(VAlign_Center).Padding(40.f)
		[
			SNew(SBox)
			.MinDesiredWidth(520.f)
			.MaxDesiredHeight(900.f)
			[
				PUBGUI::MakePanel(
					SNew(SWidgetSwitcher)
					.WidgetIndex_Lambda([this]() { return Page; })
					+ SWidgetSwitcher::Slot()
					[
						SNew(SVerticalBox)
						+ SVerticalBox::Slot().AutoHeight().HAlign(HAlign_Center).Padding(0.f, 0.f, 0.f, 20.f)
						[
							PUBGUI::MakeText(LOCTEXT("Paused", "MENU"), 34, FSlateColor(PUBGUI::Accent()), true)
						]
						+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 6.f)
						[
							PUBGUI::MakeButton(LOCTEXT("Resume", "RESUME"), FOnClicked::CreateLambda(Close), true, true, 22, 420.f)
						]
						+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 6.f)
						[
							PUBGUI::MakeButton(LOCTEXT("Settings", "SETTINGS"), FOnClicked::CreateLambda([this]() { Page = 1; return FReply::Handled(); }), true, false, 22, 420.f)
						]
						+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 6.f)
						[
							SNew(SBox)
							.Visibility(UPUBGTouchInputComponent::ShouldUseTouchControls() ? EVisibility::Visible : EVisibility::Collapsed)
							[
								PUBGUI::MakeButton(LOCTEXT("EditLayout", "EDIT BUTTON LAYOUT"), FOnClicked::CreateLambda([WeakPC]()
								{
									if (UPUBGUISubsystem* UI = UPUBGUISubsystem::Get(WeakPC.Get()))
									{
										UI->OpenTouchLayoutEditor();
									}
									return FReply::Handled();
								}), true, false, 22, 420.f)
							]
						]
						+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 6.f)
						[
							PUBGUI::MakeButton(bNetworked ? LOCTEXT("LeaveMatch", "LEAVE MATCH") : LOCTEXT("MainMenu", "MAIN MENU"), FOnClicked::CreateLambda([WeakPC]()
							{
								if (UPUBGSessionSubsystem* Sessions = UPUBGSessionSubsystem::Get(WeakPC.Get()))
								{
									Sessions->LeaveRoom();
								}
								return FReply::Handled();
							}), true, false, 22, 420.f)
						]
						+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 6.f)
						[
							PUBGUI::MakeButton(LOCTEXT("Quit", "QUIT GAME"), FOnClicked::CreateLambda([WeakPC]()
							{
								UKismetSystemLibrary::QuitGame(WeakPC.Get(), WeakPC.Get(), EQuitPreference::Quit, false);
								return FReply::Handled();
							}), true, false, 22, 420.f)
						]
					]
					+ SWidgetSwitcher::Slot()
					[
						SNew(SVerticalBox)
						+ SVerticalBox::Slot().FillHeight(1.f)
						[
							SNew(SBox).HeightOverride(620.f)
							[
								SNew(SPUBGSettingsPanel)
								.OwnerPC(WeakPC)
								.OnEditLayout(FSimpleDelegate::CreateLambda([WeakPC]()
								{
									if (UPUBGUISubsystem* UI = UPUBGUISubsystem::Get(WeakPC.Get()))
									{
										UI->OpenTouchLayoutEditor();
									}
								}))
							]
						]
						+ SVerticalBox::Slot().AutoHeight().HAlign(HAlign_Left).Padding(0.f, 12.f, 0.f, 0.f)
						[
							PUBGUI::MakeButton(LOCTEXT("Back", "BACK"), FOnClicked::CreateLambda([this]() { Page = 0; return FReply::Handled(); }), true, false, 20, 200.f)
						]
					], FMargin(28.f))
			]
		]
	];
}

#undef LOCTEXT_NAMESPACE
