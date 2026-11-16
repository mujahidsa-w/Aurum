#include "UI/SPUBGLobbyPanel.h"

#include "Core/PUBGSettings.h"
#include "Lobby/PUBGLobbyGameState.h"
#include "Lobby/PUBGLobbyPlayerController.h"
#include "Network/PUBGPlayerProfileComponent.h"
#include "Sessions/PUBGSessionSubsystem.h"
#include "UI/PUBGUIStyle.h"
#include "UI/SPUBGSettingsPanel.h"

#include "Engine/World.h"
#include "GameFramework/PlayerState.h"
#include "Widgets/Layout/SBorder.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/Layout/SSafeZone.h"
#include "Widgets/Layout/SScrollBox.h"
#include "Widgets/SBoxPanel.h"
#include "Widgets/SOverlay.h"

#define LOCTEXT_NAMESPACE "PUBGLobby"

namespace
{
	APUBGLobbyGameState* LobbyState(const APlayerController* PC)
	{
		return PC && PC->GetWorld() ? PC->GetWorld()->GetGameState<APUBGLobbyGameState>() : nullptr;
	}

	FString PresetName(int32 Index)
	{
		const TArray<FPUBGCharacterPreset>& Presets = UPUBGSettings::Get()->CharacterPresets;
		return Presets.IsValidIndex(Index) ? Presets[Index].DisplayName.ToString() : FString(TEXT("Default"));
	}
}

UPUBGPlayerProfileComponent* SPUBGLobbyPanel::GetMyProfile() const
{
	return OwnerPC.IsValid() ? UPUBGPlayerProfileComponent::Find(OwnerPC->PlayerState) : nullptr;
}

bool SPUBGLobbyPanel::AmIHost() const
{
	const UPUBGPlayerProfileComponent* Profile = GetMyProfile();
	return Profile && Profile->bIsHost;
}

