#include "UI/SPUBGMainMenu.h"

#include "Core/PUBGSettings.h"
#include "Sessions/PUBGRoomServiceSubsystem.h"
#include "Sessions/PUBGSessionSubsystem.h"
#include "UI/PUBGUIStyle.h"
#include "UI/SPUBGSettingsPanel.h"

#include "GameFramework/PlayerController.h"
#include "Kismet/KismetSystemLibrary.h"
#include "Misc/Paths.h"
#include "Styling/CoreStyle.h"
#include "Widgets/Input/SEditableTextBox.h"
#include "Widgets/Layout/SBorder.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/Layout/SSafeZone.h"
#include "Widgets/Layout/SScrollBox.h"
#include "Widgets/Layout/SWidgetSwitcher.h"
#include "Widgets/SBoxPanel.h"
#include "Widgets/SOverlay.h"
#include "Widgets/Text/STextBlock.h"

#define LOCTEXT_NAMESPACE "PUBGMainMenu"

namespace
{
	TSharedRef<SEditableTextBox> MakeEntry(const FText& Hint, FString* Target, bool bPassword = false)
	{
		return SNew(SEditableTextBox)
			.Font(PUBGUI::Font(20, false))
			.HintText(Hint)
			.IsPassword(bPassword)
			.Text_Lambda([Target]() { return FText::FromString(*Target); })
			.OnTextChanged_Lambda([Target](const FText& NewText) { *Target = NewText.ToString(); });
	}

	FString MapDisplayName(int32 Index)
	{
		return FPaths::GetBaseFilename(UPUBGSettings::Get()->GetBattleMap(Index)).Replace(TEXT("Level_"), TEXT(""));
	}
}

UPUBGSessionSubsystem* SPUBGMainMenu::Sessions() const
{
	return UPUBGSessionSubsystem::Get(OwnerPC.Get());
}

UPUBGRoomServiceSubsystem* SPUBGMainMenu::RoomService() const
{
	return UPUBGRoomServiceSubsystem::Get(OwnerPC.Get());
}

void SPUBGMainMenu::GoTo(int32 NewPage)
{
	Page = NewPage;
	if (Page == Multiplayer)
	{
		if (UPUBGSessionSubsystem* S = Sessions())
		{
			S->FindLanRooms();
		}
		if (UPUBGRoomServiceSubsystem* R = RoomService())
		{
			if (R->IsEnabled())
			{
				R->ListRooms();
			}
		}
	}
	if (Page == Character)
	{
		if (UPUBGSessionSubsystem* S = Sessions())
		{
			NameEdit = S->GetDisplayName();
		}
	}
}

