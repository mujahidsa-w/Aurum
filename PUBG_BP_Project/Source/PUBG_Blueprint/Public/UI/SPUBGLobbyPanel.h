// Pre-match room screen: players with host / ready / outfit / ping /
// connection state, ready & start, outfit choice, invite, settings, leave.

#pragma once

#include "CoreMinimal.h"
#include "Widgets/SCompoundWidget.h"
#include "Widgets/DeclarativeSyntaxSupport.h"

class APUBGLobbyPlayerController;
class APlayerState;
class SVerticalBox;

class PUBG_BLUEPRINT_API SPUBGLobbyPanel : public SCompoundWidget
{
public:
	SLATE_BEGIN_ARGS(SPUBGLobbyPanel) {}
		SLATE_ARGUMENT(TWeakObjectPtr<APUBGLobbyPlayerController>, OwnerPC)
	SLATE_END_ARGS()

	void Construct(const FArguments& InArgs);
	virtual void Tick(const FGeometry& AllottedGeometry, const double InCurrentTime, const float InDeltaTime) override;

private:
	void RebuildPlayers();
	TSharedRef<SWidget> MakePlayerRow(APlayerState* PS);
	class UPUBGPlayerProfileComponent* GetMyProfile() const;
	bool AmIHost() const;
	FText GetHeaderText() const;
	FText GetSubHeaderText() const;
	FText GetCountdownText() const;
	FText GetMessageText() const;
	FText GetCharacterText() const;
	void CycleCharacter(int32 Direction);

	TWeakObjectPtr<APUBGLobbyPlayerController> OwnerPC;
	TSharedPtr<SVerticalBox> PlayerList;
	FString PlayerSignature;
	bool bShowSettings = false;
};
