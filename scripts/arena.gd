class_name Arena
extends Node3D
## Cour de château : sol dallé, fosse de lave au centre avec un pont,
## piliers et deux estrades avec rampes. Générée de façon identique chez tous.

const HALF := 22.0
const WALL_H := 6.0
const PIT := 5.0               # demi-largeur de la fosse
const LAVA_Y := -1.5
const KILL_Y := -1.0

var spawn_points: Array = []

const TILE_SHADER := """
shader_type spatial;
uniform vec3 base_color : source_color = vec3(0.5);
uniform vec3 line_color : source_color = vec3(0.3);
uniform float cell = 2.0;
varying vec3 wpos;
varying vec3 wnrm;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec3 n = abs(wnrm);
	vec2 uv = n.x > 0.5 ? wpos.zy : (n.y > 0.5 ? wpos.xz : wpos.xy);
	vec2 g = uv / cell;
	vec2 id = floor(g);
	vec2 w = max(fwidth(g), vec2(0.0001));
	vec2 a = abs(fract(g) - 0.5);
	vec2 e = (0.5 - a) / (w * 2.0);
	float line = 1.0 - clamp(min(e.x, e.y), 0.0, 1.0);
	float v = 0.85 + 0.3 * hash(id);
	ALBEDO = mix(base_color * v, line_color, line);
	ROUGHNESS = 0.9;
}
"""

var _shader: Shader


func _ready() -> void:
	_shader = Shader.new()
	_shader.code = TILE_SHADER
	var stone := Color("#9a9184")
	var dark := Color("#5b544b")
	var wood := Color("#7a5532")
	var floor_top := 0.0
	# Sol autour de la fosse (4 dalles)
	var span := HALF * 2.0
	var side := HALF - PIT
	_box(Vector3(0, -0.5, -(PIT + side / 2.0)), Vector3(span, 1, side), stone, dark)
	_box(Vector3(0, -0.5, PIT + side / 2.0), Vector3(span, 1, side), stone, dark)
	_box(Vector3(-(PIT + side / 2.0), -0.5, 0), Vector3(side, 1, PIT * 2.0), stone, dark)
	_box(Vector3(PIT + side / 2.0, -0.5, 0), Vector3(side, 1, PIT * 2.0), stone, dark)
	# Fosse : parois, fond, lave
	_box(Vector3(0, -5.5, 0), Vector3(PIT * 2.0, 1, PIT * 2.0), dark, Color.BLACK)
	_box(Vector3(0, -3, -PIT - 0.25), Vector3(PIT * 2.0, 6, 0.5), dark, Color.BLACK)
	_box(Vector3(0, -3, PIT + 0.25), Vector3(PIT * 2.0, 6, 0.5), dark, Color.BLACK)
	_box(Vector3(-PIT - 0.25, -3, 0), Vector3(0.5, 6, PIT * 2.0), dark, Color.BLACK)
	_box(Vector3(PIT + 0.25, -3, 0), Vector3(0.5, 6, PIT * 2.0), dark, Color.BLACK)
	_lava()
	# Pont étroit au-dessus de la lave
	_box(Vector3(0, -0.3, 0), Vector3(PIT * 2.0, 0.6, 2.2), wood, wood.darkened(0.4), 1.0)
	# Murs d'enceinte
	_box(Vector3(0, WALL_H / 2.0, -HALF - 0.5), Vector3(span + 2, WALL_H, 1), dark, Color("#3c3731"), 1.5)
	_box(Vector3(0, WALL_H / 2.0, HALF + 0.5), Vector3(span + 2, WALL_H, 1), dark, Color("#3c3731"), 1.5)
	_box(Vector3(-HALF - 0.5, WALL_H / 2.0, 0), Vector3(1, WALL_H, span + 2), dark, Color("#3c3731"), 1.5)
	_box(Vector3(HALF + 0.5, WALL_H / 2.0, 0), Vector3(1, WALL_H, span + 2), dark, Color("#3c3731"), 1.5)
	# Piliers
	for x in [-11.0, 11.0]:
		for z in [-11.0, 11.0]:
			_box(Vector3(x, 2.5, z), Vector3(1.8, 5, 1.8), Color("#b3aa9b"), dark, 1.0)
	# Estrades + rampes
	for sz in [-1.0, 1.0]:
		_box(Vector3(0, 1.25, sz * 17.0), Vector3(9, 2.5, 5), stone.lightened(0.1), dark)
		var ramp := _box(Vector3(0, 1.1, sz * 11.9), Vector3(3, 0.4, 6.2), wood, wood.darkened(0.4), 1.0)
		ramp.rotation_degrees.x = -24.0 * sz
	# Caisses pour se cacher
	for p in [Vector3(-16, 0.6, -6), Vector3(16, 0.6, 6), Vector3(-7, 0.6, 15), Vector3(7, 0.6, -15), Vector3(-17, 0.6, 12), Vector3(17, 0.6, -12)]:
		_box(p, Vector3(1.2, 1.2, 1.2), wood, wood.darkened(0.5), 0.6)
	# Points d'apparition (évitent la fosse)
	for i in 8:
		var a := i * TAU / 8.0 + 0.2
		var p := Vector3(cos(a) * 17.0, floor_top + 1.0, sin(a) * 17.0)
		if absf(p.x) < 5.5 and absf(p.z) > 14.0:
			p.y = 3.5   # au-dessus d'une estrade
		spawn_points.append(p)
	spawn_points.append(Vector3(-3, 3.5, 17))
	spawn_points.append(Vector3(3, 3.5, -17))


func _box(pos: Vector3, size: Vector3, base: Color, line: Color, cell := 2.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("base_color", base)
	mat.set_shader_parameter("line_color", line)
	mat.set_shader_parameter("cell", cell)
	mi.material_override = mat
	body.add_child(mi)
	add_child(body)
	return body


func _lava() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(PIT * 2.0, PIT * 2.0)
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#ff5a00")
	mat.emission_enabled = true
	mat.emission = Color("#ff3c00")
	mat.emission_energy_multiplier = 2.5
	mi.material_override = mat
	mi.position = Vector3(0, LAVA_Y, 0)
	add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = Color("#ff6a20")
	light.light_energy = 3.0
	light.omni_range = 9.0
	light.position = Vector3(0, LAVA_Y + 1.0, 0)
	add_child(light)
