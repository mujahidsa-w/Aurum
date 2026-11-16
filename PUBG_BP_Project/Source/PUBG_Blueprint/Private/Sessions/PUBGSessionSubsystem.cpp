#include "Sessions/PUBGSessionSubsystem.h"

#include "PUBG_Blueprint.h"
#include "Core/PUBGSettings.h"
#include "Core/PUBGGameUserSettings.h"
#include "Lobby/PUBGFrontEndGameMode.h"

#include "OnlineSubsystem.h"
#include "OnlineSubsystemUtils.h"
#include "OnlineSessionSettings.h"
#include "Interfaces/OnlineExternalUIInterface.h"
#include "Engine/Engine.h"
#include "Engine/GameInstance.h"
#include "Engine/NetDriver.h"
#include "Engine/World.h"
#include "GameFramework/GameModeBase.h"
#include "GameFramework/PlayerController.h"
#include "Kismet/GameplayStatics.h"
#include "GenericPlatform/GenericPlatformHttp.h"
#include "SocketSubsystem.h"
#include "IPAddress.h"
#include "Misc/Paths.h"
#include "UObject/UObjectGlobals.h"

namespace
{
	const FName KeyRoomName(TEXT("PUBG_ROOMNAME"));
	const FName KeyHostName(TEXT("PUBG_HOST"));
	const FName KeyHasPassword(TEXT("PUBG_HASPW"));
	const FName KeyMapName(TEXT("PUBG_MAP"));

	FString SanitizePlayerName(const FString& In)
	{
		// Player names travel unencoded in the "?Name=" login option (the Blueprint
		// GameMode reads it directly), so keep them to URL-safe characters.
		FString Out;
		for (TCHAR C : In.TrimStartAndEnd())
		{
			if (FChar::IsAlnum(C) || C == TEXT('_') || C == TEXT('-'))
			{
				Out.AppendChar(C);
			}
			else if (C == TEXT(' '))
			{
				Out.AppendChar(TEXT('_'));
			}
			if (Out.Len() >= 16)
			{
				break;
			}
		}
		return Out;
	}

	FString JoinResultToText(EOnJoinSessionCompleteResult::Type Result)
	{
		switch (Result)
		{
		case EOnJoinSessionCompleteResult::SessionIsFull: return TEXT("The room is full.");
		case EOnJoinSessionCompleteResult::SessionDoesNotExist: return TEXT("The room no longer exists.");
		case EOnJoinSessionCompleteResult::CouldNotRetrieveAddress: return TEXT("Could not get the host address.");
		case EOnJoinSessionCompleteResult::AlreadyInSession: return TEXT("Already in a room.");
		default: return TEXT("Could not join the room.");
		}
	}
}

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

void UPUBGSessionSubsystem::Initialize(FSubsystemCollectionBase& Collection)
{
	Super::Initialize(Collection);

	if (GEngine)
	{
		NetFailureHandle = GEngine->OnNetworkFailure().AddUObject(this, &UPUBGSessionSubsystem::HandleNetworkFailure);
		TravelFailureHandle = GEngine->OnTravelFailure().AddUObject(this, &UPUBGSessionSubsystem::HandleTravelFailure);
	}
	PostLoadMapHandle = FCoreUObjectDelegates::PostLoadMapWithWorld.AddUObject(this, &UPUBGSessionSubsystem::HandlePostLoadMap);

	UPUBGGameUserSettings::GetPUBGSettings()->EnsureInitialized();
}

void UPUBGSessionSubsystem::Deinitialize()
{
	if (GEngine)
	{
		GEngine->OnNetworkFailure().Remove(NetFailureHandle);
		GEngine->OnTravelFailure().Remove(TravelFailureHandle);
	}
	FCoreUObjectDelegates::PostLoadMapWithWorld.Remove(PostLoadMapHandle);
	Super::Deinitialize();
}

UPUBGSessionSubsystem* UPUBGSessionSubsystem::Get(const UObject* WorldContext)
{
	const UWorld* World = GEngine ? GEngine->GetWorldFromContextObject(WorldContext, EGetWorldErrorMode::ReturnNull) : nullptr;
	UGameInstance* GameInstance = World ? World->GetGameInstance() : nullptr;
	return GameInstance ? GameInstance->GetSubsystem<UPUBGSessionSubsystem>() : nullptr;
}

