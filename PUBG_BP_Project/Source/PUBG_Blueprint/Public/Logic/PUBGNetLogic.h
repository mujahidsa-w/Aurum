// Pure gameplay / validation logic with NO Unreal Engine dependencies.
//
// Everything here is deterministic math used by the server-side anti-cheat
// checks and by the touch controls. Keeping it engine-free lets it be unit
// tested with a plain C++ compiler (see Tests/LogicTests), which is the only
// kind of execution test possible without an Unreal Engine installation.
//
// Vector helpers are templates that only require public X/Y/Z members, so they
// work with FVector inside UE and with a tiny struct in the standalone tests.

#pragma once

#include <cmath>

namespace PUBGLogic
{
	inline float ClampF(float V, float Lo, float Hi) { return V < Lo ? Lo : (V > Hi ? Hi : V); }
	inline float MinF(float A, float B) { return A < B ? A : B; }
	inline float MaxF(float A, float B) { return A > B ? A : B; }
	inline int MinI(int A, int B) { return A < B ? A : B; }
	inline int MaxI(int A, int B) { return A > B ? A : B; }

	template <typename V> inline float DistSq(const V& A, const V& B)
	{
		const float DX = A.X - B.X, DY = A.Y - B.Y, DZ = A.Z - B.Z;
		return DX * DX + DY * DY + DZ * DZ;
	}
	template <typename V> inline float Dist(const V& A, const V& B) { return std::sqrt(DistSq(A, B)); }
	template <typename V> inline float Dist2D(const V& A, const V& B)
	{
		const float DX = A.X - B.X, DY = A.Y - B.Y;
		return std::sqrt(DX * DX + DY * DY);
	}
	template <typename V> inline float Length(const V& A) { return std::sqrt(A.X * A.X + A.Y * A.Y + A.Z * A.Z); }

	// ------------------------------------------------------------------------
	// Fire-rate limiting (server). Token bucket: average rate is bounded by the
	// weapon's firing interval, while a small burst allowance absorbs network
	// jitter (several RPCs arriving in the same server frame).
	// ------------------------------------------------------------------------
	struct FFireRateLimiter
	{
		float Credits = 1.f;
		double LastTime = -1.0;

		// Tolerance < 1 accepts slightly faster arrival than the nominal interval.
		bool TryConsume(double Now, float FiringInterval, float Tolerance = 0.8f, float MaxBurst = 2.f)
		{
			const float Interval = MaxF(FiringInterval * Tolerance, 0.01f);
			if (LastTime >= 0.0)
			{
				const float Elapsed = (float)MaxF((float)(Now - LastTime), 0.f);
				Credits = MinF(MaxBurst, Credits + Elapsed / Interval);
			}
			LastTime = Now;
			if (Credits >= 1.f)
			{
				Credits -= 1.f;
				return true;
			}
			return false;
		}

		void Reset() { Credits = 1.f; LastTime = -1.0; }
	};

	// ------------------------------------------------------------------------
	// Magazine / reload tracking for one weapon slot (server).
	// The ammo budget (bullets the player legitimately picked up) is owned by the
	// caller; this tracks shots between reloads and reload timing.
	// ------------------------------------------------------------------------
	struct FMagazineTracker
	{
		int ClipSize = 30;
		float ReloadDuration = 2.f;
		int ShotsSinceReload = 0;
		bool bReloading = false;
		double ReloadEndsAt = 0.0;
		double LastReloadCompletedAt = -1000.0;

		// Called when a freshly verified weapon arrives with ClipAmmo bullets already loaded.
		void InitFromLoadedClip(int ClipAmmo)
		{
			const int Loaded = ClipSize > 0 ? MinI(MaxI(ClipAmmo, 0), ClipSize) : MaxI(ClipAmmo, 0);
			ShotsSinceReload = ClipSize > 0 ? ClipSize - Loaded : 0;
			bReloading = false;
		}

		void Update(double Now)
		{
			if (bReloading && Now >= ReloadEndsAt)
			{
				bReloading = false;
				ShotsSinceReload = 0;
				LastReloadCompletedAt = Now;
			}
		}

		bool CanFire(double Now, int AmmoBudget)
		{
			Update(Now);
			if (bReloading || AmmoBudget <= 0)
			{
				return false;
			}
			return ClipSize <= 0 || ShotsSinceReload < ClipSize;
		}

		bool TryFire(double Now, int& InOutAmmoBudget)
		{
			if (!CanFire(Now, InOutAmmoBudget))
			{
				return false;
			}
			++ShotsSinceReload;
			--InOutAmmoBudget;
			return true;
		}