void SPUBGLobbyPanel::Construct(const FArguments& InArgs)
{
	OwnerPC = InArgs._OwnerPC;
	TWeakObjectPtr<APUBGLobbyPlayerController> WeakPC = OwnerPC;

	// Send the locally chosen outfit (the URL option covers the first join; this covers changes).
	if (UPUBGSessionSubsystem* Sessions = UPUBGSessionSubsystem::Get(WeakPC.Get()))
	{
		if (WeakPC.IsValid())
		{
			WeakPC->ServerSetCharacter(Sessions->GetSelectedCharacter());
		}
	}

	auto SideButton = [](const TAttribute<FText>& Label, FOnClicked OnClicked, const TAttribute<bool>& Enabled, bool bAccent)
	{
		return SNew(SBox).Padding(FMargin(0.f, 5.f))
			[
				PUBGUI::MakeButton(Label, OnClicked, Enabled, bAccent, 22, 360.f)
			];
	};

	ChildSlot
	[
		SNew(SOverlay)
		+ SOverlay::Slot()
		[
			SNew(SBorder).BorderImage(PUBGUI::WhiteBrush()).BorderBackgroundColor(FSlateColor(FLinearColor(0.f, 0.f, 0.f, 0.55f)))
		]
		+ SOverlay::Slot()
		[
			SNew(SSafeZone)
			.IsTitleSafe(true)
			.Padding(FMargin(40.f, 30.f))
			[
				SNew(SHorizontalBox)
				// Room + players
				+ SHorizontalBox::Slot().FillWidth(1.f).Padding(0.f, 0.f, 28.f, 0.f)
				[
					PUBGUI::MakePanel(
						SNew(SVerticalBox)
						+ SVerticalBox::Slot().AutoHeight()
						[
							PUBGUI::MakeText(PUBGUI::Attr<FText>([this]() { return GetHeaderText(); }), 32, FSlateColor(PUBGUI::TextColor()), true)
						]
						+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 4.f, 0.f, 16.f)
						[
							PUBGUI::MakeText(PUBGUI::Attr<FText>([this]() { return GetSubHeaderText(); }), 16, FSlateColor(PUBGUI::Muted()))
						]
						+ SVerticalBox::Slot().FillHeight(1.f)
						[
							SNew(SScrollBox) + SScrollBox::Slot() [ SAssignNew(PlayerList, SVerticalBox) ]
						]
						+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 12.f, 0.f, 0.f)
						[
							PUBGUI::MakeText(PUBGUI::Attr<FText>([this]() { return GetCountdownText(); }), 26, FSlateColor(PUBGUI::Accent()), true)
						]
						+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 6.f, 0.f, 0.f)
						[
							PUBGUI::MakeText(PUBGUI::Attr<FText>([this]() { return GetMessageText(); }), 16, FSlateColor(PUBGUI::Danger()))
						], FMargin(26.f))
				]
				// Actions
				+ SHorizontalBox::Slot().AutoWidth()
				[
					SNew(SBox).WidthOverride(380.f)
					[
						SNew(SVerticalBox)
						+ SVerticalBox::Slot().AutoHeight()
						[
							SNew(SBox).Visibility_Lambda([this]() { return AmIHost() ? EVisibility::Visible : EVisibility::Collapsed; })
							[
								SideButton(LOCTEXT("Start", "START MATCH"), FOnClicked::CreateLambda([WeakPC]()
								{
									if (WeakPC.IsValid()) { WeakPC->ServerRequestStart(); }
									return FReply::Handled();
								}), PUBGUI::Attr<bool>([this]()
								{
									const APUBGLobbyGameState* LS = LobbyState(OwnerPC.Get());
									return LS && !LS->bTravelling && LS->CountdownEndTime < 0.f;
								}), true)
							]
						]
						+ SVerticalBox::Slot().AutoHeight()
						[
							// Listen-server host starts the match instead of readying up.
							SNew(SBox).Visibility_Lambda([this]()
							{
								const APUBGLobbyGameState* LS = LobbyState(OwnerPC.Get());
								return (!AmIHost() || (LS && LS->bDedicatedServer)) ? EVisibility::Visible : EVisibility::Collapsed;
							})
							[
								SideButton(PUBGUI::Attr<FText>([this]()
								{
									const UPUBGPlayerProfileComponent* P = GetMyProfile();
									return (P && P->bReady) ? LOCTEXT("NotReady", "NOT READY") : LOCTEXT("Ready", "READY");
								}), FOnClicked::CreateLambda([this, WeakPC]()
								{
									const UPUBGPlayerProfileComponent* P = GetMyProfile();
									if (WeakPC.IsValid()) { WeakPC->ServerSetReady(!(P && P->bReady)); }
									return FReply::Handled();
								}), true, true)
							]
						]
						+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 5.f)
						[
							PUBGUI::MakePanel(
								SNew(SHorizontalBox)
								+ SHorizontalBox::Slot().AutoWidth()
								[
									PUBGUI::MakeButton(FText::FromString(TEXT("<")), FOnClicked::CreateLambda([this]() { CycleCharacter(-1); return FReply::Handled(); }), true, false, 20, 56.f)
								]
								+ SHorizontalBox::Slot().FillWidth(1.f).HAlign(HAlign_Center).VAlign(VAlign_Center)
								[
									PUBGUI::MakeText(PUBGUI::Attr<FText>([this]() { return GetCharacterText(); }), 18, FSlateColor(PUBGUI::TextColor()), true)
								]
								+ SHorizontalBox::Slot().AutoWidth()
								[
									PUBGUI::MakeButton(FText::FromString(TEXT(">")), FOnClicked::CreateLambda([this]() { CycleCharacter(1); return FReply::Handled(); }), true, false, 20, 56.f)
								], FMargin(6.f), PUBGUI::PanelLight())
						]
						+ SVerticalBox::Slot().AutoHeight()
						[
							SideButton(LOCTEXT("Invite", "INVITE FRIENDS"), FOnClicked::CreateLambda([WeakPC]()
							{
								if (UPUBGSessionSubsystem* S = UPUBGSessionSubsystem::Get(WeakPC.Get())) { S->ShowInviteUI(); }
								return FReply::Handled();
							}), PUBGUI::Attr<bool>([WeakPC]()
							{
								const UPUBGSessionSubsystem* S = UPUBGSessionSubsystem::Get(WeakPC.Get());
								return S && S->CanShowInviteUI();
							}), false)
						]
						+ SVerticalBox::Slot().AutoHeight()
						[
							PUBGUI::MakeText(PUBGUI::Attr<FText>([this]()
							{
								const APUBGLobbyGameState* LS = LobbyState(OwnerPC.Get());
								if (!LS) { return FText::GetEmpty(); }
								if (!LS->JoinCode.IsEmpty()) { return FText::FromString(FString::Printf(TEXT("Share the join code %s"), *LS->JoinCode)); }
								if (!LS->HostAddress.IsEmpty()) { return FText::FromString(FString::Printf(TEXT("Friends on the same Wi-Fi find this room under MULTIPLAYER, or use Direct IP: %s"), *LS->HostAddress)); }
								return FText::GetEmpty();
							}), 14, FSlateColor(PUBGUI::Muted()))
						]
						+ SVerticalBox::Slot().AutoHeight()
						[
							SideButton(LOCTEXT("Settings", "SETTINGS"), FOnClicked::CreateLambda([this]() { bShowSettings = true; return FReply::Handled(); }), true, false)
						]
						+ SVerticalBox::Slot().AutoHeight()
						[
							SideButton(LOCTEXT("Leave", "LEAVE ROOM"), FOnClicked::CreateLambda([WeakPC]()
							{
								if (UPUBGSessionSubsystem* S = UPUBGSessionSubsystem::Get(WeakPC.Get())) { S->LeaveRoom(); }
								return FReply::Handled();
							}), true, false)
						]
					]
				]
			]
		]
		// Settings overlay
		+ SOverlay::Slot().HAlign(HAlign_Center).VAlign(VAlign_Center).Padding(60.f)
		[
			SNew(SBox)
			.Visibility_Lambda([this]() { return bShowSettings ? EVisibility::Visible : EVisibility::Collapsed; })
			.WidthOverride(1000.f)
			.HeightOverride(760.f)
			[
				PUBGUI::MakePanel(
					SNew(SVerticalBox)
					+ SVerticalBox::Slot().FillHeight(1.f) [ SNew(SPUBGSettingsPanel) ]
					+ SVerticalBox::Slot().AutoHeight().HAlign(HAlign_Left).Padding(0.f, 12.f, 0.f, 0.f)
					[
						PUBGUI::MakeButton(LOCTEXT("Close", "CLOSE"), FOnClicked::CreateLambda([this]() { bShowSettings = false; return FReply::Handled(); }), true, false, 20, 200.f)
					], FMargin(26.f), FLinearColor(0.03f, 0.035f, 0.045f, 0.98f))
			]
		]
	];
}