IOnlineSessionPtr UPUBGSessionSubsystem::GetSessionInterface() const
{
	// Resolve per world so every PIE instance gets its own Null subsystem instance.
	const UWorld* World = GetGameInstance() ? GetGameInstance()->GetWorld() : nullptr;
	IOnlineSubsystem* OnlineSub = World ? Online::GetSubsystem(World) : IOnlineSubsystem::Get();
	return OnlineSub ? OnlineSub->GetSessionInterface() : nullptr;
}

// ---------------------------------------------------------------------------
// Profile
// ---------------------------------------------------------------------------

void UPUBGSessionSubsystem::SetDisplayName(const FString& NewName)
{
	const FString Clean = SanitizePlayerName(NewName);
	if (!Clean.IsEmpty())
	{
		UPUBGGameUserSettings* Settings = UPUBGGameUserSettings::GetPUBGSettings();
		Settings->PlayerDisplayName = Clean;
		Settings->SaveSettings();
	}
}

FString UPUBGSessionSubsystem::GetDisplayName() const
{
	const FString Name = SanitizePlayerName(UPUBGGameUserSettings::GetPUBGSettings()->PlayerDisplayName);
	return Name.IsEmpty() ? FString(TEXT("Player")) : Name;
}

void UPUBGSessionSubsystem::SetSelectedCharacter(int32 Index)
{
	const int32 Count = UPUBGSettings::Get()->CharacterPresets.Num();
	UPUBGGameUserSettings* Settings = UPUBGGameUserSettings::GetPUBGSettings();
	Settings->SelectedCharacter = Count > 0 ? FMath::Clamp(Index, 0, Count - 1) : 0;
	Settings->SaveSettings();
}

int32 UPUBGSessionSubsystem::GetSelectedCharacter() const
{
	return UPUBGGameUserSettings::GetPUBGSettings()->SelectedCharacter;
}

// ---------------------------------------------------------------------------
// Option helpers
// ---------------------------------------------------------------------------

FString UPUBGSessionSubsystem::EncodeOption(const FString& Value)
{
	return FGenericPlatformHttp::UrlEncode(Value);
}

FString UPUBGSessionSubsystem::DecodeOption(const FString& Value)
{
	return FGenericPlatformHttp::UrlDecode(Value);
}

FString UPUBGSessionSubsystem::BuildRoomOptions(const FPUBGRoomSettings& Settings)
{
	FString Options = FString::Printf(TEXT("?RoomName=%s?MaxPlayers=%d?BattleMap=%d"),
		*EncodeOption(Settings.RoomName), Settings.MaxPlayers, Settings.BattleMapIndex);
	if (!Settings.Password.IsEmpty())
	{
		Options += TEXT("?RoomPassword=") + EncodeOption(Settings.Password);
	}
	return Options;
}

FPUBGRoomSettings UPUBGSessionSubsystem::ParseRoomOptions(const FString& Options)
{
	const UPUBGSettings* S = UPUBGSettings::Get();
	FPUBGRoomSettings Settings;
	Settings.RoomName = DecodeOption(UGameplayStatics::ParseOption(Options, TEXT("RoomName")));
	if (Settings.RoomName.IsEmpty())
	{
		Settings.RoomName = TEXT("Room");
	}
	Settings.Password = DecodeOption(UGameplayStatics::ParseOption(Options, TEXT("RoomPassword")));
	Settings.MaxPlayers = FMath::Clamp(UGameplayStatics::GetIntOption(Options, TEXT("MaxPlayers"), S->DefaultMaxPlayers), 2, S->MaxPlayersLimit);
	Settings.BattleMapIndex = UGameplayStatics::GetIntOption(Options, TEXT("BattleMap"), 0);
	return Settings;
}

FString UPUBGSessionSubsystem::MakeJoinOptions(const FString& Password, const FString& Ticket) const
{
	FString Options = FString::Printf(TEXT("?Name=%s?Character=%d"), *GetDisplayName(), GetSelectedCharacter());
	if (!Password.IsEmpty())
	{
		Options += TEXT("?Password=") + EncodeOption(Password);
	}
	if (!Ticket.IsEmpty())
	{
		Options += TEXT("?Ticket=") + EncodeOption(Ticket);
	}
	return Options;
}

