class_name Projectile
extends Node3D
## Projectile de sort. Il vole en ligne droite chez tout le monde ;
## seul le serveur détecte les touches et décide de l'effet.

var main: Node
var id := 0
var caster := ""
var kind := "fireball"      # fireball | helium | swap | fish
var power := 1.0
var dir := Vector3.FORWARD
var speed := 26.0
var life := 4.0
var _spin := 0.0
var _mesh: MeshInstance3D


func _ready() -> void:
	match kind:
		"fireball":
			speed = 24.0
			_mesh = _ball(0.22 * pow(power, 0.7), Color(1.0, 0.45, 0.1))
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.5, 0.2)
			l.light_energy = 2.0
			l.omni_range = 4.0 * pow(power, 0.5)
			add_child(l)
		"helium":
			speed = 32.0
			_mesh = _ball(0.18, Color(1.0, 0.5, 0.9))
		"swap":
			speed = 32.0
			_mesh = _ball(0.18, Color(0.4, 1.0, 0.6))
		"fish":
			speed = 12.0
			_mesh = MeshInstance3D.new()
			var cap := CapsuleMesh.new()
			cap.radius = 0.12
			cap.height = 0.55
			_mesh.mesh = cap
			_mesh.rotation_degrees.x = 90
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.5, 0.65, 0.8)
			m.metallic = 0.6
			_mesh.material_override = m
			add_child(_mesh)


func _ball(r: float, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 3.0
	mi.material_override = m
	add_child(mi)
	return mi


func _physics_process(delta: float) -> void:
	life -= delta
	var from := global_position
	var v := dir * speed
	if kind == "fish":
		dir = (dir + Vector3.DOWN * delta * 0.6).normalized()
		_spin += delta * 12.0
		_mesh.rotation.z = _spin
	var to := from + v * delta
	if multiplayer.is_server():
		var exclude: Array[RID] = []
		var c: Node = main.players.get(caster)
		if c != null:
			exclude.append(c.get_rid())
		var q := PhysicsRayQueryParameters3D.create(from, to, 3, exclude)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			main.server_projectile_hit(self, hit.position, hit.collider)
			return
		if life <= 0.0:
			main.server_projectile_hit(self, to, null)
			return
	elif life <= -1.0:
		queue_free()
		return
	global_position = to