void SPUBGLobbyPanel::CycleCharacter(int32 Direction)
{
	const int32 Count = UPUBGSettings::Get()->CharacterPresets.Num();
	if (Count == 0 || !OwnerPC.IsValid())
	{
		return;
	}
	const UPUBGPlayerProfileComponent* Profile = GetMyProfile();
	const int32 Current = Profile ? Profile->CharacterIndex : 0;
	const int32 Next = (Current + Direction + Count) % Count;
	OwnerPC->ServerSetCharacter(Next);
	if (UPUBGSessionSubsystem* Sessions = UPUBGSessionSubsystem::Get(OwnerPC.Get()))
	{
		Sessions->SetSelectedCharacter(Next);
	}
}

FText SPUBGLobbyPanel::GetCharacterText() const
{
	const UPUBGPlayerProfileComponent* Profile = GetMyProfile();
	return FText::FromString(TEXT("Outfit: ") + PresetName(Profile ? Profile->CharacterIndex : 0));
}

FText SPUBGLobbyPanel::GetHeaderText() const
{
	const APUBGLobbyGameState* LS = LobbyState(OwnerPC.Get());
	if (!LS)
	{
		return LOCTEXT("Connecting", "Connecting...");
	}
	return FText::FromString(LS->RoomName + (LS->bHasPassword ? TEXT("  (locked)") : TEXT("")));
}

FText SPUBGLobbyPanel::GetSubHeaderText() const
{
	const APUBGLobbyGameState* LS = LobbyState(OwnerPC.Get());
	if (!LS)
	{
		return FText::GetEmpty();
	}
	int32 Players = 0;
	for (const APlayerState* PS : LS->PlayerArray)
	{
		Players += (PS && !PS->IsInactive()) ? 1 : 0;
	}
	return FText::FromString(FString::Printf(TEXT("Map: %s   |   Players %d / %d   |   %s"), *LS->BattleMapName, Players, LS->MaxPlayers,
		LS->bDedicatedServer ? TEXT("Dedicated server") : TEXT("Hosted by a player")));
}

FText SPUBGLobbyPanel::GetCountdownText() const
{
	const APUBGLobbyGameState* LS = LobbyState(OwnerPC.Get());
	if (!LS)
	{
		return FText::GetEmpty();
	}
	if (LS->bTravelling)
	{
		return LOCTEXT("Loading", "Loading the match...");
	}
	const float Remaining = LS->GetCountdownRemaining();
	if (Remaining >= 0.f)
	{
		return FText::FromString(FString::Printf(TEXT("Match starts in %d"), FMath::CeilToInt(Remaining)));
	}
	return AmIHost() && !LS->bDedicatedServer ? LOCTEXT("HostHint", "Start the match when everybody is ready.")
		: LOCTEXT("WaitHint", "Press READY. The match starts when everybody is ready.");
}

