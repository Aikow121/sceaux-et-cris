class_name Wizard
extends CharacterBody3D
## Un magicien (joueur humain ou mannequin d'entraînement).
## Le pair qui le possède le simule ; les autres interpolent sa position.

const WALK := 7.0
const SPRINT := 10.0
const INCANT_SLOW := 0.55
const ACCEL := 60.0
const AIR_ACCEL := 20.0
const GRAVITY := 20.0
const JUMP := 7.5
const MOUSE_SENS := 0.0022
const PITCH_MAX := 1.55
const HEAD_Y := 0.6
const MAGE_SCENE := preload("res://assets/kaykit/Mage.glb")   # KayKit (CC0) — Kay Lousberg
const MODEL_SCALE := 0.72
const LOOPING := ["Idle", "Running_A", "Walking_A", "Walking_Backwards", "Jump_Idle", "Spellcasting", "Cheer"]

var main: Node
var display_name := "Magicien"
var is_bot := false
var color := Color.WHITE
var hp := 100
var alive := true
var statuses := {}          # nom -> { "t": durée restante, "extra": String }
var cooldowns := {}         # sort -> temps restant (local)
var incanting := false
var incant_charge := 0.0    # affiché aux autres (orbe au-dessus de la tête)
var drawing := false

var head: Node3D
var camera: Camera3D
var voice_out: AudioStreamPlayer3D
var _voice_playback: AudioStreamGeneratorPlayback
var _bus_name := ""
var _pitch_fx: AudioEffectPitchShift

var _shape: CollisionShape3D
var _wizard_vis: Node3D
var _model: Node3D
var _anim: AnimationPlayer
var _anim_lock := 0.0
var _remote_vel := Vector3.ZERO
var _last_pos := Vector3.ZERO
var _chicken_vis: Node3D
var _label: Label3D
var _speak_label: Label3D
var _wand: Node3D
var _wand_tip: MeshInstance3D
var _orb: MeshInstance3D
var _shield_vis: MeshInstance3D
var _cage_vis: Node3D

var _stun := 0.0
var _speak_t := 0.0
var _key_spell := ""
var _key_t := 0.0
var _net_xform := Transform3D.IDENTITY
var _net_pitch := 0.0
var _has_net := false
var _bot_t := 0.0
var _bot_dir := Vector2.ZERO


func is_local() -> bool:
	return is_multiplayer_authority() and not is_bot


func has_status(s: String) -> bool:
	return statuses.has(s)


func status_extra(s: String) -> String:
	return statuses[s].extra if statuses.has(s) else ""


# ------------------------------------------------------------------ Construction

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.3

	_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	_shape.shape = cap
	add_child(_shape)

	head = Node3D.new()
	head.position = Vector3(0, HEAD_Y, 0)
	add_child(head)
	camera = Camera3D.new()
	camera.fov = 80
	camera.near = 0.05
	head.add_child(camera)

	_build_wizard()
	_build_chicken()
	_build_wand()

	_label = Label3D.new()
	_label.text = display_name
	_label.modulate = color
	_label.outline_size = 8
	_label.font_size = 44
	_label.pixel_size = 0.006
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0, 1.65, 0)
	add_child(_label)
	_speak_label = Label3D.new()
	_speak_label.text = "« … »"
	_speak_label.font_size = 40
	_speak_label.pixel_size = 0.006
	_speak_label.outline_size = 8
	_speak_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_speak_label.position = Vector3(0, 1.95, 0)
	_speak_label.visible = false
	add_child(_speak_label)

	_orb = _sphere(0.18, Color(1.0, 0.8, 0.3), true)
	_orb.position = Vector3(0, 2.3, 0)
	_orb.visible = false
	add_child(_orb)
	_shield_vis = _sphere(1.2, Color(0.4, 0.7, 1.0, 0.25), true)
	_shield_vis.visible = false
	add_child(_shield_vis)
	_cage_vis = Node3D.new()
	for i in 8:
		var a := i * TAU / 8.0
		var bar := _cylinder(0.04, 2.2, Color(0.55, 0.55, 0.6))
		bar.position = Vector3(cos(a) * 0.75, 0.1, sin(a) * 0.75)
		_cage_vis.add_child(bar)
	_cage_vis.visible = false
	add_child(_cage_vis)

	# Voix (proximité)
	voice_out = AudioStreamPlayer3D.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = VoiceSystem.RATE
	gen.buffer_length = 0.5
	voice_out.stream = gen
	voice_out.unit_size = 6.0
	voice_out.max_distance = 45.0
	voice_out.max_db = 6.0
	voice_out.position = Vector3(0, HEAD_Y, 0)
	_bus_name = "Voix_" + String(name)
	var idx := AudioServer.get_bus_index(_bus_name)
	if idx == -1:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, _bus_name)
		AudioServer.set_bus_send(idx, "Master")
		var fx := AudioEffectPitchShift.new()
		AudioServer.add_bus_effect(idx, fx)
	_pitch_fx = AudioServer.get_bus_effect(idx, 0)
	AudioServer.set_bus_effect_enabled(idx, 0, false)
	voice_out.bus = _bus_name
	add_child(voice_out)
	voice_out.play()
	_voice_playback = voice_out.get_stream_playback()

	if is_local():
		camera.current = true
		_wizard_vis.visible = false
		_label.visible = false
	_net_xform = global_transform
	_refresh_visuals()


