extends RefCounted
## Realistic playable characters (scanned humans + a soldier), all CC-BY - see CREDITS.md.
## Every model carries the same animation set (retargeted offline from the soldier rig):
## idle, walk, run, rifle_idle, rifle_walk, rifle_run, rifle_aim, pistol_idle, jump.

const CHARACTERS := [
	{"id": "nathan", "name": "Nathan", "gender": "male", "head": 1.63},
	{"id": "eric", "name": "Eric", "gender": "male", "head": 1.60},
	{"id": "soldier", "name": "Ranger", "gender": "male", "head": 1.55},
	{"id": "sophia", "name": "Sophia", "gender": "female", "head": 1.48},
	{"id": "carla", "name": "Carla", "gender": "female", "head": 1.49},
	{"id": "claudia", "name": "Claudia", "gender": "female", "head": 1.50},
]

const OUTFITS := [
	{"id": "original", "name": "Original"},
	{"id": "black", "name": "Night Ops"},
	{"id": "olive", "name": "Woodland"},
	{"id": "desert", "name": "Desert"},
	{"id": "navy", "name": "Navy"},
]

## The soldier has separate clothing materials, tinted instead of re-textured.
const SOLDIER_TINT := {
	"black": Color(0.17, 0.17, 0.19),
	"olive": Color(0.45, 0.52, 0.3),
	"desert": Color(0.8, 0.68, 0.5),
	"navy": Color(0.25, 0.32, 0.48),
}


static func get_character(id: String) -> Dictionary:
	for c in CHARACTERS:
		if str(c["id"]) == id:
			return c
	return CHARACTERS[0]


static func by_gender(gender: String) -> Array:
	var out: Array = []
	for c in CHARACTERS:
		if str(c["gender"]) == gender:
			out.append(c)
	return out


static func model_path(id: String) -> String:
	return "res://assets/characters/%s.glb" % id


static func outfit_texture(id: String, outfit: String) -> String:
	return "res://assets/characters/outfits/%s_%s.jpg" % [id, outfit]


static func thumb(id: String, outfit: String) -> String:
	return "res://assets/ui/thumbs/%s_%s.png" % [id, outfit]


static func weapon_thumb(id: String) -> String:
	return "res://assets/ui/thumbs/w_%s.png" % id


static func outfit_name(id: String) -> String:
	for o in OUTFITS:
		if str(o["id"]) == id:
			return str(o["name"])
	return id


static func exists(id: String) -> bool:
	return ResourceLoader.exists(model_path(id))
