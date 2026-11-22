extends RefCounted
## Weapon catalogue with real-world specifications (calibre, muzzle velocity, cyclic rate,
## magazine capacity, overall length). Gameplay values (damage, recoil, spread) are tuned
## per calibre so heavier rounds hit harder and kick more.
##
## Models live in res://assets/weapons/<id>.glb. They were prepared so that the muzzle points
## to -Z, the model is centred on its bounding box and scaled to the real overall length.
## Adding a weapon = add its .glb and one entry below.

const AMMO := {
	"9x19": {"name": "9mm", "stack": 60},
	".45ACP": {"name": ".45 ACP", "stack": 42},
	"5.56x45": {"name": "5.56mm", "stack": 90},
	"5.45x39": {"name": "5.45mm", "stack": 90},
	"7.62x39": {"name": "7.62x39", "stack": 60},
	"7.62x51": {"name": "7.62x51", "stack": 40},
	"7.62x54R": {"name": "7.62x54R", "stack": 40},
	"9x39": {"name": "9x39", "stack": 60},
	".338LM": {"name": ".338 LM", "stack": 20},
	"12ga": {"name": "12 Gauge", "stack": 30},
}

## class: pistol / smg / ar / dmr / sniper / shotgun / lmg
## velocity m/s, rpm rounds per minute, damage per hit (per pellet for shotguns),
## recoil = vertical kick in degrees, spread = hip-fire cone in degrees, zoom = ADS magnification.
const WEAPONS := {
	"m1911": {"name": "M1911", "class": "pistol", "ammo": ".45ACP", "velocity": 253.0, "rpm": 400.0, "mag": 7, "reload": 1.9, "damage": 36.0, "modes": ["semi"], "recoil": 2.6, "spread": 2.2, "zoom": 1.25, "length": 0.216, "weight": 6},
	"usp": {"name": "USP", "class": "pistol", "ammo": "9x19", "velocity": 350.0, "rpm": 450.0, "mag": 15, "reload": 1.8, "damage": 27.0, "modes": ["semi"], "recoil": 1.8, "spread": 2.0, "zoom": 1.25, "length": 0.194, "weight": 8},
	"mp5": {"name": "MP5", "class": "smg", "ammo": "9x19", "velocity": 400.0, "rpm": 800.0, "mag": 30, "reload": 2.3, "damage": 24.0, "modes": ["auto", "semi"], "recoil": 0.9, "spread": 2.6, "zoom": 1.4, "length": 0.70, "weight": 9},
	"akm": {"name": "AKM", "class": "ar", "ammo": "7.62x39", "velocity": 715.0, "rpm": 600.0, "mag": 30, "reload": 2.6, "damage": 40.0, "modes": ["auto", "semi"], "recoil": 1.9, "spread": 3.0, "zoom": 1.6, "length": 0.88, "weight": 9},
	"ak74m": {"name": "AK-74M", "class": "ar", "ammo": "5.45x39", "velocity": 900.0, "rpm": 650.0, "mag": 30, "reload": 2.5, "damage": 34.0, "modes": ["auto", "semi"], "recoil": 1.3, "spread": 2.7, "zoom": 1.6, "length": 0.943, "weight": 8},
	"m4a1": {"name": "M4A1", "class": "ar", "ammo": "5.56x45", "velocity": 880.0, "rpm": 800.0, "mag": 30, "reload": 2.4, "damage": 33.0, "modes": ["auto", "semi"], "recoil": 1.15, "spread": 2.5, "zoom": 1.8, "length": 0.84, "weight": 8},
	"sks": {"name": "SKS", "class": "dmr", "ammo": "7.62x39", "velocity": 735.0, "rpm": 300.0, "mag": 10, "reload": 3.0, "damage": 52.0, "modes": ["semi"], "recoil": 2.4, "spread": 3.2, "zoom": 3.0, "length": 1.02, "weight": 6},
	"svd": {"name": "SVD", "class": "dmr", "ammo": "7.62x54R", "velocity": 830.0, "rpm": 240.0, "mag": 10, "reload": 3.2, "damage": 62.0, "modes": ["semi"], "recoil": 3.0, "spread": 3.6, "zoom": 4.0, "length": 1.225, "weight": 4},
	"g28": {"name": "G28", "class": "dmr", "ammo": "7.62x51", "velocity": 790.0, "rpm": 260.0, "mag": 20, "reload": 3.0, "damage": 58.0, "modes": ["semi"], "recoil": 2.6, "spread": 3.4, "zoom": 4.0, "length": 1.08, "weight": 4},
	"bolt_sniper": {"name": "Bolt-Action .338", "class": "sniper", "ammo": ".338LM", "velocity": 900.0, "rpm": 40.0, "mag": 5, "reload": 3.8, "damage": 115.0, "modes": ["bolt"], "recoil": 5.5, "spread": 5.0, "zoom": 8.0, "length": 1.2, "weight": 2},
	"vss": {"name": "VSS", "class": "dmr", "ammo": "9x39", "velocity": 290.0, "rpm": 800.0, "mag": 20, "reload": 2.8, "damage": 40.0, "modes": ["auto", "semi"], "recoil": 1.1, "spread": 2.8, "zoom": 4.0, "length": 0.894, "weight": 4, "suppressed": true},
	"r870": {"name": "870 Pump", "class": "shotgun", "ammo": "12ga", "velocity": 400.0, "rpm": 65.0, "mag": 5, "reload": 4.0, "damage": 21.0, "pellets": 9, "modes": ["pump"], "recoil": 4.5, "spread": 4.5, "zoom": 1.2, "length": 1.0, "weight": 6},
	"m4super90": {"name": "M4 Super 90", "class": "shotgun", "ammo": "12ga", "velocity": 400.0, "rpm": 240.0, "mag": 7, "reload": 4.4, "damage": 19.0, "pellets": 8, "modes": ["semi"], "recoil": 4.0, "spread": 4.8, "zoom": 1.2, "length": 1.01, "weight": 5},
	"m249": {"name": "M249", "class": "lmg", "ammo": "5.56x45", "velocity": 915.0, "rpm": 800.0, "mag": 100, "reload": 6.5, "damage": 33.0, "modes": ["auto"], "recoil": 1.5, "spread": 3.4, "zoom": 1.6, "length": 1.04, "weight": 2},
}

## Damage multiplier by hit zone.
const HEADSHOT := 2.3
const LIMB := 0.8


static func get_weapon(id: String) -> Dictionary:
	return WEAPONS.get(id, WEAPONS["m1911"])


static func model_path(id: String) -> String:
	return "res://assets/weapons/%s.glb" % id


static func ids() -> Array:
	return WEAPONS.keys()


## Picks a random weapon id, weighted so rare weapons (snipers, LMG) appear less often.
static func random_id(rng: RandomNumberGenerator) -> String:
	var total := 0
	for id in WEAPONS:
		total += int(WEAPONS[id]["weight"])
	var roll := rng.randi_range(1, total)
	for id in WEAPONS:
		roll -= int(WEAPONS[id]["weight"])
		if roll <= 0:
			return str(id)
	return "m1911"


## Seconds between shots.
static func fire_interval(w: Dictionary) -> float:
	return 60.0 / maxf(float(w["rpm"]), 1.0)