void SPUBGMainMenu::Construct(const FArguments& InArgs)
{
	OwnerPC = InArgs._OwnerPC;
	MaxPlayers = UPUBGSettings::Get()->DefaultMaxPlayers;
	if (UPUBGSessionSubsystem* S = Sessions())
	{
		Banner = S->ConsumePendingMessage();
		RoomName = S->GetDisplayName() + TEXT("'s room");
		NameEdit = S->GetDisplayName();
	}

	ChildSlot
	[
		SNew(SOverlay)
		+ SOverlay::Slot()
		[
			SNew(SBorder).BorderImage(PUBGUI::WhiteBrush()).BorderBackgroundColor(FSlateColor(FLinearColor(0.f, 0.f, 0.f, 0.5f)))
		]
		+ SOverlay::Slot()
		[
			SNew(SSafeZone)
			.IsTitleSafe(true)
			.Padding(FMargin(40.f, 30.f))
			[
				SNew(SVerticalBox)
				// Error / info banner
				+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 0.f, 0.f, 12.f)
				[
					SNew(SBox)
					.Visibility_Lambda([this]() { return Banner.IsEmpty() ? EVisibility::Collapsed : EVisibility::Visible; })
					[
						PUBGUI::MakePanel(
							SNew(SHorizontalBox)
							+ SHorizontalBox::Slot().FillWidth(1.f).VAlign(VAlign_Center)
							[
								PUBGUI::MakeText(PUBGUI::Attr<FText>([this]() { return FText::FromString(Banner); }), 18, FSlateColor(PUBGUI::TextColor()))
							]
							+ SHorizontalBox::Slot().AutoWidth()
							[
								PUBGUI::MakeButton(LOCTEXT("Dismiss", "OK"), FOnClicked::CreateLambda([this]() { Banner.Empty(); return FReply::Handled(); }), true, false, 16)
							], FMargin(16.f, 10.f), FLinearColor(0.35f, 0.08f, 0.05f, 0.92f))
					]
				]
				+ SVerticalBox::Slot().FillHeight(1.f)
				[
					SNew(SHorizontalBox)
					+ SHorizontalBox::Slot().AutoWidth().Padding(0.f, 0.f, 32.f, 0.f)
					[
						SNew(SBox).WidthOverride(400.f) [ BuildNav() ]
					]
					+ SHorizontalBox::Slot().FillWidth(1.f)
					[
						PUBGUI::MakePanel(
							SNew(SWidgetSwitcher)
							.WidgetIndex_Lambda([this]() { return Page; })
							+ SWidgetSwitcher::Slot() [ BuildHome() ]
							+ SWidgetSwitcher::Slot() [ BuildPlay() ]
							+ SWidgetSwitcher::Slot() [ BuildMultiplayer() ]
							+ SWidgetSwitcher::Slot() [ BuildCreateRoom() ]
							+ SWidgetSwitcher::Slot() [ BuildCharacter() ]
							+ SWidgetSwitcher::Slot() [ SNew(SPUBGSettingsPanel).OwnerPC(OwnerPC) ],
							FMargin(28.f))
					]
				]
				// Status line
				+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 10.f, 0.f, 0.f)
				[
					PUBGUI::MakeText(PUBGUI::Attr<FText>([this]() { return GetStatusLine(); }), 16, FSlateColor(PUBGUI::Accent()))
				]
			]
		]
	];
}

FText SPUBGMainMenu::GetStatusLine() const
{
	const UPUBGRoomServiceSubsystem* R = RoomService();
	if (R && R->IsBusy())
	{
		return FText::FromString(R->GetStatusText());
	}
	const UPUBGSessionSubsystem* S = Sessions();
	return S ? FText::FromString(S->GetStatusText()) : FText::GetEmpty();
}

void SPUBGMainMenu::Tick(const FGeometry& AllottedGeometry, const double InCurrentTime, const float InDeltaTime)
{
	SCompoundWidget::Tick(AllottedGeometry, InCurrentTime, InDeltaTime);
	if (UPUBGSessionSubsystem* S = Sessions())
	{
		const FString Message = S->ConsumePendingMessage();
		if (!Message.IsEmpty())
		{
			Banner = Message;
		}
	}
	if (UPUBGRoomServiceSubsystem* R = RoomService())
	{
		const FString Error = R->ConsumeLastError();
		if (!Error.IsEmpty())
		{
			Banner = Error;
		}
	}
	RebuildRoomList(false);
	RebuildRoomList(true);
}

