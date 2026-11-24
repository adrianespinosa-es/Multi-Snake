extends SubViewportContainer
## Fondo 3D animado del menu: serpientes redondeadas deslizandose sobre un suelo azul pastel.

const SEGMENTS := 26
const STEP := 0.1            # distancia entre puntos del rastro
const PER_SEG := 8           # puntos de rastro entre un segmento y el siguiente
const SPEED := 2.8
const MAX_TRAIL := PER_SEG * SEGMENTS + 20

var vp: SubViewport
var cam: Camera3D
var snakes: Array = []
var foods: Array = []
var time := 0.0

var params: Array = [
	{"A": 8.5, "B": 3.6, "fa": 0.31, "fb": 0.47, "pa": 0.0, "pb": 1.0, "oz": -1.0},
	{"A": 7.0, "B": 4.2, "fa": 0.23, "fb": 0.37, "pa": 2.0, "pb": 0.5, "oz": 1.5},
	{"A": 9.5, "B": 3.0, "fa": 0.27, "fb": 0.41, "pa": 4.0, "pb": 2.2, "oz": 3.0},
	{"A": 6.0, "B": 4.5, "fa": 0.35, "fb": 0.29, "pa": 5.5, "pb": 3.7, "oz": -3.0},
]


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_2X
	vp.gui_disable_input = true
	add_child(vp)
	_build_scene()


func set_active(on: bool) -> void:
	visible = on
	set_process(on)
	if vp != null:
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED


