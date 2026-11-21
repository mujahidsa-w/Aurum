#include "UI/PUBGUIStyle.h"

#include "Brushes/SlateColorBrush.h"
#include "Styling/CoreStyle.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/Input/SCheckBox.h"
#include "Widgets/Input/SSlider.h"
#include "Widgets/Layout/SBorder.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/SBoxPanel.h"
#include "Widgets/Text/STextBlock.h"

namespace PUBGUI
{
	FLinearColor Accent() { return FLinearColor(0.96f, 0.62f, 0.10f, 1.f); }
	FLinearColor Panel() { return FLinearColor(0.035f, 0.04f, 0.05f, 0.88f); }
	FLinearColor PanelLight() { return FLinearColor(0.11f, 0.12f, 0.14f, 0.92f); }
	FLinearColor Backdrop() { return FLinearColor(0.f, 0.f, 0.f, 0.55f); }
	FLinearColor TextColor() { return FLinearColor(0.92f, 0.92f, 0.92f, 1.f); }
	FLinearColor Muted() { return FLinearColor(0.6f, 0.62f, 0.66f, 1.f); }
	FLinearColor Danger() { return FLinearColor(0.9f, 0.25f, 0.2f, 1.f); }
	FLinearColor Success() { return FLinearColor(0.35f, 0.8f, 0.4f, 1.f); }

	const FSlateBrush* WhiteBrush()
	{
		return FCoreStyle::Get().GetBrush(TEXT("GenericWhiteBox"));
	}

	FSlateFontInfo Font(int32 Size, bool bBold)
	{
		return FCoreStyle::GetDefaultFontStyle(bBold ? TEXT("Bold") : TEXT("Regular"), Size);
	}

	namespace
	{
		FButtonStyle MakeStyle(const FLinearColor& Normal, const FLinearColor& Hovered, const FLinearColor& Pressed)
		{
			FButtonStyle Style = FCoreStyle::Get().GetWidgetStyle<FButtonStyle>(TEXT("Button"));
			Style.SetNormal(FSlateColorBrush(Normal));
			Style.SetHovered(FSlateColorBrush(Hovered));
			Style.SetPressed(FSlateColorBrush(Pressed));
			Style.SetDisabled(FSlateColorBrush(FLinearColor(0.08f, 0.08f, 0.09f, 0.7f)));
			Style.SetNormalPadding(FMargin(18.f, 12.f));
			Style.SetPressedPadding(FMargin(18.f, 13.f, 18.f, 11.f));
			return Style;
		}
	}

	const FButtonStyle& ButtonStyle(bool bAccent)
	{
		static const FButtonStyle Normal = MakeStyle(FLinearColor(0.16f, 0.17f, 0.2f, 0.95f), FLinearColor(0.24f, 0.25f, 0.29f, 1.f), FLinearColor(0.10f, 0.10f, 0.12f, 1.f));
		static const FButtonStyle Strong = MakeStyle(FLinearColor(0.85f, 0.52f, 0.06f, 1.f), FLinearColor(0.98f, 0.64f, 0.14f, 1.f), FLinearColor(0.65f, 0.38f, 0.04f, 1.f));
		return bAccent ? Strong : Normal;
	}

	const FButtonStyle& SelectedButtonStyle()
	{
		// Light grey brushes, tinted per state through SButton::ButtonColorAndOpacity.
		static const FButtonStyle Tintable = MakeStyle(FLinearColor(0.8f, 0.8f, 0.8f, 1.f), FLinearColor(1.f, 1.f, 1.f, 1.f), FLinearColor(0.6f, 0.6f, 0.6f, 1.f));
		return Tintable;
	}

	TSharedRef<SWidget> MakeButton(const TAttribute<FText>& Label, FOnClicked OnClicked, const TAttribute<bool>& Enabled, bool bAccent, int32 FontSize, float MinWidth)
	{
		return SNew(SBox)
			.MinDesiredWidth(MinWidth > 0.f ? FOptionalSize(MinWidth) : FOptionalSize())
			[
				SNew(SButton)
				.ButtonStyle(&ButtonStyle(bAccent))
				.HAlign(HAlign_Center)
				.VAlign(VAlign_Center)
				.IsEnabled(Enabled)
				.OnClicked(OnClicked)
				[
					SNew(STextBlock)
					.Text(Label)
					.Font(Font(FontSize, true))
					.ColorAndOpacity(FSlateColor(bAccent ? FLinearColor(0.05f, 0.05f, 0.05f) : TextColor()))
				]
			];
	}

