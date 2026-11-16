// Default touch-control layout as plain data (no Unreal types) so the exact same
// table is used by the game and by the standalone layout tests.
//
// Coordinates are normalized to the SAFE AREA (0..1). Radii are in Slate units;
// the project DPI curve (DefaultEngine.ini, UIScaleRule=ShortestSide) makes one
// unit equal one pixel of a 1080-pixel-tall screen, so radii are resolution
// independent.

#pragma once

namespace PUBGLogic
{
	enum class ETouchKind : unsigned char
	{
		Joystick,   // movement stick (analog)
		Hold,       // pressed while the finger is down (Fire, ADS, FreeLook)
		Tap,        // short press + release on touch end
		Toggle      // first tap presses, second tap releases (Sprint, Walk)
	};

	struct FTouchControlDefault
	{
		const char* Id;
		const char* Label;
		ETouchKind Kind;
		float NX;
		float NY;
		float Radius;
		bool bVisible;
	};

	// Keep ids stable: they are the keys of the saved custom layout.
	static const FTouchControlDefault GTouchDefaults[] = {
		{ "Move",      "",        ETouchKind::Joystick, 0.15f, 0.70f, 105.f, true  },
		{ "Fire",      "FIRE",    ETouchKind::Hold,     0.86f, 0.62f, 62.f,  true  },
		{ "FireLeft",  "FIRE",    ETouchKind::Hold,     0.10f, 0.36f, 40.f,  true  },
		{ "ADS",       "ADS",     ETouchKind::Hold,     0.94f, 0.42f, 40.f,  true  },
		{ "Scope",     "SCOPE",   ETouchKind::Tap,      0.82f, 0.40f, 34.f,  true  },
		{ "Jump",      "JUMP",    ETouchKind::Tap,      0.94f, 0.80f, 40.f,  true  },
		{ "Crouch",    "CROUCH",  ETouchKind::Tap,      0.84f, 0.90f, 36.f,  true  },
		{ "Prone",     "PRONE",   ETouchKind::Tap,      0.74f, 0.92f, 34.f,  true  },
		{ "Sprint",    "SPRINT",  ETouchKind::Toggle,   0.25f, 0.40f, 32.f,  true  },
		{ "Reload",    "RELOAD",  ETouchKind::Tap,      0.74f, 0.76f, 34.f,  true  },
		{ "Switch",    "SWAP",    ETouchKind::Tap,      0.50f, 0.91f, 36.f,  true  },
		{ "Weapon1",   "1",       ETouchKind::Tap,      0.43f, 0.91f, 30.f,  false },
		{ "Weapon2",   "2",       ETouchKind::Tap,      0.57f, 0.91f, 30.f,  false },
		{ "Inventory", "BAG",     ETouchKind::Tap,      0.32f, 0.91f, 32.f,  true  },
		{ "Pickup",    "PICK UP", ETouchKind::Tap,      0.64f, 0.56f, 40.f,  true  },
		{ "Interact",  "USE",     ETouchKind::Tap,      0.64f, 0.74f, 32.f,  true  },
		{ "FireMode",  "MODE",    ETouchKind::Tap,      0.84f, 0.22f, 28.f,  true  },
		{ "Holster",   "HOLSTER", ETouchKind::Tap,      0.62f, 0.91f, 30.f,  true  },
		{ "FreeLook",  "EYE",     ETouchKind::Hold,     0.74f, 0.22f, 28.f,  true  },
		{ "Drop",      "DROP",    ETouchKind::Tap,      0.38f, 0.80f, 28.f,  false },
		{ "Walk",      "WALK",    ETouchKind::Toggle,   0.25f, 0.55f, 28.f,  false },
		{ "Menu",      "MENU",    ETouchKind::Tap,      0.04f, 0.07f, 26.f,  true  },
	};

	static const int GTouchDefaultsCount = (int)(sizeof(GTouchDefaults) / sizeof(GTouchDefaults[0]));

	// Region (normalized, safe area) where a touch that misses every button
	// spawns/moves the movement stick. Everything else that misses a button is
	// a camera-look drag.
	static const float GJoystickZoneMaxX = 0.45f;
	static const float GJoystickZoneMinY = 0.30f;
}