FString UPUBGSessionSubsystem::ConsumePendingMessage()
{
	FString Message = PendingMessage;
	PendingMessage.Empty();
	return Message;
}

// ---------------------------------------------------------------------------
// Navigation
// ---------------------------------------------------------------------------

void UPUBGSessionSubsystem::OpenMainMenu(const FString& Message)
{
	if (!Message.IsEmpty())
	{
		PendingMessage = Message;
	}
	bReturnToMenuOnNextLoad = false;
	PendingOp = EPendingOp::None;
	StatusText.Empty();

	if (IOnlineSessionPtr Sessions = GetSessionInterface())
	{
		if (Sessions->GetNamedSession(NAME_GameSession))
		{
			Sessions->DestroySession(NAME_GameSession);
		}
	}

	const UPUBGSettings* S = UPUBGSettings::Get();
	UGameplayStatics::OpenLevel(GetGameInstance(), FName(*S->MenuMap), true, TEXT("game=") + S->FrontEndGameAlias);
}

void UPUBGSessionSubsystem::StartOfflineMatch(int32 BattleMapIndex)
{
	if (IOnlineSessionPtr Sessions = GetSessionInterface())
	{
		if (Sessions->GetNamedSession(NAME_GameSession))
		{
			Sessions->DestroySession(NAME_GameSession);
		}
	}
	// No ?game= option: the map's own Blueprint GameMode (MyGameMode) runs exactly as before.
	UGameplayStatics::OpenLevel(GetGameInstance(), FName(*UPUBGSettings::Get()->GetBattleMap(BattleMapIndex)), true);
}

// ---------------------------------------------------------------------------
// Hosting
// ---------------------------------------------------------------------------

void UPUBGSessionSubsystem::HostRoom(const FPUBGRoomSettings& InSettings)
{
	if (IsBusy())
	{
		return;
	}
	const UPUBGSettings* S = UPUBGSettings::Get();
	PendingHostSettings = InSettings;
	PendingHostSettings.RoomName = InSettings.RoomName.TrimStartAndEnd().Left(24);
	if (PendingHostSettings.RoomName.IsEmpty())
	{
		PendingHostSettings.RoomName = GetDisplayName() + TEXT("'s room");
	}
	PendingHostSettings.MaxPlayers = FMath::Clamp(InSettings.MaxPlayers, 2, S->MaxPlayersLimit);
	PendingHostSettings.Password = InSettings.Password.Left(32);
	PendingHostSettings.BattleMapIndex = S->BattleMaps.IsValidIndex(InSettings.BattleMapIndex) ? InSettings.BattleMapIndex : 0;

	PendingOp = EPendingOp::Host;
	StatusText = TEXT("Creating room...");

	IOnlineSessionPtr Sessions = GetSessionInterface();
	if (!Sessions.IsValid())
	{
		// No online subsystem: still host, players can join by IP.
		UE_LOG(LogPUBG, Warning, TEXT("No session interface; hosting without advertising."));
		ActiveRoomSettings = PendingHostSettings;
		FinishHost(true, FString());
		TravelToLobbyAsHost();
		return;
	}
	if (Sessions->GetNamedSession(NAME_GameSession))
	{
		DestroySessionThen([this]() { CreateSessionNow(); });
		return;
	}
	CreateSessionNow();
}

