// Standalone unit tests for PUBGNetLogic.h and PUBGTouchLayoutDefaults.h.
// Build: g++ -std=c++17 -Wall -Wextra -Werror -I../../PUBG_BP_Project/Source/PUBG_Blueprint/Public test_logic.cpp -o test_logic
#include "Logic/PUBGNetLogic.h"
#include "Logic/PUBGTouchLayoutDefaults.h"
#include <cstdio>
#include <cstring>
#include <cmath>

using namespace PUBGLogic;

static int GFailures = 0, GChecks = 0;
#define CHECK(cond) do { ++GChecks; if (!(cond)) { ++GFailures; std::printf("FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond); } } while (0)
#define CHECK_NEAR(a, b, eps) CHECK(std::fabs((a) - (b)) <= (eps))

struct V3 { float X, Y, Z; };

static void TestFireRate()
{
	FFireRateLimiter L;
	// Steady fire exactly at the weapon interval (0.1 s) must always pass.
	int Accepted = 0;
	for (int i = 0; i < 50; ++i) Accepted += L.TryConsume(i * 0.1, 0.1f) ? 1 : 0;
	CHECK(Accepted == 50);

	// Firing 3x faster than allowed: only burst + refill may pass.
	L.Reset();
	Accepted = 0;
	for (int i = 0; i < 30; ++i) Accepted += L.TryConsume(i * (0.1 / 3.0), 0.1f) ? 1 : 0;
	// Elapsed ~0.97 s, refill rate 1/(0.08 s) => at most ~1 + 12 shots.
	CHECK(Accepted <= 14);
	CHECK(Accepted >= 10);

	// Jitter: two packets arriving in the same frame after a pause are accepted.
	L.Reset();
	CHECK(L.TryConsume(0.0, 0.1f));
	CHECK(L.TryConsume(0.5, 0.1f));
	CHECK(L.TryConsume(0.5, 0.1f));
	CHECK(!L.TryConsume(0.5, 0.1f)); // burst capped at 2
}

static void TestMagazine()
{
	FMagazineTracker M;
	M.ClipSize = 5;
	M.ReloadDuration = 2.f;
	M.InitFromLoadedClip(5);
	int Budget = 7;
	int Shots = 0;
	for (int i = 0; i < 10; ++i) Shots += M.TryFire(i * 0.1, Budget) ? 1 : 0;
	CHECK(Shots == 5);           // clip exhausted
	CHECK(Budget == 2);
	CHECK(!M.StartReload(1.0, 0));    // no ammo budget -> cannot reload
	CHECK(M.StartReload(1.0, Budget));
	CHECK(!M.TryFire(2.0, Budget));   // still reloading
	CHECK(M.TryFire(3.1, Budget));    // reload done at 3.0
	CHECK(M.TryFire(3.2, Budget));
	CHECK(!M.TryFire(3.3, Budget));   // budget exhausted (2 bullets)
	CHECK(Budget == 0);

	// Client-reported reloads must respect reload duration.
	FMagazineTracker C;
	C.ClipSize = 30; C.ReloadDuration = 2.f;
	C.InitFromLoadedClip(0);
	CHECK(C.ShotsSinceReload == 30);
	CHECK(C.AcceptClientReload(10.0));
	CHECK(C.ShotsSinceReload == 0);
	CHECK(!C.AcceptClientReload(10.5)); // too fast
	CHECK(C.AcceptClientReload(12.0));

	// Loaded clip bigger than clip size is clamped.
	FMagazineTracker D; D.ClipSize = 10; D.InitFromLoadedClip(999);
	CHECK(D.ShotsSinceReload == 0);
}