		bool StartReload(double Now, int AmmoBudget)
		{
			Update(Now);
			if (bReloading || AmmoBudget <= 0 || ShotsSinceReload == 0)
			{
				return false;
			}
			bReloading = true;
			ReloadEndsAt = Now + ReloadDuration;
			return true;
		}

		// The owning client reported (via inventory snapshot) that its clip was refilled
		// by a Blueprint reload path the server did not see start. Accept it only if
		// enough time has passed since the previous completed reload.
		bool AcceptClientReload(double Now)
		{
			Update(Now);
			if (bReloading)
			{
				return false;
			}
			if (Now - LastReloadCompletedAt < ReloadDuration * 0.75)
			{
				return false;
			}
			ShotsSinceReload = 0;
			LastReloadCompletedAt = Now;
			return true;
		}
	};

	// ------------------------------------------------------------------------
	// Damage
	// ------------------------------------------------------------------------
	enum class EHitZone : unsigned char
	{
		Body,
		Head,
		Limb
	};

	// Fallback hit-zone from hit height when no bone name is available (e.g. a
	// dedicated server that does not refresh bone transforms).
	inline EHitZone ZoneFromHeight(float HitZ, float CapsuleCenterZ, float CapsuleHalfHeight)
	{
		if (CapsuleHalfHeight <= 0.f)
		{
			return EHitZone::Body;
		}
		const float Bottom = CapsuleCenterZ - CapsuleHalfHeight;
		const float Rel = (HitZ - Bottom) / (2.f * CapsuleHalfHeight);
		if (Rel >= 0.86f)
		{
			return EHitZone::Head;
		}
		if (Rel <= 0.42f)
		{
			return EHitZone::Limb;
		}
		return EHitZone::Body;
	}

	struct FDamageTuning
	{
		float HeadMultiplier = 2.0f;
		float LimbMultiplier = 0.9f;
		float MaxArmorReduction = 0.8f;
	};

	inline float ComputeDamage(float BaseDamage, EHitZone Zone, float HelmetReduction, float VestReduction, const FDamageTuning& Tuning)
	{
		float Multiplier = 1.f;
		float Reduction = 0.f;
		switch (Zone)
		{
		case EHitZone::Head:
			Multiplier = Tuning.HeadMultiplier;
			Reduction = HelmetReduction;
			break;
		case EHitZone::Limb:
			Multiplier = Tuning.LimbMultiplier;
			break;
		default:
			Reduction = VestReduction;
			break;
		}
		Reduction = ClampF(Reduction, 0.f, Tuning.MaxArmorReduction);
		return MaxF(0.f, BaseDamage * Multiplier * (1.f - Reduction));
	}

	// ------------------------------------------------------------------------
	// Server-side validation of a client-reported hit ("favor the shooter" with
	// plausibility checks, like Epic's ShooterGame sample).
	// ------------------------------------------------------------------------
	enum class EHitCheck : unsigned char
	{
		Ok,
		OriginTooFar,
		OutOfRange,
		TargetMismatch
	};

	struct FHitCheckTuning
	{
		float MaxOriginOffset = 650.f;   // camera boom + margin (cm)
		float MaxRange = 100000.f;       // 1 km
		float TargetTolerance = 120.f;   // cm on top of capsule size
		float MaxLatencyCompensation = 0.4f; // seconds of target movement accepted
	};

	template <typename V>
	inline EHitCheck ValidateHitGeometry(const V& ShooterLocation, const V& ReportedOrigin, const V& HitLocation,
		const V& TargetLocation, const V& TargetVelocity, float TargetRadius, float TargetHalfHeight,
		float LatencySeconds, const FHitCheckTuning& Tuning)
	{
		if (Dist(ReportedOrigin, ShooterLocation) > Tuning.MaxOriginOffset)
		{
			return EHitCheck::OriginTooFar;
		}
		if (Dist(ShooterLocation, HitLocation) > Tuning.MaxRange)
		{
			return EHitCheck::OutOfRange;
		}
		const float Lag = ClampF(LatencySeconds, 0.f, Tuning.MaxLatencyCompensation);
		const float Allowed = Tuning.TargetTolerance + Length(TargetVelocity) * Lag;
		if (Dist2D(HitLocation, TargetLocation) > TargetRadius + Allowed)
		{
			return EHitCheck::TargetMismatch;
		}
		const float DZ = HitLocation.Z - TargetLocation.Z;
		if ((DZ < 0.f ? -DZ : DZ) > TargetHalfHeight + Allowed)
		{
			return EHitCheck::TargetMismatch;
		}
		return EHitCheck::Ok;
	}

