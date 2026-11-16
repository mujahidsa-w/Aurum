// Rooms over the Unreal Online Subsystem (sessions) + map travel.
//
// * LAN rooms use OnlineSubsystemNull (DefaultPlatformService=Null): real
//   session advertising / discovery over UDP broadcast on the local network.
// * Any reachable host can also be joined by IP ("Direct IP").
// * Internet rooms with dedicated servers go through UPUBGRoomServiceSubsystem.
// Switching DefaultPlatformService to Steam/EOS uses the same code path.

#pragma once

#include "CoreMinimal.h"
#include "Subsystems/GameInstanceSubsystem.h"
#include "Interfaces/OnlineSessionInterface.h"
#include "Engine/EngineBaseTypes.h"
#include "Core/PUBGTypes.h"
#include "PUBGSessionSubsystem.generated.h"

class FOnlineSessionSearch;

DECLARE_DYNAMIC_MULTICAST_DELEGATE_TwoParams(FPUBGOnSessionResult, bool, bSuccess, const FString&, Message);
DECLARE_DYNAMIC_MULTICAST_DELEGATE_TwoParams(FPUBGOnRoomsFound, bool, bSuccess, const TArray<FPUBGRoomInfo>&, Rooms);

UCLASS()
class PUBG_BLUEPRINT_API UPUBGSessionSubsystem : public UGameInstanceSubsystem
{
	GENERATED_BODY()

public:
	virtual void Initialize(FSubsystemCollectionBase& Collection) override;
	virtual void Deinitialize() override;

	static UPUBGSessionSubsystem* Get(const UObject* WorldContext);

	// ------------------------------------------------------------ Profile
	UFUNCTION(BlueprintCallable, Category = "PUBG|Profile") void SetDisplayName(const FString& NewName);
	UFUNCTION(BlueprintPure, Category = "PUBG|Profile") FString GetDisplayName() const;
	UFUNCTION(BlueprintCallable, Category = "PUBG|Profile") void SetSelectedCharacter(int32 Index);
	UFUNCTION(BlueprintPure, Category = "PUBG|Profile") int32 GetSelectedCharacter() const;

	// ------------------------------------------------------------ Navigation
	/** Leaves any session and loads the main menu. Message is shown on the menu. */
	UFUNCTION(BlueprintCallable, Category = "PUBG|Rooms") void OpenMainMenu(const FString& Message);
	/** The ORIGINAL single-player game: loads the battle map with its own Blueprint GameMode. */
	UFUNCTION(BlueprintCallable, Category = "PUBG|Rooms") void StartOfflineMatch(int32 BattleMapIndex);

	// ------------------------------------------------------------ Rooms (client side)
	UFUNCTION(BlueprintCallable, Category = "PUBG|Rooms") void HostRoom(const FPUBGRoomSettings& Settings);
	UFUNCTION(BlueprintCallable, Category = "PUBG|Rooms") void FindLanRooms();
	UFUNCTION(BlueprintCallable, Category = "PUBG|Rooms") void JoinLanRoom(int32 SearchResultIndex, const FString& Password);
	/** Address = "ip" or "ip:port". */
	UFUNCTION(BlueprintCallable, Category = "PUBG|Rooms") void JoinByAddress(const FString& Address, const FString& Password);
	/** Used by the room service (dedicated servers): the ticket replaces the password. */
	void JoinWithTicket(const FString& Address, const FString& Ticket);
	UFUNCTION(BlueprintCallable, Category = "PUBG|Rooms") void LeaveRoom();
	UFUNCTION(BlueprintCallable, Category = "PUBG|Rooms") bool ShowInviteUI();
	UFUNCTION(BlueprintPure, Category = "PUBG|Rooms") bool CanShowInviteUI() const;
	/** LAN address other players can type into "Direct IP" (best effort). */
	UFUNCTION(BlueprintPure, Category = "PUBG|Rooms") FString GetLocalAddressHint() const;
	UFUNCTION(BlueprintPure, Category = "PUBG|Rooms") bool IsBusy() const { return PendingOp != EPendingOp::None; }
	UFUNCTION(BlueprintPure, Category = "PUBG|Rooms") TArray<FPUBGRoomInfo> GetLanRooms() const { return LanRooms; }
	/** Returns and clears the message to show after an error / return to menu. */
	UFUNCTION(BlueprintCallable, Category = "PUBG|Rooms") FString ConsumePendingMessage();
	UFUNCTION(BlueprintPure, Category = "PUBG|Rooms") FString GetStatusText() const { return StatusText; }

