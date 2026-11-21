#include "UI/SPUBGSettingsPanel.h"

#include "Core/PUBGGameUserSettings.h"
#include "Mobile/PUBGTouchInputComponent.h"
#include "UI/PUBGUIStyle.h"

#include "GameFramework/PlayerController.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/Layout/SScrollBox.h"
#include "Widgets/Layout/SWidgetSwitcher.h"
#include "Widgets/SBoxPanel.h"

#define LOCTEXT_NAMESPACE "PUBGSettings"

namespace
{
	UPUBGGameUserSettings* S() { return UPUBGGameUserSettings::GetPUBGSettings(); }
}

void SPUBGSettingsPanel::Construct(const FArguments& InArgs)
{
	OwnerPC = InArgs._OwnerPC;
	OnEditLayout = InArgs._OnEditLayout;

	ChildSlot
	[
		SNew(SVerticalBox)
		+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 0.f, 0.f, 12.f)
		[
			SNew(SHorizontalBox)
			+ SHorizontalBox::Slot().AutoWidth().Padding(0.f, 0.f, 8.f, 0.f)
			[
				PUBGUI::MakeOption(LOCTEXT("Graphics", "GRAPHICS"), PUBGUI::Attr<bool>([this]() { return Tab == 0; }),
					FOnClicked::CreateLambda([this]() { Tab = 0; return FReply::Handled(); }))
			]
			+ SHorizontalBox::Slot().AutoWidth()
			[
				PUBGUI::MakeOption(LOCTEXT("Controls", "CONTROLS"), PUBGUI::Attr<bool>([this]() { return Tab == 1; }),
					FOnClicked::CreateLambda([this]() { Tab = 1; return FReply::Handled(); }))
			]
		]
		+ SVerticalBox::Slot().FillHeight(1.f)
		[
			SNew(SScrollBox)
			+ SScrollBox::Slot()
			[
				SNew(SWidgetSwitcher)
				.WidgetIndex_Lambda([this]() { return Tab; })
				+ SWidgetSwitcher::Slot() [ BuildGraphics() ]
				+ SWidgetSwitcher::Slot() [ BuildControls() ]
			]
		]
	];
}

TSharedRef<SWidget> SPUBGSettingsPanel::BuildGraphics()
{
	TSharedRef<SHorizontalBox> Presets = SNew(SHorizontalBox);
	const FText PresetNames[] = { LOCTEXT("Low", "LOW"), LOCTEXT("Medium", "MEDIUM"), LOCTEXT("High", "HIGH"), LOCTEXT("Ultra", "ULTRA") };
	for (int32 i = 0; i < 4; ++i)
	{
		Presets->AddSlot().AutoWidth().Padding(0.f, 0.f, 6.f, 0.f)
		[
			PUBGUI::MakeOption(PresetNames[i], PUBGUI::Attr<bool>([i]() { return (int32)S()->GetGraphicsPreset() == i; }),
				FOnClicked::CreateLambda([i]()
				{
					S()->SetGraphicsPreset((EPUBGGraphicsPreset)i);
					S()->ApplyPUBGSettings();
					return FReply::Handled();
				}), 16)
		];
	}

	TSharedRef<SHorizontalBox> FrameRates = SNew(SHorizontalBox);
	for (int32 Fps : UPUBGGameUserSettings::GetSupportedFrameRates())
	{
		FrameRates->AddSlot().AutoWidth().Padding(0.f, 0.f, 6.f, 0.f)
		[
			PUBGUI::MakeOption(FText::AsNumber(Fps), PUBGUI::Attr<bool>([Fps]() { return S()->GetFrameRateCap() == Fps; }),
				FOnClicked::CreateLambda([Fps]()
				{
					S()->SetFrameRateCap(Fps);
					S()->ApplyPUBGSettings();
					return FReply::Handled();
				}), 16)
		];
	}

	return SNew(SVerticalBox)
		+ SVerticalBox::Slot().AutoHeight() [ PUBGUI::MakeRow(LOCTEXT("Quality", "Graphics quality"), Presets) ]
		+ SVerticalBox::Slot().AutoHeight() [ PUBGUI::MakeRow(LOCTEXT("FPS", "Frame rate limit"), FrameRates) ]
		+ SVerticalBox::Slot().AutoHeight()
		[
			PUBGUI::MakeRow(LOCTEXT("RenderScale", "Render resolution"),
				SNew(SHorizontalBox)
				+ SHorizontalBox::Slot().AutoWidth()
				[
					PUBGUI::MakeSlider(PUBGUI::Attr<float>([]() { return S()->GetRenderScale(); }),
						[](float V) { S()->SetRenderScale(FMath::RoundToFloat(V * 20.f) / 20.f); S()->ApplyPUBGSettings(); }, 0.5f, 1.f)
				]
				+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center).Padding(12.f, 0.f)
				[
					PUBGUI::MakeText(PUBGUI::Attr<FText>([]() { return FText::FromString(FString::Printf(TEXT("%d%%"), FMath::RoundToInt(S()->GetRenderScale() * 100.f))); }), 18)
				])
		]
		+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 8.f)
		[
			PUBGUI::MakeCheck(LOCTEXT("ShowFps", "Show FPS counter"), PUBGUI::Attr<bool>([]() { return S()->bShowFPS; }),
				[](bool bOn) { S()->bShowFPS = bOn; S()->SaveSettings(); })
		]
		+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 12.f, 0.f, 0.f)
		[
			PUBGUI::MakeText(LOCTEXT("GraphicsHint", "Lower quality and 30 FPS reduce heat and battery use. 90/120 FPS only take effect on displays and devices that support them."), 14,
				FSlateColor(PUBGUI::Muted()))
		];
}