static void TestDamage()
{
	FDamageTuning T;
	CHECK_NEAR(ComputeDamage(40.f, EHitZone::Body, 0.f, 0.f, T), 40.f, 1e-4f);
	CHECK_NEAR(ComputeDamage(40.f, EHitZone::Head, 0.f, 0.f, T), 80.f, 1e-4f);
	CHECK_NEAR(ComputeDamage(40.f, EHitZone::Head, 0.5f, 0.f, T), 40.f, 1e-4f);
	CHECK_NEAR(ComputeDamage(40.f, EHitZone::Body, 0.f, 0.3f, T), 28.f, 1e-4f);
	CHECK_NEAR(ComputeDamage(40.f, EHitZone::Limb, 0.9f, 0.9f, T), 36.f, 1e-4f); // armor does not cover limbs
	CHECK_NEAR(ComputeDamage(40.f, EHitZone::Body, 0.f, 5.f, T), 8.f, 1e-4f);    // reduction capped at 80%
	CHECK(ComputeDamage(-5.f, EHitZone::Body, 0.f, 0.f, T) == 0.f);

	// capsule centre z=100, half-height 90 => spans 10..190
	CHECK(ZoneFromHeight(180.f, 100.f, 90.f) == EHitZone::Head);
	CHECK(ZoneFromHeight(110.f, 100.f, 90.f) == EHitZone::Body);
	CHECK(ZoneFromHeight(30.f, 100.f, 90.f) == EHitZone::Limb);
	CHECK(ZoneFromHeight(30.f, 100.f, 0.f) == EHitZone::Body);
}

static void TestHitValidation()
{
	FHitCheckTuning T;
	const V3 Shooter{0, 0, 100}, Origin{-250, 0, 160}, Target{2000, 0, 100}, Still{0, 0, 0};
	CHECK(ValidateHitGeometry(Shooter, Origin, V3{1990, 10, 150}, Target, Still, 34.f, 88.f, 0.1f, T) == EHitCheck::Ok);
	// Camera origin far away from the shooter -> rejected
	CHECK(ValidateHitGeometry(Shooter, V3{5000, 0, 0}, V3{1990, 10, 150}, Target, Still, 34.f, 88.f, 0.1f, T) == EHitCheck::OriginTooFar);
	// Reported hit 5 m away from the target -> rejected
	CHECK(ValidateHitGeometry(Shooter, Origin, V3{1500, 0, 100}, Target, Still, 34.f, 88.f, 0.1f, T) == EHitCheck::TargetMismatch);
	// Same 2.5 m offset, accepted only because the target runs fast and latency is high
	const V3 Fast{700, 0, 0};
	CHECK(ValidateHitGeometry(Shooter, Origin, V3{1780, 0, 100}, Target, Fast, 34.f, 88.f, 0.0f, T) == EHitCheck::TargetMismatch);
	CHECK(ValidateHitGeometry(Shooter, Origin, V3{1780, 0, 100}, Target, Fast, 34.f, 88.f, 0.3f, T) == EHitCheck::Ok);
	// Latency compensation is capped
	CHECK(ValidateHitGeometry(Shooter, Origin, V3{1500, 0, 100}, Target, Fast, 34.f, 88.f, 5.0f, T) == EHitCheck::TargetMismatch);
	// Vertical mismatch
	CHECK(ValidateHitGeometry(Shooter, Origin, V3{2000, 0, 600}, Target, Still, 34.f, 88.f, 0.1f, T) == EHitCheck::TargetMismatch);
	// Out of range
	const V3 FarTarget{200000, 0, 100};
	CHECK(ValidateHitGeometry(Shooter, Origin, FarTarget, FarTarget, Still, 34.f, 88.f, 0.1f, T) == EHitCheck::OutOfRange);
}

static void TestSpeed()
{
	FSpeedValidator S;
	bool Flag = false;
	// 600 cm/s for 5 s with 700 allowed -> never flagged
	for (int i = 0; i < 300; ++i) Flag |= S.AddSample(1.f / 60.f, 10.f, 700.f);
	CHECK(!Flag);
	// One fast window (e.g. a legitimate knock-back) is tolerated
	S.Reset(); Flag = false;
	for (int i = 0; i < 60; ++i) Flag |= S.AddSample(1.f / 60.f, 30.f, 700.f);   // 1800 cm/s
	for (int i = 0; i < 60; ++i) Flag |= S.AddSample(1.f / 60.f, 5.f, 700.f);
	CHECK(!Flag);
	// Sustained speed hack is flagged on the 2nd window
	S.Reset(); Flag = false;
	int FlaggedAt = -1;
	for (int i = 0; i < 180 && FlaggedAt < 0; ++i) if (S.AddSample(1.f / 60.f, 30.f, 700.f)) FlaggedAt = i;
	CHECK(FlaggedAt >= 110 && FlaggedAt <= 125);
}