	UPROPERTY(BlueprintAssignable, Category = "PUBG|Rooms") FPUBGOnSessionResult OnHostResult;
	UPROPERTY(BlueprintAssignable, Category = "PUBG|Rooms") FPUBGOnSessionResult OnJoinResult;
	UPROPERTY(BlueprintAssignable, Category = "PUBG|Rooms") FPUBGOnRoomsFound OnRoomsFound;

	// ------------------------------------------------------------ Server side
	/** Room settings of the room this machine is hosting / serving. */
	const FPUBGRoomSettings& GetActiveRoomSettings() const { return ActiveRoomSettings; }
	void SetActiveRoomSettings(const FPUBGRoomSettings& Settings) { ActiveRoomSettings = Settings; }
	/** Advertises a dedicated server on the LAN (Null subsystem). */
	void RegisterDedicatedSession(const FPUBGRoomSettings& Settings);
	/** Lobby -> battle map (seamless when possible). */
	bool ServerTravelToBattle();
	/** Battle -> lobby after the match. */
	void ServerTravelToLobby();
	/** Marks the session as in progress / back in lobby. */
	void SetSessionInProgress(bool bInProgress);

	/** Keeps per-player choices across server travel (key = unique id or name). */
	void StoreTravelProfile(const FString& Key, int32 CharacterIndex);
	bool GetTravelProfile(const FString& Key, int32& OutCharacterIndex) const;

	/** URL option helpers (values are URL-encoded so names with spaces survive FURL parsing). */
	static FString EncodeOption(const FString& Value);
	static FString DecodeOption(const FString& Value);
	static FString BuildRoomOptions(const FPUBGRoomSettings& Settings);
	static FPUBGRoomSettings ParseRoomOptions(const FString& Options);

private:
	enum class EPendingOp : uint8 { None, Host, Find, Join, Leave };

	IOnlineSessionPtr GetSessionInterface() const;
	void CreateSessionNow();
	void FinishHost(bool bSuccess, const FString& Message);
	void FinishJoin(bool bSuccess, const FString& Message);
	void TravelToLobbyAsHost();
	void ClientTravelTo(const FString& URL);
	FString MakeJoinOptions(const FString& Password, const FString& Ticket) const;
	void DestroySessionThen(TFunction<void()> Next);

	void OnCreateSessionComplete(FName SessionName, bool bWasSuccessful);
	void OnDestroySessionComplete(FName SessionName, bool bWasSuccessful);
	void OnFindSessionsComplete(bool bWasSuccessful);
	void OnJoinSessionComplete(FName SessionName, EOnJoinSessionCompleteResult::Type Result);
	void HandleNetworkFailure(UWorld* World, UNetDriver* NetDriver, ENetworkFailure::Type FailureType, const FString& ErrorString);
	void HandleTravelFailure(UWorld* World, ETravelFailure::Type FailureType, const FString& ErrorString);
	void HandlePostLoadMap(UWorld* LoadedWorld);

	EPendingOp PendingOp = EPendingOp::None;
	FPUBGRoomSettings PendingHostSettings;
	FPUBGRoomSettings ActiveRoomSettings;
	TSharedPtr<FOnlineSessionSearch> SessionSearch;
	TArray<FPUBGRoomInfo> LanRooms;
	FString PendingJoinPassword;
	TFunction<void()> AfterDestroy;
	FString PendingMessage;
	FString StatusText;
	bool bReturnToMenuOnNextLoad = false;
	TMap<FString, int32> TravelProfiles;

	FDelegateHandle CreateHandle, DestroyHandle, FindHandle, JoinHandle;
	FDelegateHandle NetFailureHandle, TravelFailureHandle, PostLoadMapHandle;
};
