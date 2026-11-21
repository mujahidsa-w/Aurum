#include "Sessions/PUBGRoomServiceSubsystem.h"

#include "PUBG_Blueprint.h"
#include "Core/PUBGSettings.h"
#include "Lobby/PUBGLobbyGameState.h"
#include "Sessions/PUBGSessionSubsystem.h"

#include "Engine/Engine.h"
#include "Engine/GameInstance.h"
#include "Engine/World.h"
#include "GameFramework/GameStateBase.h"
#include "GameFramework/PlayerState.h"
#include "HttpModule.h"
#include "Interfaces/IHttpResponse.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonWriter.h"
#include "Misc/Base64.h"
#include "Misc/CommandLine.h"
#include "Misc/DateTime.h"
#include "Misc/Parse.h"
#include "Misc/SecureHash.h"
#include "GenericPlatform/GenericPlatformHttp.h"

namespace
{
	// Try* accessors: a missing field must not spam LogJson errors.
	FString JsonString(const TSharedPtr<FJsonObject>& Json, const TCHAR* Field)
	{
		FString Value;
		if (Json.IsValid())
		{
			Json->TryGetStringField(Field, Value);
		}
		return Value;
	}

	int32 JsonInt(const TSharedPtr<FJsonObject>& Json, const TCHAR* Field)
	{
		double Value = 0.0;
		if (Json.IsValid())
		{
			Json->TryGetNumberField(Field, Value);
		}
		return (int32)Value;
	}

	bool JsonBool(const TSharedPtr<FJsonObject>& Json, const TCHAR* Field)
	{
		bool bValue = false;
		if (Json.IsValid())
		{
			Json->TryGetBoolField(Field, bValue);
		}
		return bValue;
	}
}

void UPUBGRoomServiceSubsystem::Initialize(FSubsystemCollectionBase& Collection)
{
	Super::Initialize(Collection);

	BaseURL = UPUBGSettings::Get()->RoomServiceURL;
	FString Override;
	if (FParse::Value(FCommandLine::Get(), TEXT("RoomService="), Override))
	{
		BaseURL = Override;
	}
	BaseURL.RemoveFromEnd(TEXT("/"));

	if (IsRunningDedicatedServer())
	{
		FParse::Value(FCommandLine::Get(), TEXT("RoomId="), ServedRoomId);
		FParse::Value(FCommandLine::Get(), TEXT("RoomSecret="), ServedRoomSecret);
		FParse::Value(FCommandLine::Get(), TEXT("RoomCode="), ServedRoomCode);
		if (IsServingRoom() && IsEnabled())
		{
			const float Interval = FMath::Max(1.f, UPUBGSettings::Get()->RoomHeartbeatSeconds);
			HeartbeatHandle = FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateUObject(this, &UPUBGRoomServiceSubsystem::HeartbeatTick), Interval);
			UE_LOG(LogPUBG, Log, TEXT("Serving room %s (code %s) for %s"), *ServedRoomId, *ServedRoomCode, *BaseURL);
		}
	}
}

void UPUBGRoomServiceSubsystem::Deinitialize()
{
	if (HeartbeatHandle.IsValid())
	{
		FTSTicker::GetCoreTicker().RemoveTicker(HeartbeatHandle);
	}
	Super::Deinitialize();
}

UPUBGRoomServiceSubsystem* UPUBGRoomServiceSubsystem::Get(const UObject* WorldContext)
{
	const UWorld* World = GEngine ? GEngine->GetWorldFromContextObject(WorldContext, EGetWorldErrorMode::ReturnNull) : nullptr;
	UGameInstance* GameInstance = World ? World->GetGameInstance() : nullptr;
	return GameInstance ? GameInstance->GetSubsystem<UPUBGRoomServiceSubsystem>() : nullptr;
}

