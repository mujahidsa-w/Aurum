// Unreal automation tests for the multiplayer / mobile layer.
// Run in the editor: Window > Test Automation (Session Frontend) > filter "PUBG".
// Or headless: UnrealEditor-Cmd <Project>.uproject -ExecCmds="Automation RunTests PUBG; Quit" -unattended -nopause -nullrhi

#include "CoreMinimal.h"
#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS && WITH_EDITOR

#include "Core/PUBGTypes.h"
#include "Logic/PUBGNetLogic.h"
#include "Logic/PUBGTouchLayoutDefaults.h"
#include "Mobile/PUBGTouchKeys.h"
#include "Sessions/PUBGRoomServiceSubsystem.h"
#include "Sessions/PUBGSessionSubsystem.h"

#define PUBGTestFlags (EAutomationTestFlags::EditorContext | EAutomationTestFlags::ProductFilter)

// Same constants as Tools/RoomService/test/ticket-vector.test.js (also checked with Python's hmac).
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FPUBGTicketVectorTest, "PUBG.RoomService.TicketVector", PUBGTestFlags)
bool FPUBGTicketVectorTest::RunTest(const FString& Parameters)
{
	const FString Ticket = TEXT("cm9vbTQyfEFsaWNlfDE5OTk5OTk5OTk.855bb9674961ccfcdd6d9d54781ef24c4dc9250b");
	const FString Secret = TEXT("unit-test-secret");
	FString Error;
	TestTrue(TEXT("valid ticket accepted"), UPUBGRoomServiceSubsystem::VerifyTicketWithSecret(Ticket, Secret, TEXT("room42"), 1999999999, Error));
	TestFalse(TEXT("expired ticket rejected"), UPUBGRoomServiceSubsystem::VerifyTicketWithSecret(Ticket, Secret, TEXT("room42"), 2000000000, Error));
	TestFalse(TEXT("wrong secret rejected"), UPUBGRoomServiceSubsystem::VerifyTicketWithSecret(Ticket, TEXT("other"), TEXT("room42"), 1999999999, Error));
	TestFalse(TEXT("other room rejected"), UPUBGRoomServiceSubsystem::VerifyTicketWithSecret(Ticket, Secret, TEXT("room43"), 1999999999, Error));
	TestFalse(TEXT("empty ticket rejected"), UPUBGRoomServiceSubsystem::VerifyTicketWithSecret(FString(), Secret, TEXT("room42"), 1999999999, Error));
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FPUBGRoomOptionsTest, "PUBG.Sessions.RoomOptions", PUBGTestFlags)
bool FPUBGRoomOptionsTest::RunTest(const FString& Parameters)
{
	FPUBGRoomSettings In;
	In.RoomName = TEXT("Friday Night ?=& Squad");
	In.Password = TEXT("p@ss word?");
	In.MaxPlayers = 6;
	In.BattleMapIndex = 1;
	const FString Options = UPUBGSessionSubsystem::BuildRoomOptions(In);
	const FPUBGRoomSettings Out = UPUBGSessionSubsystem::ParseRoomOptions(Options);
	TestEqual(TEXT("room name survives URL options"), Out.RoomName, In.RoomName);
	TestEqual(TEXT("password survives URL options"), Out.Password, In.Password);
	TestEqual(TEXT("max players"), Out.MaxPlayers, 6);
	TestEqual(TEXT("battle map"), Out.BattleMapIndex, 1);
	TestFalse(TEXT("encoded options contain no raw spaces"), Options.Contains(TEXT(" ")));
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FPUBGHitValidationTest, "PUBG.Logic.HitValidationFVector", PUBGTestFlags)
bool FPUBGHitValidationTest::RunTest(const FString& Parameters)
{
	// Same logic as Tests/LogicTests, instantiated with FVector.
	PUBGLogic::FHitCheckTuning Tuning;
	const FVector Shooter(0, 0, 100), Origin(-250, 0, 160), Target(2000, 0, 100);
	TestTrue(TEXT("plausible hit"), PUBGLogic::ValidateHitGeometry(Shooter, Origin, FVector(1990, 10, 150), Target, FVector::ZeroVector, 34.f, 88.f, 0.1f, Tuning) == PUBGLogic::EHitCheck::Ok);
	TestTrue(TEXT("hit far from target"), PUBGLogic::ValidateHitGeometry(Shooter, Origin, FVector(1500, 0, 100), Target, FVector::ZeroVector, 34.f, 88.f, 0.1f, Tuning) == PUBGLogic::EHitCheck::TargetMismatch);
	TestTrue(TEXT("camera too far"), PUBGLogic::ValidateHitGeometry(Shooter, FVector(5000, 0, 0), FVector(1990, 10, 150), Target, FVector::ZeroVector, 34.f, 88.f, 0.1f, Tuning) == PUBGLogic::EHitCheck::OriginTooFar);
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FPUBGTouchKeysTest, "PUBG.Touch.KeysAndLayout", PUBGTestFlags)
bool FPUBGTouchKeysTest::RunTest(const FString& Parameters)
{
	TestTrue(TEXT("touch Fire key registered"), PUBGTouchKeys::Fire.IsValid());
	TestTrue(TEXT("touch MoveX is an axis"), PUBGTouchKeys::MoveX.IsValid() && PUBGTouchKeys::MoveX.IsAxis1D());
	TestTrue(TEXT("default layout has controls"), PUBGLogic::GTouchDefaultsCount >= 20);
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FPUBGSnapshotTest, "PUBG.Inventory.SnapshotEquality", PUBGTestFlags)
bool FPUBGSnapshotTest::RunTest(const FString& Parameters)
{
	FPUBGInventorySnapshot A;
	FPUBGItemRecord Rec;
	Rec.ItemType = (uint8)EPUBGItemType::Health;
	Rec.ID = TEXT("Bandage");
	Rec.Amount = 3;
	A.Items.Add(Rec);
	A.Weapon1ID = TEXT("M416");
	A.Weapon1Clip = 30;
	A.HeldSlot = 1;
	FPUBGInventorySnapshot B = A;
	TestTrue(TEXT("copies are equal"), A == B);
	B.Weapon1Clip = 29;
	TestTrue(TEXT("a fired bullet changes the snapshot"), A != B);
	return true;
}

#undef PUBGTestFlags

#endif // WITH_DEV_AUTOMATION_TESTS