void UPUBGSessionSubsystem::CreateSessionNow()
{
	IOnlineSessionPtr Sessions = GetSessionInterface();
	if (!Sessions.IsValid())
	{
		FinishHost(false, TEXT("Online subsystem unavailable."));
		return;
	}

	FOnlineSessionSettings SessionSettings;
	SessionSettings.NumPublicConnections = PendingHostSettings.MaxPlayers;
	SessionSettings.NumPrivateConnections = 0;
	SessionSettings.bIsLANMatch = PendingHostSettings.bLAN;
	SessionSettings.bShouldAdvertise = true;
	SessionSettings.bAllowJoinInProgress = true;
	SessionSettings.bAllowInvites = true;
	SessionSettings.bUsesPresence = true;
	SessionSettings.bAllowJoinViaPresence = true;
	SessionSettings.Set(KeyRoomName, PendingHostSettings.RoomName, EOnlineDataAdvertisementType::ViaOnlineServiceAndPing);
	SessionSettings.Set(KeyHostName, GetDisplayName(), EOnlineDataAdvertisementType::ViaOnlineServiceAndPing);
	SessionSettings.Set(KeyHasPassword, PendingHostSettings.Password.IsEmpty() ? 0 : 1, EOnlineDataAdvertisementType::ViaOnlineServiceAndPing);
	SessionSettings.Set(KeyMapName, FPaths::GetBaseFilename(UPUBGSettings::Get()->GetBattleMap(PendingHostSettings.BattleMapIndex)),
		EOnlineDataAdvertisementType::ViaOnlineServiceAndPing);

	CreateHandle = Sessions->AddOnCreateSessionCompleteDelegate_Handle(
		FOnCreateSessionCompleteDelegate::CreateUObject(this, &UPUBGSessionSubsystem::OnCreateSessionComplete));
	if (!Sessions->CreateSession(0, NAME_GameSession, SessionSettings))
	{
		Sessions->ClearOnCreateSessionCompleteDelegate_Handle(CreateHandle);
		FinishHost(false, TEXT("Could not create the room."));
	}
}

void UPUBGSessionSubsystem::OnCreateSessionComplete(FName SessionName, bool bWasSuccessful)
{
	if (IOnlineSessionPtr Sessions = GetSessionInterface())
	{
		Sessions->ClearOnCreateSessionCompleteDelegate_Handle(CreateHandle);
	}
	if (PendingOp != EPendingOp::Host)
	{
		return; // dedicated-server registration or stale callback
	}
	if (!bWasSuccessful)
	{
		FinishHost(false, TEXT("Could not create the room."));
		return;
	}
	ActiveRoomSettings = PendingHostSettings;
	FinishHost(true, FString());
	TravelToLobbyAsHost();
}

void UPUBGSessionSubsystem::FinishHost(bool bSuccess, const FString& Message)
{
	PendingOp = EPendingOp::None;
	StatusText = bSuccess ? TEXT("Loading lobby...") : FString();
	if (!bSuccess)
	{
		PendingMessage = Message;
		UE_LOG(LogPUBG, Warning, TEXT("Host failed: %s"), *Message);
	}
	OnHostResult.Broadcast(bSuccess, Message);
}

void UPUBGSessionSubsystem::TravelToLobbyAsHost()
{
	const UPUBGSettings* S = UPUBGSettings::Get();
	const FString Options = FString::Printf(TEXT("listen?game=%s"), *S->LobbyGameAlias) + BuildRoomOptions(ActiveRoomSettings) +
		FString::Printf(TEXT("?Name=%s?Character=%d"), *GetDisplayName(), GetSelectedCharacter());
	UE_LOG(LogPUBG, Log, TEXT("Hosting lobby: %s?%s"), *S->LobbyMap, *Options);
	UGameplayStatics::OpenLevel(GetGameInstance(), FName(*S->LobbyMap), true, Options);
}

void UPUBGSessionSubsystem::RegisterDedicatedSession(const FPUBGRoomSettings& Settings)
{
	ActiveRoomSettings = Settings;
	IOnlineSessionPtr Sessions = GetSessionInterface();
	if (!Sessions.IsValid() || Sessions->GetNamedSession(NAME_GameSession))
	{
		return;
	}
	FOnlineSessionSettings SessionSettings;
	SessionSettings.NumPublicConnections = Settings.MaxPlayers;
	SessionSettings.bIsDedicated = true;
	SessionSettings.bIsLANMatch = true;
	SessionSettings.bShouldAdvertise = true;
	SessionSettings.bAllowJoinInProgress = true;
	SessionSettings.bUsesPresence = false;
	SessionSettings.Set(KeyRoomName, Settings.RoomName, EOnlineDataAdvertisementType::ViaOnlineServiceAndPing);
	SessionSettings.Set(KeyHostName, FString(TEXT("Dedicated")), EOnlineDataAdvertisementType::ViaOnlineServiceAndPing);
	SessionSettings.Set(KeyHasPassword, Settings.Password.IsEmpty() ? 0 : 1, EOnlineDataAdvertisementType::ViaOnlineServiceAndPing);
	SessionSettings.Set(KeyMapName, FPaths::GetBaseFilename(UPUBGSettings::Get()->GetBattleMap(Settings.BattleMapIndex)),
		EOnlineDataAdvertisementType::ViaOnlineServiceAndPing);
	const bool bStarted = Sessions->CreateSession(0, NAME_GameSession, SessionSettings);
	UE_LOG(LogPUBG, Log, TEXT("Dedicated LAN session registration %s."), bStarted ? TEXT("started") : TEXT("failed"));
}