func _exit_tree() -> void:
	var idx := AudioServer.get_bus_index(_bus_name)
	if idx > 0:
		AudioServer.remove_bus(idx)


func _mat(c: Color, glow := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glow:
		m.emission_enabled = true
		m.emission = Color(c.r, c.g, c.b)
		m.emission_energy_multiplier = 2.0
	return m


func _sphere(r: float, c: Color, glow := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	mi.mesh = sm
	mi.material_override = _mat(c, glow)
	return mi


func _cylinder(r: float, h: float, c: Color, top := -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r if top < 0.0 else top
	cm.bottom_radius = r
	cm.height = h
	mi.mesh = cm
	mi.material_override = _mat(c)
	return mi


func _build_wizard() -> void:
	# Modèle animé KayKit, robe et chapeau teintés à la couleur du joueur
	_wizard_vis = Node3D.new()
	add_child(_wizard_vis)
	_model = MAGE_SCENE.instantiate()
	_model.scale = Vector3.ONE * MODEL_SCALE
	_model.position.y = -0.9
	_model.rotation.y = PI            # le modèle regarde vers +Z
	_wizard_vis.add_child(_model)
	for hidden in ["2H_Staff", "Spellbook", "Spellbook_open"]:
		var n := _model.find_child(hidden, true, false)
		if n:
			n.visible = false
	for part in ["Mage_Body", "Mage_Cape", "Mage_Hat"]:
		var mi := _model.find_child(part, true, false) as MeshInstance3D
		if mi and mi.mesh:
			var m := (mi.mesh.surface_get_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
			m.albedo_color = color.lightened(0.25)
			mi.material_override = m
	_anim = _model.find_child("AnimationPlayer", true, false)
	for a in LOOPING:
		if _anim.has_animation(a):
			_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	_anim.play("Idle")


## Joue une animation ponctuelle (lancer de sort, coup reçu…)
func play_action(anim_name: String, lock := 0.5) -> void:
	if _anim == null or not _anim.has_animation(anim_name):
		return
	_anim.play(anim_name, 0.1)
	_anim_lock = lock


func _update_animation(delta: float) -> void:
	if _anim == null or not _wizard_vis.visible:
		return
	_anim_lock -= delta
	if _anim_lock > 0.0:
		return
	var vel := velocity if is_multiplayer_authority() else _remote_vel
	var flat := Vector3(vel.x, 0, vel.z)
	var local_v := global_transform.basis.inverse() * flat
	var want := "Idle"
	if incanting or _key_spell != "":
		want = "Spellcasting"
	elif absf(vel.y) > 2.5:
		want = "Jump_Idle"
	elif flat.length() > 0.8:
		if local_v.z > 0.5 and absf(local_v.z) > absf(local_v.x):
			want = "Walking_Backwards"
		else:
			want = "Running_A" if flat.length() > 4.0 else "Walking_A"
	if _anim.current_animation != want:
		_anim.play(want, 0.15)


func _build_chicken() -> void:
	_chicken_vis = Node3D.new()
	add_child(_chicken_vis)
	var body := _sphere(0.4, Color(0.97, 0.97, 0.95))
	body.position.y = -0.45
	_chicken_vis.add_child(body)
	var hd := _sphere(0.2, Color(0.97, 0.97, 0.95))
	hd.position = Vector3(0, 0.05, -0.25)
	_chicken_vis.add_child(hd)
	var beak := _cylinder(0.07, 0.16, Color("#ffa500"), 0.0)
	beak.rotation_degrees.x = -90
	beak.position = Vector3(0, 0.03, -0.48)
	_chicken_vis.add_child(beak)
	var comb := _sphere(0.08, Color("#e02020"))
	comb.position = Vector3(0, 0.27, -0.25)
	_chicken_vis.add_child(comb)
	_chicken_vis.visible = false


func _build_wand() -> void:
	_wand = Node3D.new()
	_wand.position = Vector3(0.28, -0.25, -0.45)
	_wand.rotation_degrees = Vector3(-60, 0, 0)
	head.add_child(_wand)
	var stick := _cylinder(0.018, 0.45, Color("#5a3a1e"), 0.012)
	_wand.add_child(stick)
	_wand_tip = _sphere(0.035, Color(1.0, 0.85, 0.4), true)
	_wand_tip.position.y = 0.24
	_wand.add_child(_wand_tip)


# ------------------------------------------------------------------ Voix

func push_voice(samples: PackedFloat32Array) -> void:
	_speak_t = 0.3
	if _voice_playback == null:
		return
	var n := samples.size()
	if not _voice_playback.can_push_buffer(n):
		return
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		buf[i] = Vector2(samples[i], samples[i])
	_voice_playback.push_buffer(buf)


func _update_voice_fx() -> void:
	var idx := AudioServer.get_bus_index(_bus_name)
	if idx < 0:
		return
	var pitch := 1.0
	if has_status("helium"):
		pitch = 1.9
	elif has_status("chicken"):
		pitch = 1.45
	_pitch_fx.pitch_scale = pitch
	AudioServer.set_bus_effect_enabled(idx, 0, pitch != 1.0)


# ------------------------------------------------------------------ Entrées

func _unhandled_input(event: InputEvent) -> void:
	if not is_local() or not alive or drawing:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENS)
		head.rotation.x = clampf(head.rotation.x - event.relative.y * MOUSE_SENS, -PITCH_MAX, PITCH_MAX)


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	for k in cooldowns.keys():
		cooldowns[k] -= delta
		if cooldowns[k] <= 0.0:
			cooldowns.erase(k)
	_stun = maxf(0.0, _stun - delta)
	if not alive:
		return

	var move := Vector2.ZERO
	var jump := false
	var sprint := false
	if is_bot:
		_bot_t -= delta
		if _bot_t <= 0.0:
			_bot_t = randf_range(1.0, 3.0)
			_bot_dir = Vector2.from_angle(randf() * TAU) if randf() < 0.8 else Vector2.ZERO
			if global_position.length() > 18.0:
				var to_c := -Vector2(global_position.x, global_position.z).normalized()
				_bot_dir = to_c
		move = _bot_dir
		jump = randf() < 0.004
		_bot_move(delta, move, jump)
	else:
		if main.input_enabled() and not drawing:
			move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
			jump = Input.is_action_just_pressed("jump")
			sprint = Input.is_action_pressed("sprint")
			_handle_casting_input(delta)
			if Input.is_action_just_pressed("draw_trap"):
				main.start_drawing(self)
		elif incanting:
			_finish_incantation(true)
		_move(delta, move, jump, sprint)

	if global_position.y < -8.0:
		global_position = Vector3(0, 2, 15)   # sécurité
	if not multiplayer.get_peers().is_empty():
		net_state.rpc(global_transform, head.rotation.x, incant_charge if incanting else -1.0, drawing)


func _move(delta: float, input: Vector2, jump: bool, sprint: bool) -> void:
	if has_status("cage") or drawing:
		input = Vector2.ZERO
		jump = false
	var speed := SPRINT if sprint else WALK
	if incanting:
		speed *= INCANT_SLOW
	if has_status("chicken"):
		speed *= 1.15
	var wish := (transform.basis * Vector3(input.x, 0, input.y))
	wish.y = 0.0
	wish = wish.limit_length(1.0)
	var horiz := Vector3(velocity.x, 0, velocity.z)
	if is_on_floor():
		var acc := ACCEL * (0.15 if _stun > 0.0 else 1.0)
		horiz = horiz.move_toward(wish * speed, acc * delta)
		if jump:
			velocity.y = JUMP * (1.3 if has_status("chicken") else 1.0)
	else:
		if wish != Vector3.ZERO:
			var add := clampf(speed - horiz.dot(wish), 0.0, AIR_ACCEL * delta)
			horiz += wish * add
		velocity.y -= GRAVITY * main.gravity_scale() * delta
	velocity.x = horiz.x
	velocity.z = horiz.z
	move_and_slide()


func _bot_move(delta: float, input: Vector2, jump: bool) -> void:
	var wish := Vector3(input.x, 0, input.y) * WALK * 0.6
	if has_status("cage"):
		wish = Vector3.ZERO
	var horiz := Vector3(velocity.x, 0, velocity.z)
	if is_on_floor():
		horiz = horiz.move_toward(wish, ACCEL * (0.15 if _stun > 0.0 else 1.0) * delta)
		if jump:
			velocity.y = JUMP
	else:
		velocity.y -= GRAVITY * main.gravity_scale() * delta
	velocity.x = horiz.x
	velocity.z = horiz.z
	if wish.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-wish.x, -wish.z), delta * 4.0)
	move_and_slide()


func apply_knockback(v: Vector3) -> void:
	velocity += v
	_stun = 0.5
	if v.y > 0.0 and is_on_floor():
		global_position += Vector3.UP * 0.05


# ------------------------------------------------------------------ Lancer des sorts

func _can_cast() -> bool:
	return alive and not has_status("chicken") and not drawing


func _handle_casting_input(delta: float) -> void:
	# Incantation vocale : maintenir clic droit (ou V), dire le mot, relâcher.
	if Input.is_action_just_pressed("incant") and _can_cast():
		if main.voice.enabled and main.recognizer.count() > 0:
			incanting = true
			main.voice.begin_utterance()
		else:
			main.hud.show_result("Enregistrez d'abord vos sorts dans le Grimoire vocal (menu).\nTouches 1 à 5 en attendant.", Color(1, 0.8, 0.4))
	if incanting:
		incant_charge = clampf(main.voice.utterance_length() / 2.5, 0.0, 1.0)
		if Input.is_action_just_released("incant"):
			_finish_incantation(false)
	# Clavier (sans micro) : maintenir 1..5 pour charger, relâcher pour lancer
	for i in Spells.LIST.size():
		var act := "spell_%d" % (i + 1)
		if Input.is_action_just_pressed(act) and _can_cast() and not incanting:
			_key_spell = Spells.LIST[i].id
			_key_t = 0.0
		if _key_spell == Spells.LIST[i].id:
			_key_t += delta
			incant_charge = clampf(_key_t / 2.0, 0.0, 1.0)
			if Input.is_action_just_released(act):
				var power := clampf(0.7 + _key_t, 0.7, 2.7)
				_key_spell = ""
				incant_charge = 0.0
				cast_spell(main.remap_spell(Spells.LIST[i].id), power, PackedFloat32Array())


func _finish_incantation(cancel: bool) -> void:
	incanting = false
	incant_charge = 0.0
	var clip: PackedFloat32Array = main.voice.end_utterance()
	if cancel:
		return
	var info := SpellRecognizer.analyze(VoiceSystem.to_8k(clip))
	if info.feat.is_empty():
		main.hud.show_result("… (rien entendu)", Color(0.8, 0.8, 0.8))
		return
	var res: Dictionary = main.recognizer.classify(info.feat)
	if not res.ok:
		misfire(clip)
		return
	var power := Spells.power_from_voice(info.duration, info.level)
	match main.rule:
		"chuchotements":
			if info.level > Spells.WHISPER_MAX:
				misfire(clip, "Trop fort ! (volume %d %%) Il fallait chuchoter…" % int(info.level * 100))
				return
		"opera":
			if info.duration < 0.9:
				misfire(clip, "Trop court ! Ici, il faut CHANTER et tenir la note…")
				return
			power *= 1.5
	cast_spell(main.remap_spell(res.id), power, clip)


func cast_spell(id: String, power: float, clip: PackedFloat32Array) -> void:
	var def := Spells.get_def(id)
	if def.is_empty():
		return
	if cooldowns.has(id):
		main.hud.show_result("%s : encore %.1f s" % [def.name, cooldowns[id]], Color(0.8, 0.8, 0.8))
		return
	cooldowns[id] = def.cooldown
	var dir := -camera.global_transform.basis.z
	if id == "dash":
		velocity = dir * (12.0 + 5.0 * power) + Vector3.UP * 3.0
		_stun = 0.35
	main.hud.show_result("%s !  x%.1f" % [def.word.to_upper(), power], color.lightened(0.3))
	main.request_cast(String(name), id, power, _wand_tip.global_position, dir, "", clip)


func misfire(clip: PackedFloat32Array, reason := "") -> void:
	var kind: String = Spells.MISFIRES.pick_random()
	main.hud.show_result((reason + "\n" if reason != "" else "") + Spells.MISFIRE_TEXT[kind], Color(1, 0.5, 0.4))
	main.request_cast(String(name), "", 0.7, _wand_tip.global_position, -camera.global_transform.basis.z, kind, clip)


# ------------------------------------------------------------------ États

func set_status(s: String, duration: float, extra := "") -> void:
	if duration <= 0.0:
		statuses.erase(s)
	else:
		statuses[s] = {"t": duration, "extra": extra}
	if s == "chicken" and is_local() and incanting:
		_finish_incantation(true)
	_refresh_visuals()


func _refresh_visuals() -> void:
	if _wizard_vis == null:
		return
	var chicken := has_status("chicken")
	_chicken_vis.visible = alive and chicken and not is_local()
	_wizard_vis.visible = not chicken and not is_local() and (alive or _anim_lock > 0.0)
	_wand.visible = alive and not chicken and is_local()
	_label.visible = alive and not is_local()
	_shield_vis.visible = alive and has_status("shield")
	_cage_vis.visible = alive and has_status("cage")
	_update_voice_fx()


func die() -> void:
	alive = false
	incanting = false
	drawing = false
	velocity = Vector3.ZERO
	statuses.clear()
	_shape.set_deferred("disabled", true)
	if not is_local():
		play_action("Death_A", 2.5)
		_anim.queue("Death_A_Pose")
	_refresh_visuals()
	get_tree().create_timer(2.5).timeout.connect(func():
		if is_instance_valid(self) and not alive:
			_wizard_vis.visible = false)


func respawn(pos: Vector3, yaw: float) -> void:
	alive = true
	hp = 100
	statuses.clear()
	cooldowns.clear()
	velocity = Vector3.ZERO
	global_position = pos
	rotation = Vector3(0, yaw, 0)
	head.rotation.x = 0.0
	_net_xform = global_transform
	_shape.set_deferred("disabled", false)
	_anim_lock = 0.0
	_refresh_visuals()


# ------------------------------------------------------------------ Réseau / rendu

@rpc("authority", "call_remote", "unreliable_ordered")
func net_state(xf: Transform3D, pitch: float, charge: float, is_drawing: bool) -> void:
	_net_xform = xf
	_net_pitch = pitch
	_has_net = true
	incanting = charge >= 0.0
	incant_charge = maxf(charge, 0.0)
	drawing = is_drawing


func _process(delta: float) -> void:
	if not is_multiplayer_authority() and _has_net:
		var t := clampf(delta * 18.0, 0.0, 1.0)
		global_transform = global_transform.interpolate_with(_net_xform, t)
		head.rotation.x = lerpf(head.rotation.x, _net_pitch, t)
	if delta > 0.0:
		_remote_vel = _remote_vel.lerp((global_position - _last_pos) / delta, clampf(delta * 10.0, 0.0, 1.0))
		_last_pos = global_position
	_update_animation(delta)
	# Durée des états (localement chez tout le monde)
	var changed := false
	for k in statuses.keys():
		statuses[k].t -= delta
		if statuses[k].t <= 0.0:
			statuses.erase(k)
			changed = true
	if changed:
		_refresh_visuals()
	# Orbe d'incantation visible par tous, baguette qui brille
	var charging := incanting or _key_spell != ""
	_orb.visible = alive and charging and not is_local()
	var s := 1.0 + incant_charge * 3.0
	_orb.scale = Vector3.ONE * s
	_wand_tip.scale = Vector3.ONE * (1.0 + (incant_charge * 4.0 if charging else 0.0))
	_speak_t -= delta
	_speak_label.visible = alive and _speak_t > 0.0 and not is_local()
	if drawing and not is_local():
		_speak_label.visible = true
		_speak_label.text = "(dessine…)"
	else:
		_speak_label.text = "« … »"