TSharedRef<SWidget> SPUBGMainMenu::BuildNav()
{
	const UPUBGSettings* ProjectSettings = UPUBGSettings::Get();
	auto NavButton = [this](const FText& Label, int32 Target, bool bAccent = false)
	{
		return PUBGUI::MakeButton(Label, FOnClicked::CreateLambda([this, Target]() { GoTo(Target); return FReply::Handled(); }), true, bAccent, 24, 400.f);
	};
	return SNew(SVerticalBox)
		+ SVerticalBox::Slot().AutoHeight()
		[
			PUBGUI::MakeText(FText::FromString(ProjectSettings->GameTitle), 56, FSlateColor(PUBGUI::Accent()), true)
		]
		+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 0.f, 0.f, 30.f)
		[
			PUBGUI::MakeText(FText::FromString(ProjectSettings->GameSubtitle), 18, FSlateColor(PUBGUI::Muted()))
		]
		+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 6.f) [ NavButton(LOCTEXT("StartMatch", "START MATCH"), Play, true) ]
		+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 6.f) [ NavButton(LOCTEXT("Multiplayer", "MULTIPLAYER"), Multiplayer) ]
		+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 6.f) [ NavButton(LOCTEXT("Character", "CHARACTER"), Character) ]
		+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 6.f) [ NavButton(LOCTEXT("Settings", "SETTINGS"), Settings) ]
		+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 6.f)
		[
			PUBGUI::MakeButton(LOCTEXT("Quit", "QUIT"), FOnClicked::CreateLambda([this]()
			{
				UKismetSystemLibrary::QuitGame(OwnerPC.Get(), OwnerPC.Get(), EQuitPreference::Quit, false);
				return FReply::Handled();
			}), true, false, 24, 400.f)
		];
}

TSharedRef<SWidget> SPUBGMainMenu::BuildHome()
{
	return SNew(SVerticalBox)
		+ SVerticalBox::Slot().AutoHeight()
		[
			PUBGUI::MakeText(PUBGUI::Attr<FText>([this]()
			{
				const UPUBGSessionSubsystem* S = Sessions();
				const TArray<FPUBGCharacterPreset>& Presets = UPUBGSettings::Get()->CharacterPresets;
				const int32 Index = S ? S->GetSelectedCharacter() : 0;
				const FString Outfit = Presets.IsValidIndex(Index) ? Presets[Index].DisplayName.ToString() : FString();
				return FText::FromString(FString::Printf(TEXT("Welcome, %s   |   Outfit: %s"), S ? *S->GetDisplayName() : TEXT("Player"), *Outfit));
			}), 24, FSlateColor(PUBGUI::TextColor()), true)
		]
		+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 18.f)
		[
			PUBGUI::MakeText(LOCTEXT("HomeHelp",
				"START MATCH plays the original single-player game.\n"
				"MULTIPLAYER: create a room on your Wi-Fi network (LAN), join a friend's room, connect by IP, "
				"or use online rooms when a room server is configured.\n"
				"Everyone in a room picks an outfit, marks READY, and the host starts the match."), 18, FSlateColor(PUBGUI::Muted()))
		];
}

TSharedRef<SWidget> SPUBGMainMenu::BuildMapOptions(int32* Target)
{
	TSharedRef<SHorizontalBox> Box = SNew(SHorizontalBox);
	const int32 Count = UPUBGSettings::Get()->BattleMaps.Num();
	for (int32 i = 0; i < Count; ++i)
	{
		Box->AddSlot().AutoWidth().Padding(0.f, 0.f, 8.f, 0.f)
		[
			PUBGUI::MakeOption(FText::FromString(MapDisplayName(i)), PUBGUI::Attr<bool>([Target, i]() { return *Target == i; }),
				FOnClicked::CreateLambda([Target, i]() { *Target = i; return FReply::Handled(); }), 18)
		];
	}
	return Box;
}

TSharedRef<SWidget> SPUBGMainMenu::BuildPlay()
{
	return SNew(SVerticalBox)
		+ SVerticalBox::Slot().AutoHeight() [ PUBGUI::MakeText(LOCTEXT("PlayTitle", "START MATCH"), 30, FSlateColor(PUBGUI::TextColor()), true) ]
		+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 8.f, 0.f, 18.f)
		[
			PUBGUI::MakeText(LOCTEXT("PlayHelp", "Single-player, exactly as the original project. 'Battle' is the large map and needs a high-end device."), 16, FSlateColor(PUBGUI::Muted()))
		]
		+ SVerticalBox::Slot().AutoHeight() [ PUBGUI::MakeRow(LOCTEXT("Map", "Map"), BuildMapOptions(&OfflineMapIndex)) ]
		+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 24.f).HAlign(HAlign_Left)
		[
			PUBGUI::MakeButton(LOCTEXT("Start", "START"), FOnClicked::CreateLambda([this]()
			{
				if (UPUBGSessionSubsystem* S = Sessions())
				{
					S->StartOfflineMatch(OfflineMapIndex);
				}
				return FReply::Handled();
			}), true, true, 24, 300.f)
		];
}