// ---------------------------------------------------------------------------
// Searching / joining
// ---------------------------------------------------------------------------

void UPUBGSessionSubsystem::FindLanRooms()
{
	if (IsBusy())
	{
		return;
	}
	IOnlineSessionPtr Sessions = GetSessionInterface();
	if (!Sessions.IsValid())
	{
		LanRooms.Reset();
		OnRoomsFound.Broadcast(false, LanRooms);
		return;
	}
	SessionSearch = MakeShared<FOnlineSessionSearch>();
	SessionSearch->bIsLanQuery = true;
	SessionSearch->MaxSearchResults = 50;
	SessionSearch->PingBucketSize = 50;

	PendingOp = EPendingOp::Find;
	StatusText = TEXT("Searching the local network...");
	FindHandle = Sessions->AddOnFindSessionsCompleteDelegate_Handle(
		FOnFindSessionsCompleteDelegate::CreateUObject(this, &UPUBGSessionSubsystem::OnFindSessionsComplete));
	if (!Sessions->FindSessions(0, SessionSearch.ToSharedRef()))
	{
		Sessions->ClearOnFindSessionsCompleteDelegate_Handle(FindHandle);
		PendingOp = EPendingOp::None;
		StatusText.Empty();
		LanRooms.Reset();
		OnRoomsFound.Broadcast(false, LanRooms);
	}
}

void UPUBGSessionSubsystem::OnFindSessionsComplete(bool bWasSuccessful)
{
	if (IOnlineSessionPtr Sessions = GetSessionInterface())
	{
		Sessions->ClearOnFindSessionsCompleteDelegate_Handle(FindHandle);
	}
	PendingOp = EPendingOp::None;
	StatusText.Empty();
	LanRooms.Reset();

	if (SessionSearch.IsValid())
	{
		for (int32 Index = 0; Index < SessionSearch->SearchResults.Num(); ++Index)
		{
			const FOnlineSessionSearchResult& Result = SessionSearch->SearchResults[Index];
			if (!Result.IsValid())
			{
				continue;
			}
			const FOnlineSessionSettings& SS = Result.Session.SessionSettings;
			FPUBGRoomInfo Info;
			Info.SearchResultIndex = Index;
			Info.bLAN = SS.bIsLANMatch;
			SS.Get(KeyRoomName, Info.RoomName);
			if (!SS.Get(KeyHostName, Info.HostName))
			{
				Info.HostName = Result.Session.OwningUserName;
			}
			if (Info.RoomName.IsEmpty())
			{
				Info.RoomName = Info.HostName;
			}
			int32 HasPassword = 0;
			SS.Get(KeyHasPassword, HasPassword);
			Info.bHasPassword = HasPassword != 0;
			SS.Get(KeyMapName, Info.MapName);
			Info.MaxPlayers = SS.NumPublicConnections;
			Info.CurrentPlayers = FMath::Max(0, Info.MaxPlayers - Result.Session.NumOpenPublicConnections);
			Info.PingMs = Result.PingInMs;
			Info.State = TEXT("lobby");
			LanRooms.Add(Info);
		}
	}
	UE_LOG(LogPUBG, Log, TEXT("LAN search finished (%s): %d room(s)."), bWasSuccessful ? TEXT("ok") : TEXT("failed"), LanRooms.Num());
	OnRoomsFound.Broadcast(bWasSuccessful, LanRooms);
}

