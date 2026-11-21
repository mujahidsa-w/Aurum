// Main menu: Start Match (original single-player), Multiplayer (LAN rooms,
// online rooms, direct IP), Create Room, Character (name + outfit) and Settings.

#pragma once

#include "CoreMinimal.h"
#include "Core/PUBGTypes.h"
#include "Widgets/SCompoundWidget.h"
#include "Widgets/DeclarativeSyntaxSupport.h"

class APlayerController;
class SVerticalBox;

class PUBG_BLUEPRINT_API SPUBGMainMenu : public SCompoundWidget
{
public:
	SLATE_BEGIN_ARGS(SPUBGMainMenu) {}
		SLATE_ARGUMENT(TWeakObjectPtr<APlayerController>, OwnerPC)
	SLATE_END_ARGS()

	void Construct(const FArguments& InArgs);
	virtual void Tick(const FGeometry& AllottedGeometry, const double InCurrentTime, const float InDeltaTime) override;

private:
	enum EPage { Home = 0, Play, Multiplayer, CreateRoom, Character, Settings };

	TSharedRef<SWidget> BuildNav();
	TSharedRef<SWidget> BuildHome();
	TSharedRef<SWidget> BuildPlay();
	TSharedRef<SWidget> BuildMultiplayer();
	TSharedRef<SWidget> BuildCreateRoom();
	TSharedRef<SWidget> BuildCharacter();
	TSharedRef<SWidget> BuildMapOptions(int32* Target);
	TSharedRef<SWidget> MakeRoomRow(const FPUBGRoomInfo& Room, bool bOnline);
	void RebuildRoomList(bool bOnline);
	void GoTo(int32 NewPage);
	FText GetStatusLine() const;

	class UPUBGSessionSubsystem* Sessions() const;
	class UPUBGRoomServiceSubsystem* RoomService() const;

	TWeakObjectPtr<APlayerController> OwnerPC;
	int32 Page = Home;
	int32 MultiplayerTab = 0; // 0 LAN, 1 online, 2 direct IP
	FString Banner;

	// Create room
	FString RoomName;
	FString RoomPassword;
	int32 MaxPlayers = 8;
	int32 RoomMapIndex = 0;
	bool bCreateOnline = false;
	// Join
	FString JoinAddress;
	FString JoinPassword;
	FString JoinCode;
	// Offline
	int32 OfflineMapIndex = 0;
	// Profile
	FString NameEdit;

	TSharedPtr<SVerticalBox> LanList;
	TSharedPtr<SVerticalBox> OnlineList;
	FString LanSignature;
	FString OnlineSignature;
};