TSharedRef<SWidget> SPUBGMainMenu::BuildMultiplayer()
{
	auto Tab = [this](const FText& Label, int32 Index)
	{
		return PUBGUI::MakeOption(Label, PUBGUI::Attr<bool>([this, Index]() { return MultiplayerTab == Index; }),
			FOnClicked::CreateLambda([this, Index]() { MultiplayerTab = Index; return FReply::Handled(); }), 18);
	};
	const bool bOnlineEnabled = RoomService() && RoomService()->IsEnabled();

	TSharedRef<SWidget> LanPage = SNew(SVerticalBox)
		+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 0.f, 0.f, 10.f)
		[
			SNew(SHorizontalBox)
			+ SHorizontalBox::Slot().AutoWidth().Padding(0.f, 0.f, 8.f, 0.f)
			[
				PUBGUI::MakeButton(LOCTEXT("Refresh", "REFRESH"), FOnClicked::CreateLambda([this]()
				{
					if (UPUBGSessionSubsystem* S = Sessions()) { S->FindLanRooms(); }
					return FReply::Handled();
				}), PUBGUI::Attr<bool>([this]() { return Sessions() && !Sessions()->IsBusy(); }), false, 18)
			]
			+ SHorizontalBox::Slot().AutoWidth().Padding(0.f, 0.f, 8.f, 0.f)
			[
				PUBGUI::MakeButton(LOCTEXT("Create", "CREATE ROOM"), FOnClicked::CreateLambda([this]() { bCreateOnline = false; GoTo(CreateRoom); return FReply::Handled(); }), true, true, 18)
			]
			+ SHorizontalBox::Slot().FillWidth(1.f).VAlign(VAlign_Center).Padding(12.f, 0.f)
			[
				PUBGUI::MakeRow(LOCTEXT("Password", "Room password"), MakeEntry(LOCTEXT("PasswordHint", "only for locked rooms"), &JoinPassword, true), 180.f)
			]
		]
		+ SVerticalBox::Slot().FillHeight(1.f)
		[
			SNew(SScrollBox) + SScrollBox::Slot() [ SAssignNew(LanList, SVerticalBox) ]
		];

	TSharedRef<SWidget> OnlinePage = bOnlineEnabled
		? StaticCastSharedRef<SWidget>(SNew(SVerticalBox)
			+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 0.f, 0.f, 10.f)
			[
				SNew(SHorizontalBox)
				+ SHorizontalBox::Slot().AutoWidth().Padding(0.f, 0.f, 8.f, 0.f)
				[
					PUBGUI::MakeButton(LOCTEXT("RefreshOnline", "REFRESH"), FOnClicked::CreateLambda([this]()
					{
						if (UPUBGRoomServiceSubsystem* R = RoomService()) { R->ListRooms(); }
						return FReply::Handled();
					}), true, false, 18)
				]
				+ SHorizontalBox::Slot().AutoWidth().Padding(0.f, 0.f, 8.f, 0.f)
				[
					PUBGUI::MakeButton(LOCTEXT("CreateOnline", "CREATE ONLINE ROOM"), FOnClicked::CreateLambda([this]() { bCreateOnline = true; GoTo(CreateRoom); return FReply::Handled(); }), true, true, 18)
				]
				+ SHorizontalBox::Slot().FillWidth(1.f).VAlign(VAlign_Center).Padding(12.f, 0.f)
				[
					PUBGUI::MakeRow(LOCTEXT("OnlinePassword", "Room password"), MakeEntry(LOCTEXT("PasswordHint2", "only for locked rooms"), &JoinPassword, true), 180.f)
				]
			]
			+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 0.f, 0.f, 10.f)
			[
				SNew(SHorizontalBox)
				+ SHorizontalBox::Slot().FillWidth(1.f)
				[
					PUBGUI::MakeRow(LOCTEXT("Code", "Join code"), MakeEntry(LOCTEXT("CodeHint", "e.g. K7Q2XD"), &JoinCode), 180.f)
				]
				+ SHorizontalBox::Slot().AutoWidth().Padding(8.f, 0.f, 0.f, 0.f)
				[
					PUBGUI::MakeButton(LOCTEXT("JoinCode", "JOIN CODE"), FOnClicked::CreateLambda([this]()
					{
						if (UPUBGRoomServiceSubsystem* R = RoomService()) { R->JoinRoom(JoinCode, JoinPassword); }
						return FReply::Handled();
					}), PUBGUI::Attr<bool>([this]() { return RoomService() && !RoomService()->IsBusy(); }), false, 18)
				]
			]
			+ SVerticalBox::Slot().FillHeight(1.f)
			[
				SNew(SScrollBox) + SScrollBox::Slot() [ SAssignNew(OnlineList, SVerticalBox) ]
			])
		: PUBGUI::MakeText(LOCTEXT("OnlineDisabled",
			"Online rooms need the room service (Tools/RoomService) running on a server reachable from the internet.\n"
			"Set RoomServiceURL in Config/DefaultGame.ini. Until then use LAN rooms or Direct IP."), 18, FSlateColor(PUBGUI::Muted()));

	TSharedRef<SWidget> DirectPage = SNew(SVerticalBox)
		+ SVerticalBox::Slot().AutoHeight() [ PUBGUI::MakeRow(LOCTEXT("Address", "Host address"), MakeEntry(LOCTEXT("AddressHint", "192.168.1.20 or 192.168.1.20:7777"), &JoinAddress)) ]
		+ SVerticalBox::Slot().AutoHeight() [ PUBGUI::MakeRow(LOCTEXT("DirectPassword", "Room password"), MakeEntry(LOCTEXT("PasswordHint3", "optional"), &JoinPassword, true)) ]
		+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 16.f).HAlign(HAlign_Left)
		[
			PUBGUI::MakeButton(LOCTEXT("Connect", "CONNECT"), FOnClicked::CreateLambda([this]()
			{
				if (UPUBGSessionSubsystem* S = Sessions()) { S->JoinByAddress(JoinAddress, JoinPassword); }
				return FReply::Handled();
			}), true, true, 20, 260.f)
		]
		+ SVerticalBox::Slot().AutoHeight()
		[
			PUBGUI::MakeText(PUBGUI::Attr<FText>([this]()
			{
				const UPUBGSessionSubsystem* S = Sessions();
				return FText::FromString(FString::Printf(TEXT("This device: %s  (the host sees its address in the room screen)"), S ? *S->GetLocalAddressHint() : TEXT("?")));
			}), 15, FSlateColor(PUBGUI::Muted()))
		];

	return SNew(SVerticalBox)
		+ SVerticalBox::Slot().AutoHeight() [ PUBGUI::MakeText(LOCTEXT("MpTitle", "MULTIPLAYER"), 30, FSlateColor(PUBGUI::TextColor()), true) ]
		+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 12.f)
		[
			SNew(SHorizontalBox)
			+ SHorizontalBox::Slot().AutoWidth().Padding(0.f, 0.f, 8.f, 0.f) [ Tab(LOCTEXT("TabLan", "LAN / WI-FI"), 0) ]
			+ SHorizontalBox::Slot().AutoWidth().Padding(0.f, 0.f, 8.f, 0.f) [ Tab(LOCTEXT("TabOnline", "ONLINE"), 1) ]
			+ SHorizontalBox::Slot().AutoWidth() [ Tab(LOCTEXT("TabDirect", "DIRECT IP"), 2) ]
		]
		+ SVerticalBox::Slot().FillHeight(1.f)
		[
			SNew(SWidgetSwitcher)
			.WidgetIndex_Lambda([this]() { return MultiplayerTab; })
			+ SWidgetSwitcher::Slot() [ LanPage ]
			+ SWidgetSwitcher::Slot() [ OnlinePage ]
			+ SWidgetSwitcher::Slot() [ DirectPage ]
		];
}

