// Small Slate style kit for the menus / HUD built in C++ (no widget assets needed).
// Sizes are Slate units; the project DPI curve scales them to the screen.

#pragma once

#include "CoreMinimal.h"
#include "Styling/SlateColor.h"
#include "Styling/SlateTypes.h"
#include "Fonts/SlateFontInfo.h"
#include "Input/Reply.h"
#include "Misc/Attribute.h"
#include "Framework/SlateDelegates.h"
#include "Widgets/SWidget.h"
#include "Widgets/DeclarativeSyntaxSupport.h"

namespace PUBGUI
{
	/** Lambda-bound attribute (FGetter::CreateLambda works on every UE4 version). */
	template <typename T, typename FuncType>
	TAttribute<T> Attr(FuncType&& Func)
	{
		return TAttribute<T>::Create(typename TAttribute<T>::FGetter::CreateLambda(Forward<FuncType>(Func)));
	}

	FLinearColor Accent();
	FLinearColor Panel();
	FLinearColor PanelLight();
	FLinearColor Backdrop();
	FLinearColor TextColor();
	FLinearColor Muted();
	FLinearColor Danger();
	FLinearColor Success();

	const FSlateBrush* WhiteBrush();
	FSlateFontInfo Font(int32 Size, bool bBold = true);
	const FButtonStyle& ButtonStyle(bool bAccent);
	const FButtonStyle& SelectedButtonStyle();

	TSharedRef<SWidget> MakeButton(const TAttribute<FText>& Label, FOnClicked OnClicked, const TAttribute<bool>& Enabled = true,
		bool bAccent = false, int32 FontSize = 20, float MinWidth = 0.f);
	/** Button that looks pressed while IsSelected is true (tabs, option groups). */
	TSharedRef<SWidget> MakeOption(const TAttribute<FText>& Label, const TAttribute<bool>& IsSelected, FOnClicked OnClicked, int32 FontSize = 18);
	TSharedRef<SWidget> MakeText(const TAttribute<FText>& Text, int32 Size = 18, const TAttribute<FSlateColor>& Color = FSlateColor(FLinearColor(0.92f, 0.92f, 0.92f)), bool bBold = false);
	TSharedRef<SWidget> MakePanel(const TSharedRef<SWidget>& Content, const FMargin& Padding = FMargin(24.f), const FLinearColor& Color = Panel());
	/** Slider mapped to [Min, Max]. */
	TSharedRef<SWidget> MakeSlider(const TAttribute<float>& Value, TFunction<void(float)> OnChanged, float Min, float Max);
	TSharedRef<SWidget> MakeCheck(const FText& Label, const TAttribute<bool>& IsChecked, TFunction<void(bool)> OnChanged);
	/** "Label  [widget]" row used by settings screens. */
	TSharedRef<SWidget> MakeRow(const FText& Label, const TSharedRef<SWidget>& Widget, float LabelWidth = 260.f);
}
