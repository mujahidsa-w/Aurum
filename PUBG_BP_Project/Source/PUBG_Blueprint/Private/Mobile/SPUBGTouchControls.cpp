#include "Mobile/SPUBGTouchControls.h"

#include "Mobile/PUBGTouchInputComponent.h"
#include "Logic/PUBGNetLogic.h"
#include "Logic/PUBGTouchLayoutDefaults.h"
#include "UI/PUBGUIStyle.h"

#include "Fonts/FontMeasure.h"
#include "Framework/Application/SlateApplication.h"
#include "Rendering/DrawElements.h"
#include "Rendering/SlateRenderer.h"
#include "Styling/CoreStyle.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/Layout/SSafeZone.h"
#include "Widgets/SBoxPanel.h"
#include "Widgets/SOverlay.h"

#define LOCTEXT_NAMESPACE "PUBGTouch"

namespace
{
	constexpr int32 MousePointer = 1000;
	constexpr float StickDeadZone = 0.12f;
	const FName MoveId(TEXT("Move"));
	const FName MenuId(TEXT("Menu"));
	const FName PickupId(TEXT("Pickup"));

	bool IsDragToAimControl(FName Id)
	{
		return Id == TEXT("Fire") || Id == TEXT("FireLeft") || Id == TEXT("ADS") || Id == TEXT("FreeLook");
	}
}

// ---------------------------------------------------------------------------
// SPUBGTouchSurface
// ---------------------------------------------------------------------------

void SPUBGTouchSurface::Construct(const FArguments& InArgs)
{
	Input = InArgs._Input;
}

bool SPUBGTouchSurface::IsControlShown(int32 Index, bool bEditing) const
{
	const UPUBGTouchInputComponent* In = Input.Get();
	if (!In || !In->GetControls().IsValidIndex(Index))
	{
		return false;
	}
	const FPUBGTouchControl& Control = In->GetControls()[Index];
	if (bEditing)
	{
		return true;
	}
	if (!Control.bVisible)
	{
		return false;
	}
	if (In->IsPlayerDead())
	{
		return Control.Id == MenuId;
	}
	if (Control.Id == PickupId)
	{
		return In->IsPickupAvailable();
	}
	return true;
}

FVector2D SPUBGTouchSurface::CenterOf(int32 Index, const FVector2D& Size) const
{
	const FPUBGTouchControl& Control = Input->GetControls()[Index];
	return FVector2D(Control.Position.X * Size.X, Control.Position.Y * Size.Y);
}

float SPUBGTouchSurface::RadiusOf(int32 Index) const
{
	const FPUBGTouchControl& Control = Input->GetControls()[Index];
	return Control.Radius * Control.Scale * Input->GetGlobalScale();
}

int32 SPUBGTouchSurface::HitTest(const FVector2D& Local, const FVector2D& Size, bool bEditing) const
{
	const UPUBGTouchInputComponent* In = Input.Get();
	if (!In)
	{
		return -1;
	}
	int32 Best = -1;
	float BestDistance = TNumericLimits<float>::Max();
	for (int32 i = 0; i < In->GetControls().Num(); ++i)
	{
		if (!IsControlShown(i, bEditing) || (!bEditing && In->GetControls()[i].Id == MoveId))
		{
			continue;
		}
		const float Distance = FVector2D::Distance(Local, CenterOf(i, Size));
		// Slightly larger than drawn: fingers are imprecise.
		if (Distance <= RadiusOf(i) * 1.15f && Distance < BestDistance)
		{
			Best = i;
			BestDistance = Distance;
		}
	}
	return Best;
}