void UPUBGSessionSubsystem::JoinLanRoom(int32 SearchResultIndex, const FString& Password)
{
	if (IsBusy())
	{
		return;
	}
	IOnlineSessionPtr Sessions = GetSessionInterface();
	if (!Sessions.IsValid() || !SessionSearch.IsValid() || !SessionSearch->SearchResults.IsValidIndex(SearchResultIndex))
	{
		FinishJoin(false, TEXT("The room is no longer available. Refresh the list."));
		return;
	}
	PendingJoinPassword = Password;
	PendingOp = EPendingOp::Join;
	StatusText = TEXT("Joining room...");

	const FOnlineSessionSearchResult Result = SessionSearch->SearchResults[SearchResultIndex];
	auto DoJoin = [this, Result]()
	{
		IOnlineSessionPtr Sessions = GetSessionInterface();
		if (!Sessions.IsValid())
		{
			FinishJoin(false, TEXT("Online subsystem unavailable."));
			return;
		}
		JoinHandle = Sessions->AddOnJoinSessionCompleteDelegate_Handle(
			FOnJoinSessionCompleteDelegate::CreateUObject(this, &UPUBGSessionSubsystem::OnJoinSessionComplete));
		if (!Sessions->JoinSession(0, NAME_GameSession, Result))
		{
			Sessions->ClearOnJoinSessionCompleteDelegate_Handle(JoinHandle);
			FinishJoin(false, TEXT("Could not join the room."));
		}
	};

	if (Sessions->GetNamedSession(NAME_GameSession))
	{
		DestroySessionThen(DoJoin);
	}
	else
	{
		DoJoin();
	}
}

void UPUBGSessionSubsystem::OnJoinSessionComplete(FName SessionName, EOnJoinSessionCompleteResult::Type Result)
{
	IOnlineSessionPtr Sessions = GetSessionInterface();
	if (Sessions.IsValid())
	{
		Sessions->ClearOnJoinSessionCompleteDelegate_Handle(JoinHandle);
	}
	if (Result != EOnJoinSessionCompleteResult::Success)
	{
		FinishJoin(false, JoinResultToText(Result));
		return;
	}
	FString ConnectString;
	if (!Sessions.IsValid() || !Sessions->GetResolvedConnectString(NAME_GameSession, ConnectString))
	{
		FinishJoin(false, TEXT("Could not get the host address."));
		return;
	}
	FinishJoin(true, FString());
	ClientTravelTo(ConnectString + MakeJoinOptions(PendingJoinPassword, FString()));
}

void UPUBGSessionSubsystem::JoinByAddress(const FString& Address, const FString& Password)
{
	const FString Clean = Address.TrimStartAndEnd();
	if (Clean.IsEmpty() || Clean.Contains(TEXT("?")) || Clean.Contains(TEXT(" ")))
	{
		FinishJoin(false, TEXT("Enter an address like 192.168.1.20 or 192.168.1.20:7777"));
		return;
	}
	PendingOp = EPendingOp::Join;
	StatusText = TEXT("Connecting to ") + Clean + TEXT("...");
	FinishJoin(true, FString());
	ClientTravelTo(Clean + MakeJoinOptions(Password, FString()));
}

void UPUBGSessionSubsystem::JoinWithTicket(const FString& Address, const FString& Ticket)
{
	PendingOp = EPendingOp::Join;
	StatusText = TEXT("Connecting to ") + Address + TEXT("...");
	FinishJoin(true, FString());
	ClientTravelTo(Address + MakeJoinOptions(FString(), Ticket));
}

void UPUBGSessionSubsystem::FinishJoin(bool bSuccess, const FString& Message)
{
	PendingOp = EPendingOp::None;
	if (!bSuccess)
	{
		StatusText.Empty();
		PendingMessage = Message;
		UE_LOG(LogPUBG, Warning, TEXT("Join failed: %s"), *Message);
	}
	OnJoinResult.Broadcast(bSuccess, Message);
}

void UPUBGSessionSubsystem::ClientTravelTo(const FString& URL)
{
	UE_LOG(LogPUBG, Log, TEXT("Client travel: %s"), *URL);
	UGameInstance* GameInstance = GetGameInstance();
	if (APlayerController* PC = GameInstance ? GameInstance->GetFirstLocalPlayerController() : nullptr)
	{
		PC->ClientTravel(URL, TRAVEL_Absolute);
	}
	else if (GEngine && GameInstance)
	{
		GEngine->SetClientTravel(GameInstance->GetWorld(), *URL, TRAVEL_Absolute);
	}
}