void UPUBGRoomServiceSubsystem::SendJson(const FString& Verb, const FString& Path, TSharedPtr<FJsonObject> Body, FJsonCallback Done, bool bServerAuth)
{
	auto Request = FHttpModule::Get().CreateRequest();
	Request->SetURL(BaseURL + Path);
	Request->SetVerb(Verb);
	Request->SetHeader(TEXT("Content-Type"), TEXT("application/json"));
	Request->SetHeader(TEXT("Accept"), TEXT("application/json"));
	if (bServerAuth)
	{
		Request->SetHeader(TEXT("X-Room-Secret"), ServedRoomSecret);
	}
	if (Body.IsValid())
	{
		FString Payload;
		TSharedRef<TJsonWriter<>> Writer = TJsonWriterFactory<>::Create(&Payload);
		FJsonSerializer::Serialize(Body.ToSharedRef(), Writer);
		Request->SetContentAsString(Payload);
	}
	Request->SetTimeout(10.f);

	TWeakObjectPtr<UPUBGRoomServiceSubsystem> WeakThis(this);
	Request->OnProcessRequestComplete().BindLambda(
		[WeakThis, Done](FHttpRequestPtr /*Req*/, FHttpResponsePtr Response, bool bConnected)
		{
			if (!WeakThis.IsValid())
			{
				return;
			}
			const int32 Code = Response.IsValid() ? Response->GetResponseCode() : 0;
			TSharedPtr<FJsonObject> Json;
			if (Response.IsValid())
			{
				TSharedRef<TJsonReader<>> Reader = TJsonReaderFactory<>::Create(Response->GetContentAsString());
				FJsonSerializer::Deserialize(Reader, Json);
			}
			Done(bConnected && Code >= 200 && Code < 300, Code, Json);
		});
	Request->ProcessRequest();
}

FPUBGRoomInfo UPUBGRoomServiceSubsystem::ParseRoom(const TSharedPtr<FJsonObject>& Json)
{
	FPUBGRoomInfo Info;
	Info.ServiceRoomId = JsonString(Json, TEXT("id"));
	Info.JoinCode = JsonString(Json, TEXT("code"));
	Info.RoomName = JsonString(Json, TEXT("name"));
	Info.HostName = TEXT("Dedicated server");
	Info.CurrentPlayers = JsonInt(Json, TEXT("players"));
	Info.MaxPlayers = JsonInt(Json, TEXT("maxPlayers"));
	Info.bHasPassword = JsonBool(Json, TEXT("hasPassword"));
	Info.MapName = JsonString(Json, TEXT("map"));
	Info.State = JsonString(Json, TEXT("state"));
	Info.bLAN = false;
	return Info;
}

void UPUBGRoomServiceSubsystem::Finish(bool bSuccess, const FString& Message)
{
	bBusy = false;
	StatusText = bSuccess ? StatusText : FString();
	if (!bSuccess)
	{
		LastError = Message;
		UE_LOG(LogPUBG, Warning, TEXT("Room service: %s"), *Message);
	}
	OnRoomResult.Broadcast(bSuccess, Message);
}

void UPUBGRoomServiceSubsystem::ListRooms()
{
	if (!IsEnabled())
	{
		OnlineRooms.Reset();
		OnRoomsListed.Broadcast(false, OnlineRooms);
		return;
	}
	TWeakObjectPtr<UPUBGRoomServiceSubsystem> WeakThis(this);
	SendJson(TEXT("GET"), TEXT("/rooms"), nullptr, [WeakThis](bool bOk, int32 Code, TSharedPtr<FJsonObject> Json)
	{
		UPUBGRoomServiceSubsystem* Self = WeakThis.Get();
		if (!Self)
		{
			return;
		}
		Self->OnlineRooms.Reset();
		const TArray<TSharedPtr<FJsonValue>>* Rooms = nullptr;
		if (bOk && Json.IsValid() && Json->TryGetArrayField(TEXT("rooms"), Rooms))
		{
			for (const TSharedPtr<FJsonValue>& Value : *Rooms)
			{
				Self->OnlineRooms.Add(ParseRoom(Value->AsObject()));
			}
		}
		Self->OnRoomsListed.Broadcast(bOk, Self->OnlineRooms);
	});
}