	// ------------------------------------------------------------------------
	// Movement plausibility (server). The original Blueprint moves the pawn with
	// SetActorLocation, so movement is client-authoritative; the server bounds it.
	// Two consecutive over-speed windows are required to avoid false positives.
	// ------------------------------------------------------------------------
	struct FSpeedValidator
	{
		float WindowTime = 0.f;
		float WindowDistance = 0.f;
		int ConsecutiveViolations = 0;

		// Returns true when the pawn should be corrected.
		bool AddSample(float DeltaSeconds, float HorizontalDistance, float AllowedSpeed, float WindowLength = 1.f)
		{
			WindowTime += MaxF(DeltaSeconds, 0.f);
			WindowDistance += MaxF(HorizontalDistance, 0.f);
			if (WindowTime < WindowLength)
			{
				return false;
			}
			const float Speed = WindowDistance / WindowTime;
			WindowTime = 0.f;
			WindowDistance = 0.f;
			if (Speed > AllowedSpeed)
			{
				++ConsecutiveViolations;
			}
			else
			{
				ConsecutiveViolations = 0;
			}
			if (ConsecutiveViolations >= 2)
			{
				ConsecutiveViolations = 0;
				return true;
			}
			return false;
		}

		void Reset()
		{
			WindowTime = 0.f;
			WindowDistance = 0.f;
			ConsecutiveViolations = 0;
		}
	};

	// ------------------------------------------------------------------------
	// Inventory reconciliation for one item key (server ledger vs. client report).
	// ------------------------------------------------------------------------
	struct FReconcileResult
	{
		int Claim = 0;     // amount to take from nearby world pickups
		int Reject = 0;    // reported amount that could not be justified
		int Removed = 0;   // amount that left the inventory (used / moved / dropped)
	};

	inline FReconcileResult ReconcileItemCount(int Verified, int Reported, int ClaimableNearby)
	{
		FReconcileResult R;
		if (Reported > Verified)
		{
			const int Need = Reported - Verified;
			R.Claim = MinI(Need, MaxI(ClaimableNearby, 0));
			R.Reject = Need - R.Claim;
		}
		else
		{
			R.Removed = Verified - Reported;
		}
		return R;
	}

	// ------------------------------------------------------------------------
	// Touch controls
	// ------------------------------------------------------------------------
	struct FStickOutput
	{
		float X = 0.f;   // right
		float Y = 0.f;   // forward
		float Magnitude = 0.f;
	};

	// DX/DY: finger offset from the stick centre in screen space (Y grows downward).
	inline FStickOutput ProcessJoystick(float DX, float DY, float Radius, float DeadZone)
	{
		FStickOutput Out;
		const float Len = std::sqrt(DX * DX + DY * DY);
		if (Radius <= 0.f || Len <= 0.f)
		{
			return Out;
		}
		const float M = MinF(Len / Radius, 1.f);
		const float DZ = ClampF(DeadZone, 0.f, 0.95f);
		if (M <= DZ)
		{
			return Out;
		}
		const float Scaled = (M - DZ) / (1.f - DZ);
		Out.X = (DX / Len) * Scaled;
		Out.Y = (-DY / Len) * Scaled;
		Out.Magnitude = Scaled;
		return Out;
	}

	// Pushing the stick well beyond its ring, mostly upward, locks sprint
	// (common mobile-shooter gesture).
	inline bool IsSprintGesture(float DX, float DY, float Radius, float Threshold = 1.35f)
	{
		if (Radius <= 0.f || DY >= 0.f)
		{
			return false;
		}
		const float Up = -DY;
		const float Side = DX < 0.f ? -DX : DX;
		return Up > Radius * Threshold && Side < Up * 0.6f;
	}

	inline float LookScale(float BaseSensitivity, bool bAiming, float AimMultiplier)
	{
		return BaseSensitivity * (bAiming ? AimMultiplier : 1.f);
	}

	// Keeps a circular control fully inside a W x H area. Returns the corrected
	// normalized centre (0..1).
	inline void ClampControlCenter(float& InOutNX, float& InOutNY, float RadiusPx, float W, float H)
	{
		if (W <= 0.f || H <= 0.f)
		{
			return;
		}
		const float MinX = MinF(RadiusPx / W, 0.5f), MinY = MinF(RadiusPx / H, 0.5f);
		InOutNX = ClampF(InOutNX, MinX, 1.f - MinX);
		InOutNY = ClampF(InOutNY, MinY, 1.f - MinY);
	}

	inline bool CirclesOverlap(float AX, float AY, float AR, float BX, float BY, float BR, float Padding = 0.f)
	{
		const float DX = AX - BX, DY = AY - BY;
		const float R = AR + BR + Padding;
		return DX * DX + DY * DY < R * R;
	}
}