static void TestReconcile()
{
	FReconcileResult R = ReconcileItemCount(0, 1, 1);
	CHECK(R.Claim == 1 && R.Reject == 0 && R.Removed == 0);
	R = ReconcileItemCount(30, 90, 40);   // picked 60 ammo but only 40 lying nearby
	CHECK(R.Claim == 40 && R.Reject == 20);
	R = ReconcileItemCount(3, 1, 10);     // used two bandages
	CHECK(R.Claim == 0 && R.Reject == 0 && R.Removed == 2);
	R = ReconcileItemCount(2, 2, 0);
	CHECK(R.Claim == 0 && R.Reject == 0 && R.Removed == 0);
	R = ReconcileItemCount(0, 5, -3);
	CHECK(R.Claim == 0 && R.Reject == 5);
}

static void TestJoystick()
{
	FStickOutput O = ProcessJoystick(0.f, -100.f, 100.f, 0.1f);   // full up
	CHECK_NEAR(O.Y, 1.f, 1e-4f); CHECK_NEAR(O.X, 0.f, 1e-4f);
	O = ProcessJoystick(5.f, 0.f, 100.f, 0.1f);                     // inside dead zone
	CHECK(O.Magnitude == 0.f);
	O = ProcessJoystick(300.f, 0.f, 100.f, 0.1f);                   // clamped beyond ring
	CHECK_NEAR(O.X, 1.f, 1e-4f);
	O = ProcessJoystick(55.f, 0.f, 100.f, 0.1f);                    // rescaled: (0.55-0.1)/0.9 = 0.5
	CHECK_NEAR(O.X, 0.5f, 1e-4f);
	O = ProcessJoystick(-70.71f, 70.71f, 100.f, 0.f);               // down-left
	CHECK(O.X < 0.f && O.Y < 0.f);
	CHECK(IsSprintGesture(0.f, -150.f, 100.f));
	CHECK(!IsSprintGesture(0.f, -120.f, 100.f));
	CHECK(!IsSprintGesture(150.f, -150.f, 100.f));  // too sideways
	CHECK(!IsSprintGesture(0.f, 150.f, 100.f));     // downward
	CHECK_NEAR(LookScale(1.2f, true, 0.5f), 0.6f, 1e-5f);
}

static void TestDefaultLayout()
{
	// Phone / tablet aspect ratios at a 1080-unit tall safe area.
	const float Widths[] = { 1440.f, 1920.f, 2340.f, 2520.f };
	const float H = 1080.f;
	for (float W : Widths)
	{
		for (int i = 0; i < GTouchDefaultsCount; ++i)
		{
			const FTouchControlDefault& A = GTouchDefaults[i];
			float NX = A.NX, NY = A.NY;
			ClampControlCenter(NX, NY, A.Radius, W, H);
			CHECK_NEAR(NX, A.NX, 1e-6f);   // default positions must already be inside the screen
			CHECK_NEAR(NY, A.NY, 1e-6f);
			for (int j = i + 1; j < GTouchDefaultsCount; ++j)
			{
				const FTouchControlDefault& B = GTouchDefaults[j];
				const bool Overlap = CirclesOverlap(A.NX * W, A.NY * H, A.Radius, B.NX * W, B.NY * H, B.Radius, 8.f);
				if (Overlap) std::printf("  overlap at width %.0f: %s / %s\n", W, A.Id, B.Id);
				CHECK(!Overlap);
			}
			// Right-side action buttons must be outside the joystick spawn zone.
			if (A.Kind != ETouchKind::Joystick && A.NX > 0.5f)
			{
				CHECK(!(A.NX < GJoystickZoneMaxX && A.NY > GJoystickZoneMinY));
			}
		}
	}
	// Ids must be unique
	for (int i = 0; i < GTouchDefaultsCount; ++i)
		for (int j = i + 1; j < GTouchDefaultsCount; ++j)
			CHECK(std::strcmp(GTouchDefaults[i].Id, GTouchDefaults[j].Id) != 0);
	// Clamp keeps a dragged control fully on-screen
	float NX = 0.99f, NY = 0.01f;
	ClampControlCenter(NX, NY, 60.f, 1920.f, 1080.f);
	CHECK_NEAR(NX, 1.f - 60.f / 1920.f, 1e-5f);
	CHECK_NEAR(NY, 60.f / 1080.f, 1e-5f);
}

int main()
{
	TestFireRate();
	TestMagazine();
	TestDamage();
	TestHitValidation();
	TestSpeed();
	TestReconcile();
	TestJoystick();
	TestDefaultLayout();
	std::printf("%d checks, %d failures\n", GChecks, GFailures);
	return GFailures == 0 ? 0 : 1;
}