FText SPUBGLobbyPanel::GetMessageText() const
{
	const APUBGLobbyPlayerController* PC = OwnerPC.Get();
	if (PC && FPlatformTime::Seconds() - PC->LastMessageTime < 5.0)
	{
		return FText::FromString(PC->LastMessage);
	}
	return FText::GetEmpty();
}

void SPUBGLobbyPanel::Tick(const FGeometry& AllottedGeometry, const double InCurrentTime, const float InDeltaTime)
{
	SCompoundWidget::Tick(AllottedGeometry, InCurrentTime, InDeltaTime);
	RebuildPlayers();
}

void SPUBGLobbyPanel::RebuildPlayers()
{
	const APUBGLobbyGameState* LS = LobbyState(OwnerPC.Get());
	if (!PlayerList.IsValid() || !LS)
	{
		return;
	}
	FString Signature;
	for (const APlayerState* PS : LS->PlayerArray)
	{
		const UPUBGPlayerProfileComponent* Profile = UPUBGPlayerProfileComponent::Find(PS);
		if (PS && Profile)
		{
			Signature += FString::Printf(TEXT("%s/%d/%d/%d/%d|"), *PS->GetPlayerName(), Profile->bIsHost, Profile->bReady, Profile->CharacterIndex, (int32)Profile->ConnectionState);
		}
	}
	if (Signature == PlayerSignature)
	{
		return;
	}
	PlayerSignature = Signature;
	PlayerList->ClearChildren();
	for (APlayerState* PS : LS->PlayerArray)
	{
		if (PS && UPUBGPlayerProfileComponent::Find(PS))
		{
			PlayerList->AddSlot().AutoHeight().Padding(0.f, 0.f, 0.f, 6.f) [ MakePlayerRow(PS) ];
		}
	}
}

TSharedRef<SWidget> SPUBGLobbyPanel::MakePlayerRow(APlayerState* PS)
{
	TWeakObjectPtr<APlayerState> WeakPS(PS);
	TWeakObjectPtr<APUBGLobbyPlayerController> WeakPC = OwnerPC;
	const bool bIsMe = OwnerPC.IsValid() && OwnerPC->PlayerState == PS;

	return PUBGUI::MakePanel(
		SNew(SHorizontalBox)
		+ SHorizontalBox::Slot().FillWidth(1.f).VAlign(VAlign_Center)
		[
			PUBGUI::MakeText(PUBGUI::Attr<FText>([WeakPS, bIsMe]()
			{
				const UPUBGPlayerProfileComponent* Profile = UPUBGPlayerProfileComponent::Find(WeakPS.Get());
				if (!WeakPS.IsValid() || !Profile)
				{
					return FText::GetEmpty();
				}
				return FText::FromString(FString::Printf(TEXT("%s%s%s"), Profile->bIsHost ? TEXT("[HOST] ") : TEXT(""),
					*WeakPS->GetPlayerName(), bIsMe ? TEXT("  (you)") : TEXT("")));
			}), 20, FSlateColor(PUBGUI::TextColor()), true)
		]
		+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center).Padding(14.f, 0.f)
		[
			PUBGUI::MakeText(PUBGUI::Attr<FText>([WeakPS]()
			{
				const UPUBGPlayerProfileComponent* Profile = UPUBGPlayerProfileComponent::Find(WeakPS.Get());
				if (!WeakPS.IsValid() || !Profile)
				{
					return FText::GetEmpty();
				}
				return FText::FromString(FString::Printf(TEXT("%s   |   %s   |   %d ms   |   %s"), *PresetName(Profile->CharacterIndex),
					*Profile->GetConnectionStateText(), WeakPS->GetPing() * 4, Profile->bIsHost ? TEXT("host") : (Profile->bReady ? TEXT("READY") : TEXT("not ready"))));
			}), 15, FSlateColor(PUBGUI::Muted()))
		]
		+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center)
		[
			SNew(SBox).Visibility_Lambda([this, bIsMe]() { return (AmIHost() && !bIsMe) ? EVisibility::Visible : EVisibility::Collapsed; })
			[
				PUBGUI::MakeButton(LOCTEXT("Kick", "KICK"), FOnClicked::CreateLambda([WeakPC, WeakPS]()
				{
					if (WeakPC.IsValid() && WeakPS.IsValid()) { WeakPC->ServerKick(WeakPS.Get()); }
					return FReply::Handled();
				}), true, false, 14)
			]
		], FMargin(14.f, 10.f), PUBGUI::PanelLight());
}

#undef LOCTEXT_NAMESPACE