void SPUBGTouchSurface::Tick(const FGeometry& AllottedGeometry, const double InCurrentTime, const float InDeltaTime)
{
	SLeafWidget::Tick(AllottedGeometry, InCurrentTime, InDeltaTime);
	LastSize = AllottedGeometry.GetLocalSize();
	if (const UPUBGTouchInputComponent* In = Input.Get())
	{
		if (In->GetReleaseCounter() != SeenReleaseCounter)
		{
			// Input was released while hidden (inventory, menu, death): forget the fingers.
			SeenReleaseCounter = In->GetReleaseCounter();
			Pointers.Reset();
			bStickHeld = false;
			KnobOffset = FVector2D::ZeroVector;
		}
	}
}

void SPUBGTouchSurface::ClearPointers()
{
	if (UPUBGTouchInputComponent* In = Input.Get())
	{
		for (const TPair<int32, FPointer>& Pair : Pointers)
		{
			if (Pair.Value.Role == ERole::Control)
			{
				In->ReleaseControl(Pair.Value.Control);
			}
			else if (Pair.Value.Role == ERole::Stick)
			{
				In->ReleaseStick();
			}
		}
	}
	Pointers.Reset();
	bStickHeld = false;
	KnobOffset = FVector2D::ZeroVector;
}

void SPUBGTouchSurface::UpdateStick(const FVector2D& Local)
{
	UPUBGTouchInputComponent* In = Input.Get();
	const int32 MoveIndex = In ? In->FindControl(MoveId) : INDEX_NONE;
	if (!In || MoveIndex == INDEX_NONE)
	{
		return;
	}
	const float Radius = RadiusOf(MoveIndex);
	const FVector2D Offset = Local - StickCenter;
	const PUBGLogic::FStickOutput Out = PUBGLogic::ProcessJoystick(Offset.X, Offset.Y, Radius, StickDeadZone);
	KnobOffset = Offset.GetClampedToMaxSize(Radius);
	In->SetStick(Out.X, Out.Y, Out.Magnitude, PUBGLogic::IsSprintGesture(Offset.X, Offset.Y, Radius));
}

FReply SPUBGTouchSurface::HandleDown(const FGeometry& Geometry, int32 Pointer, const FVector2D& ScreenPosition)
{
	UPUBGTouchInputComponent* In = Input.Get();
	if (!In || Pointers.Contains(Pointer))
	{
		return FReply::Unhandled();
	}
	const FVector2D Size = Geometry.GetLocalSize();
	const FVector2D Local = Geometry.AbsoluteToLocal(ScreenPosition);

	if (In->IsEditingLayout())
	{
		const int32 Hit = HitTest(Local, Size, true);
		if (Hit < 0)
		{
			return FReply::Unhandled();
		}
		SelectedControl = Hit;
		FPointer P;
		P.Role = ERole::Edit;
		P.Control = Hit;
		P.Last = Local;
		P.GrabOffset = CenterOf(Hit, Size) - Local;
		Pointers.Add(Pointer, P);
		return FReply::Handled().CaptureMouse(SharedThis(this));
	}

	const int32 Hit = HitTest(Local, Size, false);
	if (Hit >= 0)
	{
		FPointer P;
		P.Role = ERole::Control;
		P.Control = Hit;
		P.Last = Local;
		Pointers.Add(Pointer, P);
		In->PressControl(Hit);
		return FReply::Handled().CaptureMouse(SharedThis(this));
	}
	if (In->IsPlayerDead())
	{
		return FReply::Unhandled();
	}

	const int32 MoveIndex = In->FindControl(MoveId);
	const bool bInStickZone = Local.X < PUBGLogic::GJoystickZoneMaxX * Size.X && Local.Y > PUBGLogic::GJoystickZoneMinY * Size.Y;
	if (!bStickHeld && MoveIndex != INDEX_NONE && bInStickZone)
	{
		bStickHeld = true;
		if (In->IsFloatingStick())
		{
			// Keep the whole base on screen.
			const float Radius = RadiusOf(MoveIndex);
			StickCenter = FVector2D(FMath::Clamp(Local.X, Radius, Size.X - Radius), FMath::Clamp(Local.Y, Radius, Size.Y - Radius));
		}
		else
		{
			StickCenter = CenterOf(MoveIndex, Size);
		}
		FPointer P;
		P.Role = ERole::Stick;
		P.Control = MoveIndex;
		P.Last = Local;
		Pointers.Add(Pointer, P);
		UpdateStick(Local);
		return FReply::Handled().CaptureMouse(SharedThis(this));
	}

	FPointer P;
	P.Role = ERole::Look;
	P.Last = Local;
	Pointers.Add(Pointer, P);
	return FReply::Handled().CaptureMouse(SharedThis(this));
}

