extends RefCounted
## Builds the REAL buildings and roads of Vis Island from OpenStreetMap data
## (© OpenStreetMap contributors, ODbL). Footprints are extruded to their real floor count
## (or an estimate), rectangular houses get terracotta gable roofs, others flat roofs.
## Geometry is merged per 400 m cell to keep draw calls low; buildings get trimesh collision.

const OSM_PATH := "res://maps/vis/osm.tres"
const CELL := 400.0
const FLOOR_H := 3.0


static func available() -> bool:
	return ResourceLoader.exists(OSM_PATH)


## Collects triangles per material and commits them as one ArrayMesh.
class Batch:
	var tools := {}
	var order: Array = []

	func _st(mat: Material) -> SurfaceTool:
		if not tools.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[mat] = st
			order.append(mat)
		return tools[mat]

	## Adds a triangle whose front face points along `n` (Godot: clockwise = front).
	func tri(mat: Material, a: Vector3, b: Vector3, c: Vector3, n: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
		if (b - a).cross(c - a).dot(n) > 0.0:
			var tv := b
			b = c
			c = tv
			var tu := ub
			ub = uc
			uc = tu
		var st := _st(mat)
		st.set_normal(n)
		st.set_uv(ua)
		st.add_vertex(a)
		st.set_normal(n)
		st.set_uv(ub)
		st.add_vertex(b)
		st.set_normal(n)
		st.set_uv(uc)
		st.add_vertex(c)

	func quad(mat: Material, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
		tri(mat, a, b, c, n, ua, ub, uc)
		tri(mat, a, c, d, n, ua, uc, ud)

	func is_empty() -> bool:
		return order.is_empty()

	func commit() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for mat in order:
			var st: SurfaceTool = tools[mat]
			st.generate_tangents()
			st.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
		return mesh


static func build(world: Node3D) -> int:
	var res: Resource = load(OSM_PATH)
	if res == null:
		return 0
	var mats: Dictionary = world.call("osm_materials")
	var building_cells := {}
	var road_cells := {}
	var count := _buildings(world, res, mats, building_cells)
	_roads(world, res, mats, road_cells)
	for key in building_cells:
		var batch: Batch = building_cells[key]
		if batch.is_empty():
			continue
		var mesh := batch.commit()
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.visibility_range_end = 1800.0
		world.add_child(mi)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.shape = mesh.create_trimesh_shape()
		body.add_child(cs)
		world.add_child(body)
	for key in road_cells:
		var rb: Batch = road_cells[key]
		if rb.is_empty():
			continue
		var rm := MeshInstance3D.new()
		rm.mesh = rb.commit()
		rm.visibility_range_end = 1600.0
		rm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(rm)
	return count


static func _cell(cells: Dictionary, p: Vector2) -> Batch:
	var key := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
	if not cells.has(key):
		cells[key] = Batch.new()
	return cells[key]


static func _h(world: Node3D, x: float, z: float) -> float:
	return float(world.call("height_at", x, z))


# --- Buildings ------------------------------------------------------------------------------

static func _buildings(world: Node3D, res: Resource, mats: Dictionary, cells: Dictionary) -> int:
	var pts: PackedVector2Array = res.get_meta("b_points")
	var offs: PackedInt32Array = res.get_meta("b_offsets")
	var levels: PackedInt32Array = res.get_meta("b_levels")
	var kinds: PackedInt32Array = res.get_meta("b_kind")
	var plasters: Array = mats["plaster"]
	var shutters: Array = mats["shutters"]
	var loot: Array = world.get("loot_points")
	var built := 0
	for i in levels.size():
		var poly := pts.slice(offs[i], offs[i + 1])
		var n := poly.size()
		if n < 3:
			continue
		var base := INF
		var centre := Vector2.ZERO
		for p in poly:
			base = minf(base, _h(world, p.x, p.y))
			centre += p
		centre /= float(n)
		if base < 0.8:
			# Waterfront: the 32 m elevation grid smooths the shoreline, so put the house on the quay.
			if _h(world, centre.x, centre.y) < -8.0:
				continue
			base = 0.8
		var kind := kinds[i]
		var floors := maxi(levels[i], 1)
		var height := floors * FLOOR_H + 0.4
		if kind == 1:
			height = maxf(height, 10.0)
		var top := base + height
		var batch := _cell(cells, centre)
		var wall: Material = plasters[i % plasters.size()]
		if kind == 3 or kind == 4:
			wall = mats["concrete"]
		var shutter: Material = shutters[i % shutters.size()]
		var longest := 0
		var longest_len := 0.0
		for e in n:
			var p0 := poly[e]
			var p1 := poly[(e + 1) % n]
			var d := p1 - p0
			var length := d.length()
			if length < 0.05:
				continue
			if length > longest_len:
				longest_len = length
				longest = e
			var nrm := Vector3(d.y, 0.0, -d.x) / length
			batch.quad(wall,
				Vector3(p0.x, base - 1.5, p0.y), Vector3(p1.x, base - 1.5, p1.y),
				Vector3(p1.x, top, p1.y), Vector3(p0.x, top, p0.y), nrm,
				Vector2(0, -1.5), Vector2(length, -1.5), Vector2(length, height), Vector2(0, height))
			if kind != 4 and length >= 2.6:
				var per := int(length / 3.2)
				var tangent := Vector3(d.x, 0.0, d.y) / length
				for f in floors:
					for k in per:
						var mid := p0.lerp(p1, (float(k) + 0.5) / per)
						var centre3 := Vector3(mid.x, base + f * FLOOR_H + 1.45, mid.y)
						_window(batch, mats["window"], shutter, centre3, tangent, nrm)
		# Front door on the longest wall.
		var dp0 := poly[longest]
		var dp1 := poly[(longest + 1) % n]
		var dd := dp1 - dp0
		if dd.length() > 1.5:
			var dn := Vector3(dd.y, 0.0, -dd.x) / dd.length()
			var dt := Vector3(dd.x, 0.0, dd.y) / dd.length()
			var mid2 := dp0.lerp(dp1, 0.5)
			var c3 := Vector3(mid2.x, base + 1.05, mid2.y) + dn * 0.05
			batch.quad(shutter, c3 - dt * 0.55 - Vector3(0, 1.05, 0), c3 + dt * 0.55 - Vector3(0, 1.05, 0),
				c3 + dt * 0.55 + Vector3(0, 1.05, 0), c3 - dt * 0.55 + Vector3(0, 1.05, 0), dn,
				Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
			if absf(_polygon_area(poly)) > 35.0:
				var door := mid2 + Vector2(dn.x, dn.z) * 1.4
				loot.append(Vector3(door.x, _h(world, door.x, door.y) + 0.05, door.y))
		# Roof.
		if n == 4 and kind != 3:
			_gable_roof(batch, mats["roof"], wall, poly, top)
		else:
			_flat_roof(batch, mats["concrete"], poly, top)
		built += 1
	return built


static func _window(batch: Batch, glass: Material, shutter: Material, c: Vector3, t: Vector3, n: Vector3) -> void:
	var up := Vector3.UP
	var o := c + n * 0.04
	batch.quad(glass, o - t * 0.45 - up * 0.62, o + t * 0.45 - up * 0.62, o + t * 0.45 + up * 0.62, o - t * 0.45 + up * 0.62, n,
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	for side: float in [-1.0, 1.0]:
		var s := c + n * 0.07 + t * side * 0.68
		batch.quad(shutter, s - t * 0.21 - up * 0.64, s + t * 0.21 - up * 0.64, s + t * 0.21 + up * 0.64, s - t * 0.21 + up * 0.64, n,
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))


static func _polygon_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


static func _flat_roof(batch: Batch, mat: Material, poly: PackedVector2Array, top: float) -> void:
	var idx := Geometry2D.triangulate_polygon(poly)
	for k in range(0, idx.size(), 3):
		var a := poly[idx[k]]
		var b := poly[idx[k + 1]]
		var c := poly[idx[k + 2]]
		batch.tri(mat, Vector3(a.x, top, a.y), Vector3(b.x, top, b.y), Vector3(c.x, top, c.y), Vector3.UP, a * 0.25, b * 0.25, c * 0.25)


static func _gable_roof(batch: Batch, roof: Material, wall: Material, poly: PackedVector2Array, top: float) -> void:
	var p := poly
	# Make p0->p1 the long side so the ridge runs along the length of the house.
	if p[0].distance_to(p[1]) < p[1].distance_to(p[2]):
		p = PackedVector2Array([poly[1], poly[2], poly[3], poly[0]])
	var short_len := p[1].distance_to(p[2])
	var ridge_h := clampf(short_len * 0.32, 1.0, 3.2)
	var r0v := (p[3] + p[0]) * 0.5
	var r1v := (p[1] + p[2]) * 0.5
	var a := Vector3(p[0].x, top, p[0].y)
	var b := Vector3(p[1].x, top, p[1].y)
	var c := Vector3(p[2].x, top, p[2].y)
	var d := Vector3(p[3].x, top, p[3].y)
	var r0 := Vector3(r0v.x, top + ridge_h, r0v.y)
	var r1 := Vector3(r1v.x, top + ridge_h, r1v.y)
	var n1 := (b - a).cross(r0 - a).normalized()
	if n1.y < 0.0:
		n1 = -n1
	var n2 := (d - c).cross(r1 - c).normalized()
	if n2.y < 0.0:
		n2 = -n2
	var len_ab := a.distance_to(b)
	batch.quad(roof, a, b, r1, r0, n1, Vector2(0, 0), Vector2(len_ab, 0), Vector2(len_ab, 2.5), Vector2(0, 2.5))
	batch.quad(roof, c, d, r0, r1, n2, Vector2(0, 0), Vector2(len_ab, 0), Vector2(len_ab, 2.5), Vector2(0, 2.5))
	# Gable ends in wall colour.
	var g1 := Vector3(c.x - b.x, 0.0, c.z - b.z)
	var gn1 := Vector3(g1.z, 0.0, -g1.x).normalized()
	batch.tri(wall, b, c, r1, gn1, Vector2(0, 0), Vector2(1, 0), Vector2(0.5, 1))
	var g2 := Vector3(a.x - d.x, 0.0, a.z - d.z)
	var gn2 := Vector3(g2.z, 0.0, -g2.x).normalized()
	batch.tri(wall, d, a, r0, gn2, Vector2(0, 0), Vector2(1, 0), Vector2(0.5, 1))


# --- Roads ------------------------------------------------------------------------------------

static func _roads(world: Node3D, res: Resource, mats: Dictionary, cells: Dictionary) -> void:
	var pts: PackedVector2Array = res.get_meta("r_points")
	var offs: PackedInt32Array = res.get_meta("r_offsets")
	var widths: PackedFloat32Array = res.get_meta("r_width")
	var kinds: PackedInt32Array = res.get_meta("r_kind")
	for r in widths.size():
		var line := pts.slice(offs[r], offs[r + 1])
		if line.size() < 2:
			continue
		var samples := PackedVector2Array()
		for s in line.size() - 1:
			var a := line[s]
			var b := line[s + 1]
			var steps := maxi(1, int(a.distance_to(b) / 5.0))
			for k in steps:
				samples.append(a.lerp(b, float(k) / steps))
		samples.append(line[line.size() - 1])
		var half := widths[r] * 0.5
		var mat: Material = mats["dirt"] if kinds[r] == 1 else mats["asphalt"]
		var batch := _cell(cells, line[0])
		var dist := 0.0
		for k in samples.size() - 1:
			var p0 := samples[k]
			var p1 := samples[k + 1]
			var seg := p1 - p0
			var seg_len := seg.length()
			if seg_len < 0.01:
				continue
			var dir0 := (p1 - samples[maxi(k - 1, 0)]).normalized()
			var dir1 := (samples[mini(k + 2, samples.size() - 1)] - p0).normalized()
			var side0 := Vector2(-dir0.y, dir0.x) * half
			var side1 := Vector2(-dir1.y, dir1.x) * half
			var l0 := p0 + side0
			var r0 := p0 - side0
			var l1 := p1 + side1
			var r1 := p1 - side1
			var hl0 := _h(world, l0.x, l0.y)
			var hr0 := _h(world, r0.x, r0.y)
			var hl1 := _h(world, l1.x, l1.y)
			var hr1 := _h(world, r1.x, r1.y)
			if maxf(maxf(hl0, hr0), maxf(hl1, hr1)) < 0.3:
				dist += seg_len
				continue
			var lift := 0.22
			var n := Vector3(0, 1, 0)
			batch.quad(mat,
				Vector3(l0.x, hl0 + lift, l0.y), Vector3(r0.x, hr0 + lift, r0.y),
				Vector3(r1.x, hr1 + lift, r1.y), Vector3(l1.x, hl1 + lift, l1.y), n,
				Vector2(0, dist * 0.25), Vector2(1, dist * 0.25), Vector2(1, (dist + seg_len) * 0.25), Vector2(0, (dist + seg_len) * 0.25))
			dist += seg_len