void UPUBGRoomServiceSubsystem::CreateRoom(const FPUBGRoomSettings& Settings)
{
	if (!IsEnabled() || bBusy)
	{
		Finish(false, TEXT("Online rooms are not configured (RoomServiceURL)."));
		return;
	}
	bBusy = true;
	StatusText = TEXT("Starting a server...");

	UPUBGSessionSubsystem* Sessions = UPUBGSessionSubsystem::Get(this);
	TSharedPtr<FJsonObject> Body = MakeShared<FJsonObject>();
	Body->SetStringField(TEXT("name"), Settings.RoomName);
	Body->SetNumberField(TEXT("maxPlayers"), Settings.MaxPlayers);
	Body->SetStringField(TEXT("password"), Settings.Password);
	Body->SetNumberField(TEXT("mapIndex"), Settings.BattleMapIndex);
	Body->SetStringField(TEXT("hostName"), Sessions ? Sessions->GetDisplayName() : FString(TEXT("Player")));

	const FString Password = Settings.Password;
	TWeakObjectPtr<UPUBGRoomServiceSubsystem> WeakThis(this);
	SendJson(TEXT("POST"), TEXT("/rooms"), Body, [WeakThis, Password](bool bOk, int32 Code, TSharedPtr<FJsonObject> Json)
	{
		UPUBGRoomServiceSubsystem* Self = WeakThis.Get();
		if (!Self)
		{
			return;
		}
		if (!bOk || !Json.IsValid())
		{
			const FString Error = JsonString(Json, TEXT("error"));
			Self->Finish(false, Error.IsEmpty() ? FString::Printf(TEXT("Could not create the room (HTTP %d)."), Code) : Error);
			return;
		}
		const FString RoomId = JsonString(Json, TEXT("id"));
		Self->StatusText = TEXT("Waiting for the server to start...");
		Self->PollRoomUntilReady(RoomId, Password, FPlatformTime::Seconds() + 60.0);
	});
}

void UPUBGRoomServiceSubsystem::PollRoomUntilReady(const FString& RoomId, const FString& Password, double Deadline)
{
	TWeakObjectPtr<UPUBGRoomServiceSubsystem> WeakThis(this);
	SendJson(TEXT("GET"), TEXT("/rooms/") + RoomId, nullptr, [WeakThis, RoomId, Password, Deadline](bool bOk, int32 Code, TSharedPtr<FJsonObject> Json)
	{
		UPUBGRoomServiceSubsystem* Self = WeakThis.Get();
		if (!Self)
		{
			return;
		}
		const FString State = bOk ? JsonString(Json, TEXT("state")) : FString();
		if (State == TEXT("lobby") || State == TEXT("in_game"))
		{
			Self->bBusy = false;
			Self->JoinRoom(RoomId, Password);
			return;
		}
		if (State == TEXT("failed") || (!bOk && Code == 404) || FPlatformTime::Seconds() > Deadline)
		{
			Self->Finish(false, TEXT("The server did not start in time."));
			return;
		}
		// Poll again in one second.
		FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateLambda([WeakThis, RoomId, Password, Deadline](float)
		{
			if (UPUBGRoomServiceSubsystem* Again = WeakThis.Get())
			{
				Again->PollRoomUntilReady(RoomId, Password, Deadline);
			}
			return false; // one-shot
		}), 1.f);
	});
}

void UPUBGRoomServiceSubsystem::JoinRoom(const FString& RoomIdOrCode, const FString& Password)
{
	if (!IsEnabled() || bBusy)
	{
		return;
	}
	const FString Clean = RoomIdOrCode.TrimStartAndEnd();
	if (Clean.IsEmpty())
	{
		Finish(false, TEXT("Enter a room code."));
		return;
	}
	bBusy = true;
	StatusText = TEXT("Requesting access...");

	UPUBGSessionSubsystem* Sessions = UPUBGSessionSubsystem::Get(this);
	TSharedPtr<FJsonObject> Body = MakeShared<FJsonObject>();
	Body->SetStringField(TEXT("playerName"), Sessions ? Sessions->GetDisplayName() : FString(TEXT("Player")));
	Body->SetStringField(TEXT("password"), Password);

	TWeakObjectPtr<UPUBGRoomServiceSubsystem> WeakThis(this);
	SendJson(TEXT("POST"), TEXT("/rooms/") + FGenericPlatformHttp::UrlEncode(Clean) + TEXT("/join"), Body,
		[WeakThis](bool bOk, int32 Code, TSharedPtr<FJsonObject> Json)
	{
		UPUBGRoomServiceSubsystem* Self = WeakThis.Get();
		if (!Self)
		{
			return;
		}
		if (!bOk || !Json.IsValid())
		{
			FString Error = JsonString(Json, TEXT("error"));
			if (Error.IsEmpty())
			{
				Error = Code == 403 ? TEXT("Wrong room password.") : (Code == 404 ? TEXT("Room not found.") : FString::Printf(TEXT("Could not join (HTTP %d)."), Code));
			}
			Self->Finish(false, Error);
			return;
		}
		const FString Address = JsonString(Json, TEXT("address"));
		const FString Ticket = JsonString(Json, TEXT("ticket"));
		Self->StatusText = TEXT("Connecting...");
		Self->Finish(true, FString());
		if (UPUBGSessionSubsystem* SessionSubsystem = UPUBGSessionSubsystem::Get(Self))
		{
			SessionSubsystem->JoinWithTicket(Address, Ticket);
		}
	});
}