FReply SPUBGTouchSurface::HandleMove(const FGeometry& Geometry, int32 Pointer, const FVector2D& ScreenPosition)
{
	UPUBGTouchInputComponent* In = Input.Get();
	FPointer* P = Pointers.Find(Pointer);
	if (!In || !P)
	{
		return FReply::Unhandled();
	}
	const FVector2D Size = Geometry.GetLocalSize();
	const FVector2D Local = Geometry.AbsoluteToLocal(ScreenPosition);
	const FVector2D Delta = Local - P->Last;
	P->Last = Local;

	switch (P->Role)
	{
	case ERole::Control:
		if (In->GetControls().IsValidIndex(P->Control) && IsDragToAimControl(In->GetControls()[P->Control].Id))
		{
			In->AddLookDelta(Delta); // drag the fire / aim button to aim while shooting
		}
		break;
	case ERole::Stick:
		UpdateStick(Local);
		break;
	case ERole::Look:
		In->AddLookDelta(Delta);
		break;
	case ERole::Edit:
		if (In->GetControls().IsValidIndex(P->Control))
		{
			FPUBGTouchControl& Control = In->GetControls()[P->Control];
			const FVector2D NewCenter = Local + P->GrabOffset;
			float NX = Size.X > 0.f ? NewCenter.X / Size.X : 0.5f;
			float NY = Size.Y > 0.f ? NewCenter.Y / Size.Y : 0.5f;
			PUBGLogic::ClampControlCenter(NX, NY, RadiusOf(P->Control), Size.X, Size.Y);
			Control.Position = FVector2D(NX, NY);
		}
		break;
	}
	return FReply::Handled();
}

FReply SPUBGTouchSurface::HandleUp(int32 Pointer)
{
	FPointer P;
	if (!Pointers.RemoveAndCopyValue(Pointer, P))
	{
		return FReply::Unhandled();
	}
	if (UPUBGTouchInputComponent* In = Input.Get())
	{
		if (P.Role == ERole::Control)
		{
			In->ReleaseControl(P.Control);
		}
		else if (P.Role == ERole::Stick)
		{
			In->ReleaseStick();
			bStickHeld = false;
			KnobOffset = FVector2D::ZeroVector;
		}
	}
	return FReply::Handled().ReleaseMouseCapture();
}

FReply SPUBGTouchSurface::OnTouchStarted(const FGeometry& MyGeometry, const FPointerEvent& InTouchEvent)
{
	return HandleDown(MyGeometry, (int32)InTouchEvent.GetPointerIndex(), InTouchEvent.GetScreenSpacePosition());
}

FReply SPUBGTouchSurface::OnTouchMoved(const FGeometry& MyGeometry, const FPointerEvent& InTouchEvent)
{
	return HandleMove(MyGeometry, (int32)InTouchEvent.GetPointerIndex(), InTouchEvent.GetScreenSpacePosition());
}

FReply SPUBGTouchSurface::OnTouchEnded(const FGeometry& MyGeometry, const FPointerEvent& InTouchEvent)
{
	return HandleUp((int32)InTouchEvent.GetPointerIndex());
}