void UPUBGSessionSubsystem::LeaveRoom()
{
	IOnlineSessionPtr Sessions = GetSessionInterface();
	if (Sessions.IsValid() && Sessions->GetNamedSession(NAME_GameSession))
	{
		DestroySessionThen([this]() { OpenMainMenu(FString()); });
	}
	else
	{
		OpenMainMenu(FString());
	}
}

void UPUBGSessionSubsystem::DestroySessionThen(TFunction<void()> Next)
{
	IOnlineSessionPtr Sessions = GetSessionInterface();
	if (!Sessions.IsValid())
	{
		Next();
		return;
	}
	AfterDestroy = MoveTemp(Next);
	DestroyHandle = Sessions->AddOnDestroySessionCompleteDelegate_Handle(
		FOnDestroySessionCompleteDelegate::CreateUObject(this, &UPUBGSessionSubsystem::OnDestroySessionComplete));
	if (!Sessions->DestroySession(NAME_GameSession))
	{
		Sessions->ClearOnDestroySessionCompleteDelegate_Handle(DestroyHandle);
		TFunction<void()> Callback = MoveTemp(AfterDestroy);
		AfterDestroy = nullptr;
		if (Callback)
		{
			Callback();
		}
	}
}

void UPUBGSessionSubsystem::OnDestroySessionComplete(FName SessionName, bool bWasSuccessful)
{
	if (IOnlineSessionPtr Sessions = GetSessionInterface())
	{
		Sessions->ClearOnDestroySessionCompleteDelegate_Handle(DestroyHandle);
	}
	TFunction<void()> Callback = MoveTemp(AfterDestroy);
	AfterDestroy = nullptr;
	if (Callback)
	{
		Callback();
	}
}

bool UPUBGSessionSubsystem::CanShowInviteUI() const
{
	const UWorld* World = GetGameInstance() ? GetGameInstance()->GetWorld() : nullptr;
	IOnlineSubsystem* OnlineSub = World ? Online::GetSubsystem(World) : IOnlineSubsystem::Get();
	return OnlineSub && OnlineSub->GetExternalUIInterface().IsValid();
}

bool UPUBGSessionSubsystem::ShowInviteUI()
{
	const UWorld* World = GetGameInstance() ? GetGameInstance()->GetWorld() : nullptr;
	IOnlineSubsystem* OnlineSub = World ? Online::GetSubsystem(World) : IOnlineSubsystem::Get();
	IOnlineExternalUIPtr ExternalUI = OnlineSub ? OnlineSub->GetExternalUIInterface() : nullptr;
	return ExternalUI.IsValid() && ExternalUI->ShowInviteUI(0, NAME_GameSession);
}

FString UPUBGSessionSubsystem::GetLocalAddressHint() const
{
	ISocketSubsystem* Sockets = ISocketSubsystem::Get(PLATFORM_SOCKETSUBSYSTEM);
	if (!Sockets)
	{
		return FString();
	}
	bool bCanBindAll = false;
	TSharedRef<FInternetAddr> Address = Sockets->GetLocalHostAddr(*GLog, bCanBindAll);
	if (!Address->IsValid())
	{
		return FString();
	}
	FString Port = FString::FromInt(UPUBGSettings::Get()->DefaultPort);
	const UWorld* World = GetGameInstance() ? GetGameInstance()->GetWorld() : nullptr;
	if (UNetDriver* NetDriver = World ? World->GetNetDriver() : nullptr)
	{
		FString Left, Right;
		if (NetDriver->LowLevelGetNetworkNumber().Split(TEXT(":"), &Left, &Right, ESearchCase::IgnoreCase, ESearchDir::FromEnd))
		{
			Port = Right;
		}
	}
	return Address->ToString(false) + TEXT(":") + Port;
}

// ---------------------------------------------------------------------------
// Server travel
// ---------------------------------------------------------------------------

void UPUBGSessionSubsystem::SetSessionInProgress(bool bInProgress)
{
	IOnlineSessionPtr Sessions = GetSessionInterface();
	if (!Sessions.IsValid() || !Sessions->GetNamedSession(NAME_GameSession))
	{
		return;
	}
	if (bInProgress)
	{
		Sessions->StartSession(NAME_GameSession);
	}
	else
	{
		Sessions->EndSession(NAME_GameSession);
	}
}