	TSharedRef<SWidget> MakeOption(const TAttribute<FText>& Label, const TAttribute<bool>& IsSelected, FOnClicked OnClicked, int32 FontSize)
	{
		TAttribute<bool> Selected = IsSelected;
		return SNew(SButton)
			.ButtonStyle(&SelectedButtonStyle())
			.ButtonColorAndOpacity_Lambda([Selected]()
			{
				return Selected.Get() ? FSlateColor(FLinearColor(0.72f, 0.44f, 0.06f, 1.f)) : FSlateColor(FLinearColor(0.2f, 0.21f, 0.25f, 0.95f));
			})
			.HAlign(HAlign_Center)
			.VAlign(VAlign_Center)
			.OnClicked(OnClicked)
			[
				SNew(STextBlock)
				.Text(Label)
				.Font(Font(FontSize, true))
				.ColorAndOpacity(FSlateColor(TextColor()))
			];
	}

	TSharedRef<SWidget> MakeText(const TAttribute<FText>& Text, int32 Size, const TAttribute<FSlateColor>& Color, bool bBold)
	{
		return SNew(STextBlock)
			.Text(Text)
			.Font(Font(Size, bBold))
			.ColorAndOpacity(Color)
			.AutoWrapText(true);
	}

	TSharedRef<SWidget> MakePanel(const TSharedRef<SWidget>& Content, const FMargin& Padding, const FLinearColor& Color)
	{
		return SNew(SBorder)
			.BorderImage(WhiteBrush())
			.BorderBackgroundColor(FSlateColor(Color))
			.Padding(Padding)
			[
				Content
			];
	}

	TSharedRef<SWidget> MakeSlider(const TAttribute<float>& Value, TFunction<void(float)> OnChanged, float Min, float Max)
	{
		TAttribute<float> Source = Value;
		return SNew(SBox)
			.MinDesiredWidth(320.f)
			.HeightOverride(44.f)
			[
				SNew(SSlider)
				.Value_Lambda([Source, Min, Max]() { return Max > Min ? (Source.Get() - Min) / (Max - Min) : 0.f; })
				.OnValueChanged_Lambda([OnChanged, Min, Max](float Normalized) { if (OnChanged) { OnChanged(Min + Normalized * (Max - Min)); } })
			];
	}

	TSharedRef<SWidget> MakeCheck(const FText& Label, const TAttribute<bool>& IsChecked, TFunction<void(bool)> OnChanged)
	{
		TAttribute<bool> Source = IsChecked;
		return SNew(SCheckBox)
			.IsChecked_Lambda([Source]() { return Source.Get() ? ECheckBoxState::Checked : ECheckBoxState::Unchecked; })
			.OnCheckStateChanged_Lambda([OnChanged](ECheckBoxState State) { if (OnChanged) { OnChanged(State == ECheckBoxState::Checked); } })
			[
				SNew(STextBlock)
				.Text(Label)
				.Font(Font(18, false))
				.ColorAndOpacity(FSlateColor(TextColor()))
			];
	}

	TSharedRef<SWidget> MakeRow(const FText& Label, const TSharedRef<SWidget>& Widget, float LabelWidth)
	{
		return SNew(SHorizontalBox)
			+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center).Padding(0.f, 6.f, 16.f, 6.f)
			[
				SNew(SBox).WidthOverride(LabelWidth)
				[
					SNew(STextBlock).Text(Label).Font(Font(18, false)).ColorAndOpacity(FSlateColor(Muted()))
				]
			]
			+ SHorizontalBox::Slot().FillWidth(1.f).VAlign(VAlign_Center).Padding(0.f, 6.f)
			[
				Widget
			];
	}
}