FReply SPUBGTouchSurface::OnMouseButtonDown(const FGeometry& MyGeometry, const FPointerEvent& MouseEvent)
{
	if (MouseEvent.GetEffectingButton() != EKeys::LeftMouseButton)
	{
		return FReply::Unhandled();
	}
	return HandleDown(MyGeometry, MousePointer, MouseEvent.GetScreenSpacePosition());
}

FReply SPUBGTouchSurface::OnMouseMove(const FGeometry& MyGeometry, const FPointerEvent& MouseEvent)
{
	return Pointers.Contains(MousePointer) ? HandleMove(MyGeometry, MousePointer, MouseEvent.GetScreenSpacePosition()) : FReply::Unhandled();
}

FReply SPUBGTouchSurface::OnMouseButtonUp(const FGeometry& MyGeometry, const FPointerEvent& MouseEvent)
{
	return MouseEvent.GetEffectingButton() == EKeys::LeftMouseButton ? HandleUp(MousePointer) : FReply::Unhandled();
}

int32 SPUBGTouchSurface::OnPaint(const FPaintArgs& Args, const FGeometry& AllottedGeometry, const FSlateRect& MyCullingRect,
	FSlateWindowElementList& OutDrawElements, int32 LayerId, const FWidgetStyle& InWidgetStyle, bool bParentEnabled) const
{
	const UPUBGTouchInputComponent* In = Input.Get();
	if (!In || !In->GetCircleBrush()->GetResourceObject())
	{
		return LayerId;
	}
	const FVector2D Size = AllottedGeometry.GetLocalSize();
	const bool bEditing = In->IsEditingLayout();
	const float Opacity = In->GetOpacity();
	const FLinearColor Accent = PUBGUI::Accent();
	const TSharedRef<FSlateFontMeasure> FontMeasure = FSlateApplication::Get().GetRenderer()->GetFontMeasureService();
	const FSlateFontInfo BaseFont = FCoreStyle::GetDefaultFontStyle(TEXT("Bold"), 14);

	auto DrawCircle = [&](const FVector2D& Center, float Radius, const FSlateBrush* Brush, const FLinearColor& Color, int32 Layer)
	{
		FSlateDrawElement::MakeBox(OutDrawElements, Layer,
			AllottedGeometry.ToPaintGeometry(Center - FVector2D(Radius, Radius), FVector2D(Radius * 2.f, Radius * 2.f)),
			Brush, ESlateDrawEffect::None, Color);
	};
	auto DrawLabel = [&](const FVector2D& Center, const FString& Text, int32 FontSize, const FLinearColor& Color, int32 Layer)
	{
		if (Text.IsEmpty())
		{
			return;
		}
		FSlateFontInfo Font = BaseFont;
		Font.Size = FontSize;
		const FVector2D TextSize = FontMeasure->Measure(Text, Font);
		FSlateDrawElement::MakeText(OutDrawElements, Layer, AllottedGeometry.ToPaintGeometry(Center - TextSize * 0.5f, TextSize),
			Text, Font, ESlateDrawEffect::None, Color);
	};

	if (bEditing)
	{
		FSlateDrawElement::MakeBox(OutDrawElements, LayerId, AllottedGeometry.ToPaintGeometry(), PUBGUI::WhiteBrush(),
			ESlateDrawEffect::None, FLinearColor(0.f, 0.f, 0.f, 0.35f));
		// Movement-stick zone outline hint
		DrawLabel(FVector2D(Size.X * PUBGLogic::GJoystickZoneMaxX * 0.5f, Size.Y * PUBGLogic::GJoystickZoneMinY + 18.f),
			TEXT("movement zone"), 12, PUBGUI::Muted(), LayerId + 1);
	}

	for (int32 i = 0; i < In->GetControls().Num(); ++i)
	{
		if (!IsControlShown(i, bEditing))
		{
			continue;
		}
		const FPUBGTouchControl& Control = In->GetControls()[i];
		const FVector2D Center = CenterOf(i, Size);
		const float Radius = RadiusOf(i);
		const float Alpha = (Control.bVisible ? 1.f : 0.4f) * Opacity;

		if (Control.Id == MoveId)
		{
			const FVector2D Base = (bStickHeld && !bEditing) ? StickCenter : Center;
			DrawCircle(Base, Radius, In->GetCircleBrush(), FLinearColor(0.f, 0.f, 0.f, 0.25f * Alpha), LayerId + 1);
			DrawCircle(Base, Radius, In->GetRingBrush(), FLinearColor(1.f, 1.f, 1.f, 0.55f * Alpha), LayerId + 2);
			const FLinearColor KnobColor = (bStickHeld ? Accent : FLinearColor::White).CopyWithNewOpacity(0.8f * Alpha);
			DrawCircle(Base + KnobOffset, Radius * 0.42f, In->GetCircleBrush(), KnobColor, LayerId + 3);
			if (In->IsSprintLocked())
			{
				DrawLabel(Base - FVector2D(0.f, Radius + 18.f), TEXT("SPRINT LOCKED"), 14, Accent, LayerId + 3);
			}
			if (bEditing && i == SelectedControl)
			{
				DrawCircle(Base, Radius + 4.f, In->GetRingBrush(), Accent, LayerId + 3);
			}
			continue;
		}

		const bool bActive = Control.bPressed || Control.bToggledOn;
		const FLinearColor Fill = bActive ? Accent.CopyWithNewOpacity(0.6f * Alpha) : FLinearColor(0.f, 0.f, 0.f, 0.38f * Alpha);
		const FLinearColor Ring = (bEditing && i == SelectedControl) ? Accent : FLinearColor(1.f, 1.f, 1.f, 0.8f * Alpha);
		DrawCircle(Center, Radius, In->GetCircleBrush(), Fill, LayerId + 1);
		DrawCircle(Center, Radius, In->GetRingBrush(), Ring, LayerId + 2);

		const int32 FontSize = FMath::Clamp(FMath::RoundToInt(Radius * 0.34f), 10, 22);
		DrawLabel(Center, Control.Label, FontSize, FLinearColor(1.f, 1.f, 1.f, FMath::Max(0.7f, Alpha)), LayerId + 3);
		if (Control.Id == PickupId && !In->GetPickupLabel().IsEmpty() && !bEditing)
		{
			DrawLabel(Center + FVector2D(0.f, Radius + 14.f), In->GetPickupLabel(), 13, FLinearColor::White, LayerId + 3);
		}
		if (bEditing && !Control.bVisible)
		{
			DrawLabel(Center + FVector2D(0.f, Radius + 12.f), TEXT("hidden"), 11, PUBGUI::Muted(), LayerId + 3);
		}
	}
	return LayerId + 4;
}