bool UPUBGSessionSubsystem::ServerTravelToBattle()
{
	UWorld* World = GetGameInstance() ? GetGameInstance()->GetWorld() : nullptr;
	if (!World || World->GetNetMode() == NM_Client)
	{
		return false;
	}
	FString URL = UPUBGSettings::Get()->GetBattleMap(ActiveRoomSettings.BattleMapIndex) +
		FString::Printf(TEXT("?MaxPlayers=%d"), ActiveRoomSettings.MaxPlayers);
	if (World->GetNetMode() == NM_ListenServer)
	{
		URL += TEXT("?listen");
	}
	SetSessionInProgress(true);
	UE_LOG(LogPUBG, Log, TEXT("Server travel to battle: %s"), *URL);
	return World->ServerTravel(URL, false);
}

void UPUBGSessionSubsystem::ServerTravelToLobby()
{
	UWorld* World = GetGameInstance() ? GetGameInstance()->GetWorld() : nullptr;
	if (!World || World->GetNetMode() == NM_Client)
	{
		return;
	}
	const UPUBGSettings* S = UPUBGSettings::Get();
	FString URL = S->LobbyMap + TEXT("?game=") + S->LobbyGameAlias + BuildRoomOptions(ActiveRoomSettings);
	if (World->GetNetMode() == NM_ListenServer)
	{
		URL += TEXT("?listen");
	}
	SetSessionInProgress(false);
	UE_LOG(LogPUBG, Log, TEXT("Server travel back to lobby: %s"), *URL);
	World->ServerTravel(URL, false);
}

void UPUBGSessionSubsystem::StoreTravelProfile(const FString& Key, int32 CharacterIndex)
{
	if (!Key.IsEmpty())
	{
		TravelProfiles.Add(Key, CharacterIndex);
	}
}

bool UPUBGSessionSubsystem::GetTravelProfile(const FString& Key, int32& OutCharacterIndex) const
{
	if (const int32* Found = TravelProfiles.Find(Key))
	{
		OutCharacterIndex = *Found;
		return true;
	}
	return false;
}

// ---------------------------------------------------------------------------
// Failures
// ---------------------------------------------------------------------------

void UPUBGSessionSubsystem::HandleNetworkFailure(UWorld* World, UNetDriver* NetDriver, ENetworkFailure::Type FailureType, const FString& ErrorString)
{
	if (World && World->GetGameInstance() != GetGameInstance())
	{
		return; // another PIE instance
	}
	if (NetDriver && NetDriver->NetDriverName != NAME_GameNetDriver)
	{
		return;
	}
	PendingMessage = FString::Printf(TEXT("Connection lost (%s)%s%s"), ENetworkFailure::ToString(FailureType),
		ErrorString.IsEmpty() ? TEXT("") : TEXT(": "), *ErrorString);
	PendingOp = EPendingOp::None;
	StatusText.Empty();
	// The engine travels to the default map after a disconnect; redirect to the menu once it loads.
	bReturnToMenuOnNextLoad = true;
	UE_LOG(LogPUBG, Warning, TEXT("%s"), *PendingMessage);
}

void UPUBGSessionSubsystem::HandleTravelFailure(UWorld* World, ETravelFailure::Type FailureType, const FString& ErrorString)
{
	if (World && World->GetGameInstance() != GetGameInstance())
	{
		return;
	}
	PendingMessage = FString::Printf(TEXT("Could not join (%s)%s%s"), ETravelFailure::ToString(FailureType),
		ErrorString.IsEmpty() ? TEXT("") : TEXT(": "), *ErrorString);
	PendingOp = EPendingOp::None;
	StatusText.Empty();
	bReturnToMenuOnNextLoad = true;
	UE_LOG(LogPUBG, Warning, TEXT("%s"), *PendingMessage);
}

void UPUBGSessionSubsystem::HandlePostLoadMap(UWorld* LoadedWorld)
{
	if (!LoadedWorld || LoadedWorld->GetGameInstance() != GetGameInstance() || !bReturnToMenuOnNextLoad)
	{
		return;
	}
	bReturnToMenuOnNextLoad = false;
	const AGameModeBase* GameMode = LoadedWorld->GetAuthGameMode();
	if (GameMode && GameMode->IsA<APUBGFrontEndGameMode>())
	{
		return;
	}
	OpenMainMenu(FString());
}
