// Multi-touch on-screen controls (Slate, drawn procedurally - no texture assets).
//
// SPUBGTouchSurface tracks every finger independently (pointer index):
//   * a finger that starts on a button presses that button (Fire / ADS / FreeLook
//     can also be dragged to aim while held);
//   * a finger that starts in the lower-left zone drives the movement stick
//     (floating or fixed);
//   * any other finger drags the camera.
// In layout-edit mode fingers move controls instead, and the toolbar of
// SPUBGTouchControls resizes / hides / resets them.

#pragma once

#include "CoreMinimal.h"
#include "Widgets/SLeafWidget.h"
#include "Widgets/SCompoundWidget.h"
#include "Widgets/DeclarativeSyntaxSupport.h"

class UPUBGTouchInputComponent;

class PUBG_BLUEPRINT_API SPUBGTouchSurface : public SLeafWidget
{
public:
	SLATE_BEGIN_ARGS(SPUBGTouchSurface) {}
		SLATE_ARGUMENT(TWeakObjectPtr<UPUBGTouchInputComponent>, Input)
	SLATE_END_ARGS()

	void Construct(const FArguments& InArgs);

	virtual FVector2D ComputeDesiredSize(float LayoutScaleMultiplier) const override { return FVector2D(64.f, 64.f); }
	virtual int32 OnPaint(const FPaintArgs& Args, const FGeometry& AllottedGeometry, const FSlateRect& MyCullingRect,
		FSlateWindowElementList& OutDrawElements, int32 LayerId, const FWidgetStyle& InWidgetStyle, bool bParentEnabled) const override;
	virtual void Tick(const FGeometry& AllottedGeometry, const double InCurrentTime, const float InDeltaTime) override;
	virtual bool SupportsKeyboardFocus() const override { return false; }

	virtual FReply OnTouchStarted(const FGeometry& MyGeometry, const FPointerEvent& InTouchEvent) override;
	virtual FReply OnTouchMoved(const FGeometry& MyGeometry, const FPointerEvent& InTouchEvent) override;
	virtual FReply OnTouchEnded(const FGeometry& MyGeometry, const FPointerEvent& InTouchEvent) override;
	// Mouse fallback for desktop testing with a visible cursor.
	virtual FReply OnMouseButtonDown(const FGeometry& MyGeometry, const FPointerEvent& MouseEvent) override;
	virtual FReply OnMouseMove(const FGeometry& MyGeometry, const FPointerEvent& MouseEvent) override;
	virtual FReply OnMouseButtonUp(const FGeometry& MyGeometry, const FPointerEvent& MouseEvent) override;

	int32 GetSelectedControl() const { return SelectedControl; }
	void ClearPointers();

private:
	enum class ERole : uint8 { Control, Stick, Look, Edit };
	struct FPointer
	{
		ERole Role = ERole::Look;
		int32 Control = -1;
		FVector2D Last = FVector2D::ZeroVector;
		FVector2D GrabOffset = FVector2D::ZeroVector;
	};

	FReply HandleDown(const FGeometry& Geometry, int32 Pointer, const FVector2D& ScreenPosition);
	FReply HandleMove(const FGeometry& Geometry, int32 Pointer, const FVector2D& ScreenPosition);
	FReply HandleUp(int32 Pointer);
	int32 HitTest(const FVector2D& Local, const FVector2D& Size, bool bEditing) const;
	bool IsControlShown(int32 Index, bool bEditing) const;
	FVector2D CenterOf(int32 Index, const FVector2D& Size) const;
	float RadiusOf(int32 Index) const;
	void UpdateStick(const FVector2D& Local);

	TWeakObjectPtr<UPUBGTouchInputComponent> Input;
	TMap<int32, FPointer> Pointers;
	bool bStickHeld = false;
	FVector2D StickCenter = FVector2D::ZeroVector;
	FVector2D KnobOffset = FVector2D::ZeroVector;
	FVector2D LastSize = FVector2D(1920.f, 1080.f);
	int32 SelectedControl = -1;
	int32 SeenReleaseCounter = 0;
};

/** Safe-zone aware overlay: surface + "close bag" button + layout-edit toolbar. */
class PUBG_BLUEPRINT_API SPUBGTouchControls : public SCompoundWidget
{
public:
	SLATE_BEGIN_ARGS(SPUBGTouchControls) {}
		SLATE_ARGUMENT(TWeakObjectPtr<UPUBGTouchInputComponent>, Input)
	SLATE_END_ARGS()

	void Construct(const FArguments& InArgs);

private:
	FReply ModifySelected(TFunctionRef<void(struct FPUBGTouchControl&)> Change);

	TWeakObjectPtr<UPUBGTouchInputComponent> Input;
	TSharedPtr<SPUBGTouchSurface> Surface;
};