TSharedRef<SWidget> SPUBGMainMenu::MakeRoomRow(const FPUBGRoomInfo& Room, bool bOnline)
{
	const FString Details = FString::Printf(TEXT("%s   |   %s   |   %d/%d players%s%s%s"),
		*Room.HostName, *Room.MapName, Room.CurrentPlayers, Room.MaxPlayers,
		bOnline ? TEXT("") : *FString::Printf(TEXT("   |   %d ms"), Room.PingMs),
		Room.bHasPassword ? TEXT("   |   LOCKED") : TEXT(""),
		Room.State == TEXT("in_game") ? TEXT("   |   match running") : TEXT(""));
	return SNew(SBox).Padding(FMargin(0.f, 0.f, 0.f, 8.f))
		[
			PUBGUI::MakePanel(
				SNew(SHorizontalBox)
				+ SHorizontalBox::Slot().FillWidth(1.f).VAlign(VAlign_Center)
				[
					SNew(SVerticalBox)
					+ SVerticalBox::Slot().AutoHeight() [ PUBGUI::MakeText(FText::FromString(Room.RoomName), 20, FSlateColor(PUBGUI::TextColor()), true) ]
					+ SVerticalBox::Slot().AutoHeight() [ PUBGUI::MakeText(FText::FromString(Details), 14, FSlateColor(PUBGUI::Muted())) ]
				]
				+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center)
				[
					PUBGUI::MakeButton(LOCTEXT("Join", "JOIN"), FOnClicked::CreateLambda([this, Room, bOnline]()
					{
						if (bOnline)
						{
							if (UPUBGRoomServiceSubsystem* R = RoomService()) { R->JoinRoom(Room.ServiceRoomId, JoinPassword); }
						}
						else if (UPUBGSessionSubsystem* S = Sessions())
						{
							S->JoinLanRoom(Room.SearchResultIndex, JoinPassword);
						}
						return FReply::Handled();
					}), Room.CurrentPlayers < Room.MaxPlayers, true, 18, 140.f)
				], FMargin(14.f), PUBGUI::PanelLight())
		];
}