bool UPUBGRoomServiceSubsystem::HeartbeatTick(float DeltaTime)
{
	const UWorld* World = GetGameInstance() ? GetGameInstance()->GetWorld() : nullptr;
	int32 Players = 0;
	FString State = TEXT("in_game");
	if (const AGameStateBase* GameState = World ? World->GetGameState() : nullptr)
	{
		for (const APlayerState* PS : GameState->PlayerArray)
		{
			Players += (PS && !PS->IsInactive() && !PS->IsABot()) ? 1 : 0;
		}
		if (GameState->IsA<APUBGLobbyGameState>())
		{
			State = TEXT("lobby");
		}
	}
	TSharedPtr<FJsonObject> Body = MakeShared<FJsonObject>();
	Body->SetNumberField(TEXT("players"), Players);
	Body->SetStringField(TEXT("state"), State);
	SendJson(TEXT("POST"), TEXT("/rooms/") + ServedRoomId + TEXT("/heartbeat"), Body,
		[](bool bOk, int32 Code, TSharedPtr<FJsonObject>)
		{
			if (!bOk)
			{
				UE_LOG(LogPUBG, Warning, TEXT("Room heartbeat failed (HTTP %d)."), Code);
			}
		}, true);
	return true; // keep ticking
}

bool UPUBGRoomServiceSubsystem::VerifyJoinTicket(const FString& Ticket, FString& OutError) const
{
	return VerifyTicketWithSecret(Ticket, ServedRoomSecret, ServedRoomId, FDateTime::UtcNow().ToUnixTimestamp(), OutError);
}

bool UPUBGRoomServiceSubsystem::VerifyTicketWithSecret(const FString& Ticket, const FString& Secret, const FString& RoomId, int64 NowUnix, FString& OutError)
{
	FString PayloadB64, SignatureHex;
	if (Ticket.IsEmpty() || !Ticket.Split(TEXT("."), &PayloadB64, &SignatureHex))
	{
		OutError = TEXT("Join through the room list (missing ticket).");
		return false;
	}
	FString Base64 = PayloadB64.Replace(TEXT("-"), TEXT("+")).Replace(TEXT("_"), TEXT("/"));
	while (Base64.Len() % 4 != 0)
	{
		Base64.AppendChar(TEXT('='));
	}
	TArray<uint8> PayloadBytes;
	if (!FBase64::Decode(Base64, PayloadBytes) || PayloadBytes.Num() == 0)
	{
		OutError = TEXT("Invalid ticket.");
		return false;
	}

	FTCHARToUTF8 KeyUtf8(*Secret);
	uint8 Hash[FSHA1::DigestSize];
	FSHA1::HMACBuffer(KeyUtf8.Get(), KeyUtf8.Length(), PayloadBytes.GetData(), PayloadBytes.Num(), Hash);
	const FString Expected = BytesToHex(Hash, FSHA1::DigestSize).ToLower();
	if (!Expected.Equals(SignatureHex.ToLower(), ESearchCase::CaseSensitive))
	{
		OutError = TEXT("Invalid ticket signature.");
		return false;
	}

	PayloadBytes.Add(0);
	const FString Payload = UTF8_TO_TCHAR((const ANSICHAR*)PayloadBytes.GetData());
	TArray<FString> Parts;
	Payload.ParseIntoArray(Parts, TEXT("|"), false);
	if (Parts.Num() != 3)
	{
		OutError = TEXT("Invalid ticket.");
		return false;
	}
	if (Parts[0] != RoomId)
	{
		OutError = TEXT("Ticket is for another room.");
		return false;
	}
	if (NowUnix > FCString::Atoi64(*Parts[2]))
	{
		OutError = TEXT("Ticket expired, join again.");
		return false;
	}
	return true;
}
