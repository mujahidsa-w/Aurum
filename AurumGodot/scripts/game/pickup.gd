extends Area3D
## Loot lying on the ground: a weapon (real model), an ammo box or a medkit.

const WeaponDB := preload("res://scripts/game/weapon_db.gd")

var kind := "weapon"
var weapon_id := ""
var loaded := -1
var ammo_type := ""
var amount := 0


func setup_weapon(id: String, rounds: int = -1) -> void:
	kind = "weapon"
	weapon_id = id
	loaded = rounds
	_build()


func setup_ammo(ammo: String, count: int) -> void:
	kind = "ammo"
	ammo_type = ammo
	amount = count
	_build()


func setup_medkit() -> void:
	kind = "medkit"
	amount = 1
	_build()


func describe() -> String:
	match kind:
		"weapon":
			return str(WeaponDB.get_weapon(weapon_id)["name"])
		"ammo":
			return "%s x%d" % [str(WeaponDB.AMMO.get(ammo_type, {"name": ammo_type})["name"]), amount]
	return "First Aid Kit"


func _build() -> void:
	collision_layer = 8
	collision_mask = 2
	monitorable = true
	monitoring = true
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.3
	cs.shape = sphere
	cs.position = Vector3(0, 0.4, 0)
	add_child(cs)
	match kind:
		"weapon":
			var path := WeaponDB.model_path(weapon_id)
			if ResourceLoader.exists(path):
				var scene := load(path) as PackedScene
				if scene:
					var model := scene.instantiate() as Node3D
					if model:
						# Lie on its side on the ground.
						model.transform = Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0, 0.06, 0))
						add_child(model)
		"ammo":
			_box(Vector3(0.32, 0.18, 0.2), Color(0.28, 0.32, 0.18))
			_box(Vector3(0.33, 0.03, 0.21), Color(0.9, 0.72, 0.15), 0.06)
		"medkit":
			_box(Vector3(0.34, 0.14, 0.24), Color(0.92, 0.92, 0.9))
			_box(Vector3(0.2, 0.01, 0.05), Color(0.85, 0.1, 0.1), 0.075)
			_box(Vector3(0.05, 0.01, 0.16), Color(0.85, 0.1, 0.1), 0.075)
	var label := Label3D.new()
	label.text = describe()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.pixel_size = 0.004
	label.outline_size = 8
	label.position = Vector3(0, 0.55, 0)
	label.visibility_range_end = 14.0
	label.no_depth_test = false
	add_child(label)


func _box(size: Vector3, color: Color, y: float = 0.0) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.7
	mi.material_override = m
	mi.position = Vector3(0, size.y * 0.5 + y, 0)
	add_child(mi)