TSharedRef<SWidget> SPUBGSettingsPanel::BuildControls()
{
	TWeakObjectPtr<APlayerController> WeakPC = OwnerPC;
	FSimpleDelegate EditDelegate = OnEditLayout;
	auto PercentText = [](TFunction<float()> Getter)
	{
		return PUBGUI::MakeText(PUBGUI::Attr<FText>([Getter]() { return FText::FromString(FString::Printf(TEXT("%.2f"), Getter())); }), 18);
	};

	return SNew(SVerticalBox)
		+ SVerticalBox::Slot().AutoHeight()
		[
			PUBGUI::MakeRow(LOCTEXT("Look", "Camera sensitivity"),
				SNew(SHorizontalBox)
				+ SHorizontalBox::Slot().AutoWidth()
				[
					PUBGUI::MakeSlider(PUBGUI::Attr<float>([]() { return S()->LookSensitivity; }), [](float V) { S()->LookSensitivity = V; S()->SaveSettings(); }, 0.2f, 3.f)
				]
				+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center).Padding(12.f, 0.f) [ PercentText([]() { return S()->LookSensitivity; }) ])
		]
		+ SVerticalBox::Slot().AutoHeight()
		[
			PUBGUI::MakeRow(LOCTEXT("Aim", "Aiming sensitivity"),
				SNew(SHorizontalBox)
				+ SHorizontalBox::Slot().AutoWidth()
				[
					PUBGUI::MakeSlider(PUBGUI::Attr<float>([]() { return S()->AimSensitivity; }), [](float V) { S()->AimSensitivity = V; S()->SaveSettings(); }, 0.2f, 1.5f)
				]
				+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center).Padding(12.f, 0.f) [ PercentText([]() { return S()->AimSensitivity; }) ])
		]
		+ SVerticalBox::Slot().AutoHeight()
		[
			PUBGUI::MakeRow(LOCTEXT("Opacity", "Button opacity"),
				PUBGUI::MakeSlider(PUBGUI::Attr<float>([]() { return S()->TouchOpacity; }), [](float V) { S()->TouchOpacity = V; S()->SaveSettings(); }, 0.15f, 1.f))
		]
		+ SVerticalBox::Slot().AutoHeight()
		[
			PUBGUI::MakeRow(LOCTEXT("Size", "Button size"),
				PUBGUI::MakeSlider(PUBGUI::Attr<float>([]() { return S()->TouchScale; }), [](float V) { S()->TouchScale = V; S()->SaveSettings(); }, 0.7f, 1.4f))
		]
		+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 6.f)
		[
			PUBGUI::MakeCheck(LOCTEXT("Invert", "Invert vertical look"), PUBGUI::Attr<bool>([]() { return S()->bInvertLook; }),
				[](bool bOn) { S()->bInvertLook = bOn; S()->SaveSettings(); })
		]
		+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 6.f)
		[
			PUBGUI::MakeCheck(LOCTEXT("Floating", "Floating joystick (appears where you touch)"), PUBGUI::Attr<bool>([]() { return S()->bFloatingJoystick; }),
				[](bool bOn) { S()->bFloatingJoystick = bOn; S()->SaveSettings(); })
		]
		+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 6.f)
		[
			PUBGUI::MakeCheck(LOCTEXT("AnalogWalk", "Walk when the joystick is pushed lightly"), PUBGUI::Attr<bool>([]() { return S()->bAnalogWalk; }),
				[](bool bOn) { S()->bAnalogWalk = bOn; S()->SaveSettings(); })
		]
		+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 6.f)
		[
			PUBGUI::MakeCheck(LOCTEXT("SprintGesture", "Push the joystick far up to lock sprint"), PUBGUI::Attr<bool>([]() { return S()->bSprintGesture; }),
				[](bool bOn) { S()->bSprintGesture = bOn; S()->SaveSettings(); })
		]
		+ SVerticalBox::Slot().AutoHeight().Padding(0.f, 14.f, 0.f, 0.f)
		[
			SNew(SHorizontalBox)
			+ SHorizontalBox::Slot().AutoWidth().Padding(0.f, 0.f, 8.f, 0.f)
			[
				SNew(SBox)
				.Visibility_Lambda([WeakPC, EditDelegate]()
				{
					return (WeakPC.IsValid() && EditDelegate.IsBound() && UPUBGTouchInputComponent::ShouldUseTouchControls()) ? EVisibility::Visible : EVisibility::Collapsed;
				})
				[
					PUBGUI::MakeButton(LOCTEXT("EditLayout", "EDIT BUTTON LAYOUT"), FOnClicked::CreateLambda([EditDelegate]()
					{
						EditDelegate.ExecuteIfBound();
						return FReply::Handled();
					}), true, true, 18)
				]
			]
			+ SHorizontalBox::Slot().AutoWidth()
			[
				PUBGUI::MakeButton(LOCTEXT("ResetLayout", "RESET BUTTON LAYOUT"), FOnClicked::CreateLambda([WeakPC]()
				{
					if (WeakPC.IsValid())
					{
						if (UPUBGTouchInputComponent* Touch = WeakPC->FindComponentByClass<UPUBGTouchInputComponent>())
						{
							Touch->ResetLayout();
							return FReply::Handled();
						}
					}
					UPUBGGameUserSettings::GetPUBGSettings()->TouchLayout.Reset();
					UPUBGGameUserSettings::GetPUBGSettings()->SaveSettings();
					return FReply::Handled();
				}), true, false, 18)
			]
		];
}

#undef LOCTEXT_NAMESPACE
