// Graphics + controls settings (main menu, lobby and in-game menu).
// Every change is applied immediately and saved to GameUserSettings.ini.

#pragma once

#include "CoreMinimal.h"
#include "Widgets/SCompoundWidget.h"
#include "Widgets/DeclarativeSyntaxSupport.h"

class APlayerController;

class PUBG_BLUEPRINT_API SPUBGSettingsPanel : public SCompoundWidget
{
public:
	SLATE_BEGIN_ARGS(SPUBGSettingsPanel) {}
		/** When set (in game, touch device), "Edit touch layout" is offered. */
		SLATE_ARGUMENT(TWeakObjectPtr<APlayerController>, OwnerPC)
		SLATE_EVENT(FSimpleDelegate, OnEditLayout)
	SLATE_END_ARGS()

	void Construct(const FArguments& InArgs);

private:
	TSharedRef<SWidget> BuildGraphics();
	TSharedRef<SWidget> BuildControls();

	TWeakObjectPtr<APlayerController> OwnerPC;
	FSimpleDelegate OnEditLayout;
	int32 Tab = 0;
};
