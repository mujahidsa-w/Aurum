extends RefCounted
## Bakes the stylised soldier (CharacterModel) into ONE ArrayMesh with one surface per
## material, so dozens of soldiers cost dozens of draw calls instead of thousands.

const CharacterModel := preload("res://scripts/character_model.gd")

static var _mesh: ArrayMesh
static var _accent_surface := -1
static var _weapon_xform := Transform3D.IDENTITY


## Builds the shared mesh once. `host` must be inside the scene tree.
static func ensure_built(host: Node) -> void:
	if _mesh:
		return
	var model := CharacterModel.new()
	model.show_rifle = false
	host.add_child(model)
	var tools := {}
	var order: Array = []
	var root_inv := model.global_transform.affine_inverse()
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var mat: Material = mi.material_override
		if not tools.has(mat):
			var st_new := SurfaceTool.new()
			st_new.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[mat] = st_new
			order.append(mat)
		var st: SurfaceTool = tools[mat]
		st.append_from(mi.mesh, 0, root_inv * mi.global_transform)
	_mesh = ArrayMesh.new()
	for mat in order:
		var st: SurfaceTool = tools[mat]
		st.commit(_mesh)
		var idx := _mesh.get_surface_count() - 1
		_mesh.surface_set_material(idx, mat)
		if mat == model.accent_mat:
			_accent_surface = idx
	_weapon_xform = model.weapon_transform
	host.remove_child(model)
	model.queue_free()


## A MeshInstance3D of the soldier with its own accent colour.
static func create(accent: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	if _accent_surface >= 0:
		var m := StandardMaterial3D.new()
		m.albedo_color = accent
		m.roughness = 0.45
		mi.set_surface_override_material(_accent_surface, m)
	return mi


## Where a two-handed weapon sits, in soldier space (+X = muzzle direction).
static func weapon_transform() -> Transform3D:
	return _weapon_xform
