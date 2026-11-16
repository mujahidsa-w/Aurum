// In-match overlay drawn on top of the ORIGINAL Blueprint HUD:
// alive count, kills, kill feed, ping / FPS, hit marker, damage flash, server
// notices, and the elimination / victory screen (spectate, leave). Mostly
// hit-test invisible so touches reach the controls underneath.
// SPUBGInGameMenu: resume / settings / edit touch layout / leave.

#pragma once

#include "CoreMinimal.h"
#include "Widgets/SCompoundWidget.h"
#include "Widgets/DeclarativeSyntaxSupport.h"

class APlayerController;
class APawn;

class PUBG_BLUEPRINT_API SPUBGGameHud : public SCompoundWidget
{
public:
	SLATE_BEGIN_ARGS(SPUBGGameHud) {}
		SLATE_ARGUMENT(TWeakObjectPtr<APlayerController>, OwnerPC)
	SLATE_END_ARGS()

	void Construct(const FArguments& InArgs);
	virtual void Tick(const FGeometry& AllottedGeometry, const double InCurrentTime, const float InDeltaTime) override;

private:
	FText GetTopLeftText() const;
	FText GetStatusText() const;
	FText GetKillFeedLine(int32 Index) const;
	FText GetNoticeText() const;
	FSlateColor GetHitMarkerColor() const;
	FSlateColor GetDamageFlashColor() const;
	EVisibility GetEndPanelVisibility() const;
	FText GetEndTitle() const;
	FText GetEndDetails() const;
	FReply SpectateNext();
	FReply LeaveMatch();
	APawn* GetPawn() const;

	TWeakObjectPtr<APlayerController> OwnerPC;
	TWeakObjectPtr<APawn> SpectateTarget;
	float SmoothedFps = 60.f;
};

class PUBG_BLUEPRINT_API SPUBGInGameMenu : public SCompoundWidget
{
public:
	SLATE_BEGIN_ARGS(SPUBGInGameMenu) {}
		SLATE_ARGUMENT(TWeakObjectPtr<APlayerController>, OwnerPC)
	SLATE_END_ARGS()

	void Construct(const FArguments& InArgs);

private:
	TWeakObjectPtr<APlayerController> OwnerPC;
	int32 Page = 0;
};