# ---------------------------------------------------------------- escena
func _build_scene() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.78, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.86, 0.93, 1.0)
	env.ambient_light_energy = 0.75
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -28, 0)
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	vp.add_child(sun)

	cam = Camera3D.new()
	cam.fov = 48.0
	cam.position = Vector3(0, 11, 12)
	vp.add_child(cam)
	cam.look_at(Vector3(0, 0, 0.5))

	# suelo con tablero suave
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
uniform vec3 col_a : source_color = vec3(0.80, 0.90, 0.99);
uniform vec3 col_b : source_color = vec3(0.73, 0.85, 0.97);
void fragment() {
	vec2 c = floor(UV * 30.0);
	float k = mod(c.x + c.y, 2.0);
	ALBEDO = mix(col_a, col_b, k);
	ROUGHNESS = 0.95;
}
"""
	var gmat := ShaderMaterial.new()
	gmat.shader = shader
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	plane.mesh = pm
	plane.material_override = gmat
	vp.add_child(plane)

	# serpientes con 4 colores distintos
	var idx: Array = []
	for i in Session.palette.size():
		idx.append(i)
	idx.shuffle()
	for k in 4:
		_make_snake(k, Session.palette[idx[k]])

	# cubitos flotantes
	var fcols := [Color(0.16, 0.20, 0.34), Color(0.97, 0.97, 1.0), Color(1.0, 0.75, 0.25)]
	for i in 12:
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.6, 0.6, 0.6)
		m.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = fcols[i % fcols.size()]
		mat.roughness = 0.4
		m.material_override = mat
		m.position = Vector3(randf_range(-12.0, 12.0), 0.6, randf_range(-6.5, 6.5))
		vp.add_child(m)
		foods.append({"node": m, "phase": randf() * TAU})


func _make_snake(k: int, col: Color) -> void:
	var s := {"p": params[k], "tt": float(params[k]["pa"]), "trail": [], "head": Vector3.ZERO, "nodes": [], "radii": []}
	for j in SEGMENTS:
		var f := float(j) / float(SEGMENTS - 1)
		var r := lerpf(0.62, 0.34, f)
		var sp := SphereMesh.new()
		sp.radius = r
		sp.height = r * 2.0
		sp.radial_segments = 24
		sp.rings = 12
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col.lightened(0.40).lerp(col.darkened(0.45), f)   # morro claro -> cola oscura
		mat.roughness = 0.32
		var mi := MeshInstance3D.new()
		mi.mesh = sp
		mi.material_override = mat
		s["radii"].append(r)
		if j == 0:
			var holder := Node3D.new()
			holder.add_child(mi)
			_add_eyes(holder, r)
			vp.add_child(holder)
			s["nodes"].append(holder)
		else:
			vp.add_child(mi)
			s["nodes"].append(mi)
	for i in 260:   # calentamiento: rellena el rastro
		_advance(s, 0.05)
	snakes.append(s)


func _add_eyes(holder: Node3D, r: float) -> void:
	var white := StandardMaterial3D.new()
	white.albedo_color = Color.WHITE
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.08, 0.08, 0.12)
	for sx in [-1.0, 1.0]:
		var e := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.19
		em.height = 0.38
		e.mesh = em
		e.material_override = white
		e.position = Vector3(sx * 0.3, r * 0.45, -r * 0.62)
		holder.add_child(e)
		var p := MeshInstance3D.new()
		var pm := SphereMesh.new()
		pm.radius = 0.1
		pm.height = 0.2
		p.mesh = pm
		p.material_override = black
		p.position = Vector3(sx * 0.3, r * 0.47, -r * 0.62 - 0.14)
		holder.add_child(p)


# ---------------------------------------------------------------- movimiento
func _path(p: Dictionary, tt: float) -> Vector3:
	return Vector3(p["A"] * sin(p["fa"] * tt + p["pa"]), 0.0, p["B"] * sin(p["fb"] * tt + p["pb"]) + p["oz"])


func _advance(s: Dictionary, dt: float) -> void:
	var p: Dictionary = s["p"]
	var trail: Array = s["trail"]
	var remaining := SPEED * dt
	while remaining > 0.0:
		var stepd := minf(remaining, 0.05)
		remaining -= stepd
		var tt: float = s["tt"]
		var vx: float = p["A"] * p["fa"] * cos(p["fa"] * tt + p["pa"])
		var vz: float = p["B"] * p["fb"] * cos(p["fb"] * tt + p["pb"])
		var v := maxf(sqrt(vx * vx + vz * vz), 0.25)
		tt += stepd / v
		s["tt"] = tt
		var h := _path(p, tt)
		s["head"] = h
		if trail.is_empty() or h.distance_to(trail[trail.size() - 1]) >= STEP:
			trail.append(h)
			if trail.size() > MAX_TRAIL:
				trail.pop_front()


func _update_nodes(s: Dictionary) -> void:
	var trail: Array = s["trail"]
	var n := trail.size()
	if n < PER_SEG * SEGMENTS:
		return
	var h: Vector3 = s["head"]
	var last: Vector3 = trail[n - 1]
	var f := minf(h.distance_to(last) / STEP, 1.0)
	var nodes: Array = s["nodes"]
	var radii: Array = s["radii"]
	for j in nodes.size():
		var pos: Vector3 = h
		if j > 0:
			var kf := float(j * PER_SEG) - f
			var k0 := int(floor(kf))
			var u := kf - float(k0)
			var ia := maxi(n - 1 - k0, 0)
			var ib := maxi(ia - 1, 0)
			pos = Vector3(trail[ia]).lerp(trail[ib], u)
		var bump := maxf(0.0, sin(time * 3.0 - float(j) * 0.5)) * 0.15
		pos.y = float(radii[j]) + bump
		var node: Node3D = nodes[j]
		node.position = pos
		if j == 0:
			var back: Vector3 = trail[n - 3]
			var dir := h - back
			dir.y = 0.0
			if dir.length() > 0.001:
				node.look_at(pos + dir.normalized(), Vector3.UP)


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	time += delta
	for s in snakes:
		_advance(s, delta)
		_update_nodes(s)
	for f in foods:
		var m: MeshInstance3D = f["node"]
		m.rotation.y += delta * 1.2
		m.position.y = 0.6 + 0.18 * sin(time * 2.0 + float(f["phase"]))
	cam.position = Vector3(sin(time * 0.15) * 1.5, 11.0, 12.0 + cos(time * 0.12) * 0.8)
	cam.look_at(Vector3(0, 0, 0.5))