void SPUBGMainMenu::RebuildRoomList(bool bOnline)
{
	TSharedPtr<SVerticalBox>& List = bOnline ? OnlineList : LanList;
	if (!List.IsValid())
	{
		return;
	}
	TArray<FPUBGRoomInfo> Rooms;
	if (bOnline)
	{
		if (const UPUBGRoomServiceSubsystem* R = RoomService()) { Rooms = R->GetOnlineRooms(); }
	}
	else if (const UPUBGSessionSubsystem* S = Sessions())
	{
		Rooms = S->GetLanRooms();
	}
	FString Signature = FString::FromInt(Rooms.Num());
	for (const FPUBGRoomInfo& Room : Rooms)
	{
		Signature += FString::Printf(TEXT("|%s:%d:%d:%s"), *Room.RoomName, Room.CurrentPlayers, Room.SearchResultIndex, *Room.State);
	}
	FString& Previous = bOnline ? OnlineSignature : LanSignature;
	if (Signature == Previous)
	{
		return;
	}
	Previous = Signature;
	List->ClearChildren();
	if (Rooms.Num() == 0)
	{
		List->AddSlot().AutoHeight()
		[
			PUBGUI::MakeText(bOnline ? LOCTEXT("NoOnline", "No online rooms yet. Create one!")
				: LOCTEXT("NoLan", "No rooms found on this network. Make sure both devices are on the same Wi-Fi, or create a room."), 18, FSlateColor(PUBGUI::Muted()))
		];
		return;
	}
	for (const FPUBGRoomInfo& Room : Rooms)
	{
		List->AddSlot().AutoHeight() [ MakeRoomRow(Room, bOnline) ];
	}
}