// ---------------------------------------------------------------------------
// SPUBGTouchControls
// ---------------------------------------------------------------------------

FReply SPUBGTouchControls::ModifySelected(TFunctionRef<void(FPUBGTouchControl&)> Change)
{
	UPUBGTouchInputComponent* In = Input.Get();
	const int32 Selected = Surface.IsValid() ? Surface->GetSelectedControl() : INDEX_NONE;
	if (In && In->GetControls().IsValidIndex(Selected))
	{
		Change(In->GetControls()[Selected]);
	}
	return FReply::Handled();
}

void SPUBGTouchControls::Construct(const FArguments& InArgs)
{
	Input = InArgs._Input;
	TWeakObjectPtr<UPUBGTouchInputComponent> Weak = Input;

	auto ToolbarButton = [this](const FText& Label, TFunction<FReply()> OnClick)
	{
		return PUBGUI::MakeButton(Label, FOnClicked::CreateLambda(OnClick), true, false, 16);
	};

	ChildSlot
	[
		SNew(SOverlay)
		+ SOverlay::Slot()
		[
			SNew(SSafeZone)
			.IsTitleSafe(true)
			[
				SAssignNew(Surface, SPUBGTouchSurface)
				.Input(Input)
				.Visibility_Lambda([Weak]()
				{
					return (Weak.IsValid() && !Weak->IsInventoryOpen()) ? EVisibility::Visible : EVisibility::Collapsed;
				})
			]
		]
		// The original inventory has no close button: offer one on touch screens.
		+ SOverlay::Slot()
		.HAlign(HAlign_Right)
		.VAlign(VAlign_Top)
		.Padding(FMargin(0.f, 40.f, 60.f, 0.f))
		[
			SNew(SBox)
			.Visibility_Lambda([Weak]() { return (Weak.IsValid() && Weak->IsInventoryOpen()) ? EVisibility::Visible : EVisibility::Collapsed; })
			[
				PUBGUI::MakeButton(LOCTEXT("CloseBag", "CLOSE BAG"), FOnClicked::CreateLambda([Weak]()
				{
					if (UPUBGTouchInputComponent* In = Weak.Get())
					{
						In->TapInventory();
					}
					return FReply::Handled();
				}), true, true, 20)
			]
		]
		// Layout editor toolbar
		+ SOverlay::Slot()
		.HAlign(HAlign_Center)
		.VAlign(VAlign_Top)
		.Padding(FMargin(0.f, 24.f, 0.f, 0.f))
		[
			SNew(SBox)
			.Visibility_Lambda([Weak]() { return (Weak.IsValid() && Weak->IsEditingLayout()) ? EVisibility::Visible : EVisibility::Collapsed; })
			[
				PUBGUI::MakePanel(
					SNew(SVerticalBox)
					+ SVerticalBox::Slot().AutoHeight().HAlign(HAlign_Center).Padding(0.f, 0.f, 0.f, 10.f)
					[
						PUBGUI::MakeText(LOCTEXT("EditHint", "Drag a control to move it, then select it to resize or hide it."), 16)
					]
					+ SVerticalBox::Slot().AutoHeight()
					[
						SNew(SHorizontalBox)
						+ SHorizontalBox::Slot().AutoWidth().Padding(4.f)
						[
							ToolbarButton(LOCTEXT("Smaller", "SMALLER"), [this]() { return ModifySelected([](FPUBGTouchControl& C) { C.Scale = FMath::Max(0.6f, C.Scale - 0.1f); }); })
						]
						+ SHorizontalBox::Slot().AutoWidth().Padding(4.f)
						[
							ToolbarButton(LOCTEXT("Bigger", "BIGGER"), [this]() { return ModifySelected([](FPUBGTouchControl& C) { C.Scale = FMath::Min(1.8f, C.Scale + 0.1f); }); })
						]
						+ SHorizontalBox::Slot().AutoWidth().Padding(4.f)
						[
							ToolbarButton(LOCTEXT("ShowHide", "SHOW / HIDE"), [this]()
							{
								return ModifySelected([](FPUBGTouchControl& C)
								{
									if (C.Id != MoveId && C.Id != MenuId)
									{
										C.bVisible = !C.bVisible;
									}
								});
							})
						]
						+ SHorizontalBox::Slot().AutoWidth().Padding(4.f)
						[
							ToolbarButton(LOCTEXT("Reset", "RESET"), [Weak]()
							{
								if (UPUBGTouchInputComponent* In = Weak.Get())
								{
									In->ResetLayout();
								}
								return FReply::Handled();
							})
						]
						+ SHorizontalBox::Slot().AutoWidth().Padding(4.f)
						[
							PUBGUI::MakeButton(LOCTEXT("Done", "SAVE"), FOnClicked::CreateLambda([Weak]()
							{
								if (UPUBGTouchInputComponent* In = Weak.Get())
								{
									In->SetEditingLayout(false);
								}
								return FReply::Handled();
							}), true, true, 16)
						]
					], FMargin(16.f))
			]
		]
	];
}

#undef LOCTEXT_NAMESPACE
