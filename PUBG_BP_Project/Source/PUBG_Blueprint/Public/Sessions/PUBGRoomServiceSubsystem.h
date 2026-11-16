// Client + server side of Tools/RoomService (internet rooms on dedicated servers).
//
// Mobile devices are almost always behind NAT, so a phone cannot host an
// internet game. The room service runs next to the dedicated server binaries:
// "Create room" asks it to start a dedicated server process, the room list
// comes from it, and "Join" returns the server address plus a short-lived
// HMAC-signed ticket that the dedicated server verifies in PreLogin (the room
// password never reaches the game server).

#pragma once

#include "CoreMinimal.h"
#include "Subsystems/GameInstanceSubsystem.h"
#include "Containers/Ticker.h"
#include "Interfaces/IHttpRequest.h"
#include "Core/PUBGTypes.h"
#include "PUBGRoomServiceSubsystem.generated.h"

class FJsonObject;

DECLARE_DYNAMIC_MULTICAST_DELEGATE_TwoParams(FPUBGOnOnlineRoomsListed, bool, bSuccess, const TArray<FPUBGRoomInfo>&, Rooms);
DECLARE_DYNAMIC_MULTICAST_DELEGATE_TwoParams(FPUBGOnRoomServiceResult, bool, bSuccess, const FString&, Message);

UCLASS()
class PUBG_BLUEPRINT_API UPUBGRoomServiceSubsystem : public UGameInstanceSubsystem
{
	GENERATED_BODY()

public:
	virtual void Initialize(FSubsystemCollectionBase& Collection) override;
	virtual void Deinitialize() override;

	static UPUBGRoomServiceSubsystem* Get(const UObject* WorldContext);

	/** True when UPUBGSettings::RoomServiceURL (or -RoomService=) is set. */
	UFUNCTION(BlueprintPure, Category = "PUBG|Online") bool IsEnabled() const { return !BaseURL.IsEmpty(); }
	UFUNCTION(BlueprintPure, Category = "PUBG|Online") bool IsBusy() const { return bBusy; }
	UFUNCTION(BlueprintPure, Category = "PUBG|Online") FString GetStatusText() const { return StatusText; }
	/** Returns and clears the last error (for UI banners). */
	UFUNCTION(BlueprintCallable, Category = "PUBG|Online") FString ConsumeLastError() { FString E = LastError; LastError.Empty(); return E; }

	UFUNCTION(BlueprintCallable, Category = "PUBG|Online") void ListRooms();
	/** Asks the service to start a dedicated server, waits for it, then joins it. */
	UFUNCTION(BlueprintCallable, Category = "PUBG|Online") void CreateRoom(const FPUBGRoomSettings& Settings);
	/** RoomIdOrCode: id from the list or the 6-character join code. */
	UFUNCTION(BlueprintCallable, Category = "PUBG|Online") void JoinRoom(const FString& RoomIdOrCode, const FString& Password);

	UPROPERTY(BlueprintAssignable, Category = "PUBG|Online") FPUBGOnOnlineRoomsListed OnRoomsListed;
	UPROPERTY(BlueprintAssignable, Category = "PUBG|Online") FPUBGOnRoomServiceResult OnRoomResult;

	UFUNCTION(BlueprintPure, Category = "PUBG|Online") TArray<FPUBGRoomInfo> GetOnlineRooms() const { return OnlineRooms; }

	// ---------------------------------------------------------------- Dedicated server side
	/** Started by the room service (-RoomId= -RoomSecret= on the command line). */
	bool IsServingRoom() const { return !ServedRoomId.IsEmpty() && !ServedRoomSecret.IsEmpty(); }
	FString GetServedRoomCode() const { return ServedRoomCode; }
	/** Ticket = base64url("roomId|playerName|expiresUnix") + "." + hex(HMAC-SHA1(secret, payload)). */
	bool VerifyJoinTicket(const FString& Ticket, FString& OutError) const;
	/** Same check with an explicit secret / room id; used by the automation test. */
	static bool VerifyTicketWithSecret(const FString& Ticket, const FString& Secret, const FString& RoomId, int64 NowUnix, FString& OutError);

private:
	using FJsonCallback = TFunction<void(bool /*bOk*/, int32 /*Code*/, TSharedPtr<FJsonObject> /*Json*/)>;
	void SendJson(const FString& Verb, const FString& Path, TSharedPtr<FJsonObject> Body, FJsonCallback Done, bool bServerAuth = false);
	void PollRoomUntilReady(const FString& RoomId, const FString& Password, double Deadline);
	bool HeartbeatTick(float DeltaTime);
	static FPUBGRoomInfo ParseRoom(const TSharedPtr<FJsonObject>& Json);
	void Finish(bool bSuccess, const FString& Message);

	FString BaseURL;
	bool bBusy = false;
	FString StatusText;
	FString LastError;
	TArray<FPUBGRoomInfo> OnlineRooms;

	FString ServedRoomId;
	FString ServedRoomSecret;
	FString ServedRoomCode;
	FDelegateHandle HeartbeatHandle;
};