TSharedRef<SWidget> SPUBGMainMenu::BuildCreateRoom()
{
	const int32 Limit = UPUBGSettings::Get()->MaxPlayersLimit;
	const bool bOnlineEnabled = RoomService() && RoomService()->IsEnabled();
	return SNew(SVerticalBox)
		+ SVerticalBox::Slot().AutoHeight() [ PUBGUI::MakeText(LOCTEXT("CreateTitle", "CREATE ROOM"), 30, FSlateColor(PUBGUI::TextColor()), true) ]
		+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 14.f, 0.f, 0.f) [ PUBGUI::MakeRow(LOCTEXT("RoomName", "Room name"), MakeEntry(LOCTEXT("RoomNameHint", "My room"), &RoomName)) ]
		+ SVerticalBox::Slot().AutoHeight() [ PUBGUI::MakeRow(LOCTEXT("RoomPassword", "Password"), MakeEntry(LOCTEXT("RoomPasswordHint", "leave empty for a public room"), &RoomPassword, true)) ]
		+ SVerticalBox::Slot().AutoHeight()
		[
			PUBGUI::MakeRow(LOCTEXT("MaxPlayers", "Max players"),
				SNew(SHorizontalBox)
				+ SHorizontalBox::Slot().AutoWidth()
				[
					PUBGUI::MakeButton(FText::FromString(TEXT("-")), FOnClicked::CreateLambda([this]() { MaxPlayers = FMath::Max(2, MaxPlayers - 1); return FReply::Handled(); }), true, false, 20, 60.f)
				]
				+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center).Padding(16.f, 0.f)
				[
					PUBGUI::MakeText(PUBGUI::Attr<FText>([this]() { return FText::AsNumber(MaxPlayers); }), 22, FSlateColor(PUBGUI::TextColor()), true)
				]
				+ SHorizontalBox::Slot().AutoWidth()
				[
					PUBGUI::MakeButton(FText::FromString(TEXT("+")), FOnClicked::CreateLambda([this, Limit]() { MaxPlayers = FMath::Min(Limit, MaxPlayers + 1); return FReply::Handled(); }), true, false, 20, 60.f)
				])
		]
		+ SVerticalBox::Slot().AutoHeight() [ PUBGUI::MakeRow(LOCTEXT("RoomMap", "Map"), BuildMapOptions(&RoomMapIndex)) ]
		+ SVerticalBox::Slot().AutoHeight()
		[
			PUBGUI::MakeRow(LOCTEXT("Network", "Network"),
				SNew(SHorizontalBox)
				+ SHorizontalBox::Slot().AutoWidth().Padding(0.f, 0.f, 8.f, 0.f)
				[
					PUBGUI::MakeOption(LOCTEXT("Lan", "LAN / WI-FI (this device hosts)"), PUBGUI::Attr<bool>([this]() { return !bCreateOnline; }),
						FOnClicked::CreateLambda([this]() { bCreateOnline = false; return FReply::Handled(); }), 16)
				]
				+ SHorizontalBox::Slot().AutoWidth()
				[
					SNew(SBox).Visibility(bOnlineEnabled ? EVisibility::Visible : EVisibility::Collapsed)
					[
						PUBGUI::MakeOption(LOCTEXT("Online", "ONLINE (dedicated server)"), PUBGUI::Attr<bool>([this]() { return bCreateOnline; }),
							FOnClicked::CreateLambda([this]() { bCreateOnline = true; return FReply::Handled(); }), 16)
					]
				])
		]
		+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 24.f, 0.f, 0.f).HAlign(HAlign_Left)
		[
			SNew(SHorizontalBox)
			+ SHorizontalBox::Slot().AutoWidth().Padding(0.f, 0.f, 10.f, 0.f)
			[
				PUBGUI::MakeButton(LOCTEXT("CreateButton", "CREATE"), FOnClicked::CreateLambda([this]()
				{
					FPUBGRoomSettings Room;
					Room.RoomName = RoomName;
					Room.Password = RoomPassword;
					Room.MaxPlayers = MaxPlayers;
					Room.BattleMapIndex = RoomMapIndex;
					Room.bLAN = !bCreateOnline;
					if (bCreateOnline)
					{
						if (UPUBGRoomServiceSubsystem* R = RoomService()) { R->CreateRoom(Room); }
					}
					else if (UPUBGSessionSubsystem* S = Sessions())
					{
						S->HostRoom(Room);
					}
					return FReply::Handled();
				}), PUBGUI::Attr<bool>([this]() { return Sessions() && !Sessions()->IsBusy() && !(RoomService() && RoomService()->IsBusy()); }), true, 22, 260.f)
			]
			+ SHorizontalBox::Slot().AutoWidth()
			[
				PUBGUI::MakeButton(LOCTEXT("Back", "BACK"), FOnClicked::CreateLambda([this]() { GoTo(Multiplayer); return FReply::Handled(); }), true, false, 22, 200.f)
			]
		];
}

TSharedRef<SWidget> SPUBGMainMenu::BuildCharacter()
{
	TSharedRef<SVerticalBox> Presets = SNew(SVerticalBox);
	const TArray<FPUBGCharacterPreset>& List = UPUBGSettings::Get()->CharacterPresets;
	for (int32 i = 0; i < List.Num(); ++i)
	{
		const FPUBGCharacterPreset& Preset = List[i];
		Presets->AddSlot().AutoHeight().Padding(0.f, 4.f)
		[
			SNew(SHorizontalBox)
			+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center).Padding(0.f, 0.f, 12.f, 0.f)
			[
				SNew(SBox).WidthOverride(34.f).HeightOverride(34.f)
				[
					SNew(SBorder).BorderImage(PUBGUI::WhiteBrush()).BorderBackgroundColor(FSlateColor(Preset.UIColor))
				]
			]
			+ SHorizontalBox::Slot().AutoWidth()
			[
				SNew(SBox).MinDesiredWidth(320.f)
				[
					PUBGUI::MakeOption(Preset.DisplayName, PUBGUI::Attr<bool>([this, i]() { return Sessions() && Sessions()->GetSelectedCharacter() == i; }),
						FOnClicked::CreateLambda([this, i]()
						{
							if (UPUBGSessionSubsystem* S = Sessions()) { S->SetSelectedCharacter(i); }
							return FReply::Handled();
						}), 20)
				]
			]
		];
	}

	return SNew(SVerticalBox)
		+ SVerticalBox::Slot().AutoHeight() [ PUBGUI::MakeText(LOCTEXT("CharTitle", "CHARACTER"), 30, FSlateColor(PUBGUI::TextColor()), true) ]
		+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 14.f, 0.f, 0.f)
		[
			SNew(SHorizontalBox)
			+ SHorizontalBox::Slot().FillWidth(1.f)
			[
				PUBGUI::MakeRow(LOCTEXT("Name", "Player name"), MakeEntry(LOCTEXT("NameHint", "letters, numbers, _ and -"), &NameEdit))
			]
			+ SHorizontalBox::Slot().AutoWidth().Padding(10.f, 0.f, 0.f, 0.f).VAlign(VAlign_Center)
			[
				PUBGUI::MakeButton(LOCTEXT("SaveName", "SAVE"), FOnClicked::CreateLambda([this]()
				{
					if (UPUBGSessionSubsystem* S = Sessions())
					{
						S->SetDisplayName(NameEdit);
						NameEdit = S->GetDisplayName();
					}
					return FReply::Handled();
				}), true, true, 18)
			]
		]
		+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 16.f, 0.f, 8.f)
		[
			PUBGUI::MakeText(LOCTEXT("OutfitHelp", "Outfit (made from the project's own character meshes). Other players see it in multiplayer."), 16, FSlateColor(PUBGUI::Muted()))
		]
		+ SVerticalBox::Slot().AutoHeight() [ Presets ];
}

#undef LOCTEXT_NAMESPACE
