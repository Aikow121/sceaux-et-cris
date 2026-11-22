extends Node3D
## Sceaux & Cris — prototype.
## Menu, réseau (ENet), apparitions, sorts, pièges, dégâts, scores, replay.
## Le serveur (l'hôte) décide des touches, dégâts, états et morts.
## Chaque joueur simule son propre déplacement et reconnaît sa propre voix.

const PORT := 7777
const MAX_CLIENTS := 8
const RESPAWN_DELAY := 6.0
const MAX_TRAPS := 3
const ROUND_TIME := 150.0
const INTERMISSION := 8.0
const CROWN_HOME := Vector3(0, 0.45, 0)     # au milieu du pont, au-dessus de la lave !
const PALETTE := [Color("#d64545"), Color("#3f7fd6"), Color("#e0b030"), Color("#4caf50"),
	Color("#9c5bd6"), Color("#e07a30"), Color("#d6488f"), Color("#30b8b0")]

var arena: Arena
var hud: Hud
var voice: VoiceSystem
var recognizer := SpellRecognizer.new()
var draw_ui: DrawUI
var grimoire: GrimoireUI
var players_root: Node3D
var fx_root: Node3D
var players := {}           # nom du nœud -> Wizard
var stats := {}
var projectiles := {}       # id -> Projectile
var traps := {}             # id -> Trap
var last_clip := {}         # magicien -> dernière incantation (16 kHz)
var in_game := false
var mode := "bataille"           # bataille | roi
var rule := "normal"             # règle loufoque de la manche
var rule_map := {}               # Grimoire maudit : sort prononcé -> sort lancé
var round_num := 0
var round_left := 0.0
var intermission := false
var crown_holder := ""
var crown_pos := CROWN_HOME

var _last_attacker := {}    # victime -> [attaquant, heure]
var _next_id := 1
var _bot_count := 0
var _color_i := 0
var _capture_grace := 0.0
var _pending_trap := {}
var _menu_layer: CanvasLayer
var _name_edit: LineEdit
var _ip_edit: LineEdit
var _bots_spin: SpinBox
var _status: Label
var _buttons: Array = []
var _menu_cam: Camera3D
var _orbit := 0.0
var _mode_opt: OptionButton
var _crown: Node3D
var _crown_cd := {}              # magicien -> temps avant de pouvoir reprendre la couronne
var _stats_sync_t := 0.0


func _ready() -> void:
	randomize()
	_setup_input()
	_setup_environment()
	arena = Arena.new()
	arena.name = "Arena"
	add_child(arena)
	players_root = Node3D.new()
	players_root.name = "Players"
	add_child(players_root)
	fx_root = Node3D.new()
	fx_root.name = "FX"
	add_child(fx_root)
	voice = VoiceSystem.new()
	voice.name = "Voice"
	voice.main = self
	add_child(voice)
	recognizer.load_saved()
	hud = Hud.new()
	hud.name = "HUD"
	add_child(hud)
	draw_ui = DrawUI.new()
	add_child(draw_ui)
	draw_ui.finished.connect(_on_drawing_finished)
	draw_ui.cancelled.connect(_on_drawing_cancelled)
	grimoire = GrimoireUI.new()
	grimoire.main = self
	add_child(grimoire)
	_menu_cam = Camera3D.new()
	add_child(_menu_cam)
	_menu_cam.current = true
	_build_menu()
	_build_crown()
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# ================================================================== Mise en place

func _setup_input() -> void:
	_keys("move_forward", [KEY_W, KEY_UP])
	_keys("move_back", [KEY_S, KEY_DOWN])
	_keys("move_left", [KEY_A, KEY_LEFT])
	_keys("move_right", [KEY_D, KEY_RIGHT])
	_keys("jump", [KEY_SPACE])
	_keys("sprint", [KEY_SHIFT])
	_keys("incant", [KEY_V])
	_mouse("incant", MOUSE_BUTTON_RIGHT)
	_keys("draw_trap", [KEY_T])
	_keys("scoreboard", [KEY_TAB])
	for i in 5:
		_keys("spell_%d" % (i + 1), [KEY_1 + i])


func _keys(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k   # position physique : ZQSD en AZERTY = WASD en QWERTY
		InputMap.action_add_event(action, ev)


func _mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func _setup_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#3d6fb5")
	sky_mat.sky_horizon_color = Color("#e8c49a")
	sky_mat.ground_horizon_color = Color("#8a7a66")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 1.1
	sun.light_color = Color("#fff1d6")
	sun.shadow_enabled = true
	add_child(sun)


func _build_menu() -> void:
	_menu_layer = CanvasLayer.new()
	_menu_layer.layer = 10
	add_child(_menu_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_layer.add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.45)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(440, 0)
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)

	var title := Label.new()
	title.text = "SCEAUX & CRIS"
	title.add_theme_font_size_override("font_size", 42)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var sub := Label.new()
	sub.text = "Criez vos sorts. Dessinez vos pièges. Écoutez vos ennemis."
	sub.modulate = Color(1, 1, 1, 0.7)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)

	var gb := Button.new()
	gb.text = "Grimoire vocal (enregistrer mes sorts)"
	gb.pressed.connect(func(): grimoire.open())
	vb.add_child(gb)

	_name_edit = LineEdit.new()
	_name_edit.text = "Mage%d" % randi_range(10, 99)
	_name_edit.placeholder_text = "Pseudo"
	_name_edit.max_length = 16
	vb.add_child(_name_edit)
	var row := HBoxContainer.new()
	var bl := Label.new()
	bl.text = "Mannequins d'entraînement :"
	bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bl)
	_bots_spin = SpinBox.new()
	_bots_spin.max_value = 6
	_bots_spin.value = 2
	row.add_child(_bots_spin)
	vb.add_child(row)

	var solo := Button.new()
	solo.text = "Entraînement solo"
	solo.pressed.connect(_on_solo)
	vb.add_child(solo)
	var host := Button.new()
	host.text = "Héberger une partie (port %d)" % PORT
	host.pressed.connect(_on_host)
	vb.add_child(host)
	var jr := HBoxContainer.new()
	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jr.add_child(_ip_edit)
	var join := Button.new()
	join.text = "Rejoindre"
	join.pressed.connect(_on_join)
	jr.add_child(join)
	vb.add_child(jr)
	_buttons = [solo, host, join]
	var mrow := HBoxContainer.new()
	var mlabel := Label.new()
	mlabel.text = "Mode (hôte) :"
	mlabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mrow.add_child(mlabel)
	_mode_opt = OptionButton.new()
	for k in Spells.MODES:
		_mode_opt.add_item(Spells.MODES[k][0])
	mrow.add_child(_mode_opt)
	vb.add_child(mrow)
	vb.move_child(mrow, vb.get_child_count() - 4)
	_status = Label.new()
	_status.modulate = Color(1, 0.8, 0.4)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_status)
	var help := Label.new()
	help.add_theme_font_size_override("font_size", 13)
	help.modulate = Color(1, 1, 1, 0.75)
	help.text = "Clic droit maintenu : dites votre sort, relâchez. Tenez la voyelle pour le charger !\nMal prononcé = SORT RATÉ (poule, poisson, explosion…).\nT : dessiner un piège sur la surface visée. Tout le monde vous entend parler… selon la distance."
	vb.add_child(help)


# ================================================================== Menu / connexion

func _pname() -> String:
	var n := _name_edit.text.strip_edges()
	return n if n != "" else "Mage"


func _on_solo() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_start_server()


func _on_host() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_CLIENTS)
	if err != OK:
		_status.text = "Impossible d'ouvrir le port %d (erreur %d)" % [PORT, err]
		return
	multiplayer.multiplayer_peer = peer
	_start_server()


func _on_join() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(_ip_edit.text.strip_edges(), PORT)
	if err != OK:
		_status.text = "Adresse invalide (erreur %d)" % err
		return
	multiplayer.multiplayer_peer = peer
	_status.text = "Connexion…"
	for b in _buttons:
		b.disabled = true


func _start_server() -> void:
	mode = Spells.MODES.keys()[_mode_opt.selected]
	_enter_game()
	_server_add("1", _pname(), false, 1)
	for i in int(_bots_spin.value):
		_bot_count += 1
		_server_add("bot_%d" % _bot_count, "Mannequin %d" % _bot_count, true, 1)
	get_tree().create_timer(1.0).timeout.connect(_server_round_start)


func _enter_game() -> void:
	in_game = true
	voice.start_mic()
	_menu_layer.visible = false
	grimoire.visible = false
	hud.visible = true
	get_viewport().gui_release_focus()
	_capture()
	if recognizer.count() == 0:
		hud.show_center("Grimoire vocal vide : utilisez les touches 1 à 5\n(ou enregistrez vos sorts depuis le menu)", 6.0)


func _on_connected() -> void:
	_enter_game()
	register_player.rpc_id(1, _pname())


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_status.text = "Échec de la connexion."
	for b in _buttons:
		b.disabled = false


func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().reload_current_scene()


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	var n := str(id)
	if players.has(n):
		remove_player.rpc(n)
		stats.erase(n)
		sync_stats.rpc(stats)


# ================================================================== Boucle

func _process(delta: float) -> void:
	_capture_grace = maxf(0.0, _capture_grace - delta)
	round_left = maxf(0.0, round_left - delta)
	_update_crown_visual(delta)
	if not in_game:
		_orbit += delta * 0.1
		_menu_cam.position = Vector3(cos(_orbit) * 20.0, 9.0, sin(_orbit) * 20.0)
		_menu_cam.look_at(Vector3(0, 0, 0))


func _physics_process(_delta: float) -> void:
	if not in_game or not multiplayer.is_server():
		return
	_server_round_tick(_delta)
	var now := Time.get_ticks_msec() / 1000.0
	for n in players.keys():
		var p: Wizard = players.get(n)
		if p == null or not p.alive:
			continue
		var pos := p.global_position
		# Lave
		if pos.y < Arena.KILL_Y and absf(pos.x) < Arena.PIT + 0.5 and absf(pos.z) < Arena.PIT + 0.5:
			var killer: String = n
			if _last_attacker.has(n) and now - _last_attacker[n][1] < 7.0:
				killer = _last_attacker[n][0]
			_server_kill(n, killer, "la lave")
			continue
		# Pièges
		for tid in traps.keys():
			var t: Trap = traps.get(tid)
			if t == null or not t.is_armed() or t.owner_name == n:
				continue
			var v := pos - t.global_position
			var along := v.dot(t.normal)
			var lat := (v - t.normal * along).length()
			if along > -0.5 and along < 2.0 and lat < Trap.RADIUS + 0.3:
				_server_trigger_trap(t, p)
				break


func _unhandled_input(event: InputEvent) -> void:
	if not in_game or draw_ui.is_open():
		return
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_capture()
		get_viewport().set_input_as_handled()


func _capture() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_capture_grace = 0.2


func input_enabled() -> bool:
	return in_game and _capture_grace <= 0.0 and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not draw_ui.is_open()


func local_player() -> Wizard:
	return players.get(str(multiplayer.get_unique_id()))


# ================================================================== Joueurs

@rpc("any_peer", "call_remote", "reliable")
func register_player(pname: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	pname = pname.strip_edges().left(16)
	_server_add(str(id), pname if pname != "" else "Mage", false, id)


func _server_add(node_name: String, display: String, is_bot: bool, authority: int) -> void:
	var col: Color = PALETTE[_color_i % PALETTE.size()]
	_color_i += 1
	if authority != 1:
		for n in players:
			var p: Wizard = players[n]
			spawn_player.rpc_id(authority, n, p.display_name, p.is_bot, p.color, p.get_multiplayer_authority(),
				p.global_position, p.rotation.y, p.hp, p.alive)
	var sp := _pick_spawn()
	spawn_player.rpc(node_name, display, is_bot, col, authority, sp, _yaw_to_center(sp), 100, true)
	if authority != 1 and round_num > 0:
		round_started.rpc_id(authority, round_num, mode, rule, rule_map, round_left)
		crown_update.rpc_id(authority, crown_holder, crown_pos)
	stats[node_name] = {"name": display, "kills": 0, "deaths": 0, "points": 0.0}
	sync_stats.rpc(stats)


func _pick_spawn() -> Vector3:
	var best: Vector3 = arena.spawn_points.pick_random()
	var best_s := -1.0
	for i in 6:
		var sp: Vector3 = arena.spawn_points.pick_random()
		var s := 1e9
		for p in players.values():
			if p.alive:
				s = minf(s, p.global_position.distance_to(sp))
		if s > best_s:
			best_s = s
			best = sp
	return best


func _yaw_to_center(p: Vector3) -> float:
	return atan2(p.x, p.z)


@rpc("authority", "call_local", "reliable")
func spawn_player(n: String, display: String, is_bot: bool, col: Color, authority: int,
		pos: Vector3, yaw: float, hp: int, alive: bool) -> void:
	if players.has(n):
		return
	var p := Wizard.new()
	p.name = n
	p.main = self
	p.display_name = display
	p.is_bot = is_bot
	p.color = col
	p.hp = hp
	p.set_multiplayer_authority(authority)
	players_root.add_child(p)
	p.respawn(pos, yaw)
	p.hp = hp
	players[n] = p
	if not alive:
		p.die()
	if p.is_local():
		hud.player = p


@rpc("authority", "call_local", "reliable")
func remove_player(n: String) -> void:
	if players.has(n):
		players[n].queue_free()
		players.erase(n)


@rpc("authority", "call_local", "reliable")
func sync_stats(s: Dictionary) -> void:
	stats = s
	hud.update_scores(stats, mode)


# ================================================================== Voix

## Appelé par VoiceSystem à la réception d'un paquet de voix.
func route_voice(sender: String, samples: PackedFloat32Array) -> void:
	server_on_speaking(sender)
	var p: Wizard = players.get(sender)
	if p == null:
		return
	var target := p
	if p.has_status("swap"):
		var other: Wizard = players.get(p.status_extra("swap"))
		if other != null:
			target = other     # Échange de voix : la voix sort du corps de l'autre !
	target.push_voice(samples)


# ================================================================== Sorts

func request_cast(caster: String, spell: String, power: float, origin: Vector3, dir: Vector3,
		misfire: String, clip: PackedFloat32Array) -> void:
	var max_len := int(3.0 * VoiceSystem.RATE)
	if clip.size() > max_len:
		clip = clip.slice(clip.size() - max_len)
	var data := VoiceSystem.encode(clip)
	if multiplayer.is_server():
		_server_cast(caster, spell, power, origin, dir, misfire, data)
	else:
		rpc_request_cast.rpc_id(1, caster, spell, power, origin, dir, misfire, data)


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_cast(caster: String, spell: String, power: float, origin: Vector3, dir: Vector3,
		misfire: String, data: PackedByteArray) -> void:
	if not multiplayer.is_server() or caster != str(multiplayer.get_remote_sender_id()):
		return
	_server_cast(caster, spell, power, origin, dir, misfire, data)


func _server_cast(caster: String, spell: String, power: float, origin: Vector3, dir: Vector3,
		misfire: String, data: PackedByteArray) -> void:
	var p: Wizard = players.get(caster)
	if p == null or not p.alive:
		return
	power = clampf(power, 0.5, 3.0)
	dir = dir.normalized()
	if caster == crown_holder:
		_server_drop_crown("%s a lancé un sort et perd la couronne !" % p.display_name)
	if origin.distance_to(p.global_position) > 3.0:
		origin = p.head.global_position
	var kind := spell
	match misfire:
		"chicken":
			set_status.rpc(caster, "chicken", 6.0, "")
			kind = "misfire"
		"helium_self":
			set_status.rpc(caster, "helium", 10.0, "")
			kind = "misfire"
		"backfire":
			_server_explode(p.global_position + Vector3.DOWN * 0.5, 0.7, caster, "son propre sort")
			kind = "misfire"
		"fish":
			kind = "fish"
	if spell == "shield":
		set_status.rpc(caster, "shield", 3.0, "")
	var pid := 0
	if kind in ["fireball", "helium", "swap", "fish"]:
		pid = _next_id
		_next_id += 1
	cast_fx.rpc(caster, kind, power, origin, dir, pid, data)


@rpc("authority", "call_local", "reliable")
func cast_fx(caster: String, kind: String, power: float, origin: Vector3, dir: Vector3, pid: int, data: PackedByteArray) -> void:
	if not data.is_empty():
		last_clip[caster] = VoiceSystem.decode(data)
	var cp: Wizard = players.get(caster)
	if cp != null and kind != "misfire":
		cp.play_action("Spellcast_Shoot", 0.6)
	if pid > 0:
		var pr := Projectile.new()
		pr.main = self
		pr.id = pid
		pr.caster = caster
		pr.kind = kind
		pr.power = power
		pr.dir = dir
		fx_root.add_child(pr)
		pr.global_position = origin
		projectiles[pid] = pr
	elif kind == "dash":
		_burst(origin, Color(0.8, 0.95, 1.0), 0.8)
	elif kind == "shield":
		_burst(origin, Color(0.4, 0.7, 1.0), 1.2)
	elif kind == "misfire":
		_burst(origin, Color(1.0, 0.5, 0.9), 0.6)


func server_projectile_hit(pr: Projectile, pos: Vector3, collider: Object) -> void:
	if not multiplayer.is_server() or not projectiles.has(pr.id):
		return
	projectile_end.rpc(pr.id, pos)
	var target: Wizard = collider as Wizard
	match pr.kind:
		"fireball":
			_server_explode(pos, pr.power, pr.caster, "une boule de feu")
		"helium":
			if target != null and target.alive and not target.has_status("shield"):
				set_status.rpc(String(target.name), "helium", 15.0, "")
				_feed_rpc("%s a mis de l'hélium dans la voix de %s" % [_dname(pr.caster), target.display_name])
		"swap":
			if target != null and target.alive and not target.has_status("shield") and String(target.name) != pr.caster:
				set_status.rpc(String(target.name), "swap", 20.0, pr.caster)
				set_status.rpc(pr.caster, "swap", 20.0, String(target.name))
				_feed_rpc("%s et %s ont échangé leurs voix !" % [_dname(pr.caster), target.display_name])
		"fish":
			if target != null and target.alive:
				knockback.rpc(String(target.name), pr.dir * 6.0 + Vector3.UP * 3.0)
				_feed_rpc("%s a reçu un poisson" % target.display_name)


@rpc("authority", "call_local", "reliable")
func projectile_end(pid: int, pos: Vector3) -> void:
	var pr: Projectile = projectiles.get(pid)
	if pr == null:
		return
	projectiles.erase(pid)
	if pr.kind == "helium":
		_burst(pos, Color(1.0, 0.5, 0.9), 0.7)
	elif pr.kind == "swap":
		_burst(pos, Color(0.4, 1.0, 0.6), 0.7)
	pr.queue_free()


func _server_explode(pos: Vector3, power: float, attacker: String, cause: String) -> void:
	var radius := 2.0 * pow(power, 0.6) + 0.8
	explosion_fx.rpc(pos, radius)
	for n in players.keys():
		var p: Wizard = players[n]
		if not p.alive:
			continue
		var d := p.global_position.distance_to(pos)
		if d > radius + 0.4 or p.has_status("shield"):
			continue
		var away := (p.global_position - pos + Vector3.UP * 0.6).normalized()
		knockback.rpc(n, away * (7.0 + 5.0 * power) + Vector3.UP * 4.0)
		var dmg := int(38.0 * pow(power, 0.7) * (1.0 - 0.5 * clampf(d / radius, 0.0, 1.0)))
		_server_damage(n, dmg, attacker, cause)


func _server_damage(victim: String, dmg: int, attacker: String, cause: String) -> void:
	var p: Wizard = players.get(victim)
	if p == null or not p.alive:
		return
	if attacker != victim:
		_last_attacker[victim] = [attacker, Time.get_ticks_msec() / 1000.0]
	var hp := p.hp - dmg
	sync_hp.rpc(victim, hp)
	if hp <= 0:
		_server_kill(victim, attacker, cause)


func _server_kill(victim: String, killer: String, cause: String) -> void:
	var p: Wizard = players.get(victim)
	if p == null or not p.alive:
		return
	if victim == crown_holder:
		_server_drop_crown("%s perd la couronne !" % p.display_name)
	if stats.has(victim):
		stats[victim].deaths += 1
	if killer != victim and stats.has(killer):
		stats[killer].kills += 1
	player_died.rpc(victim, killer, cause)
	sync_stats.rpc(stats)
	_last_attacker.erase(victim)
	get_tree().create_timer(RESPAWN_DELAY).timeout.connect(func():
		if players.has(victim):
			var sp := _pick_spawn()
			respawn_player.rpc(victim, sp, _yaw_to_center(sp)))


@rpc("authority", "call_local", "reliable")
func sync_hp(n: String, hp: int) -> void:
	var p: Wizard = players.get(n)
	if p == null:
		return
	if hp < p.hp and p.is_local():
		hud.flash()
	if hp < p.hp and hp > 0:
		p.play_action("Hit_A", 0.4)
	p.hp = hp


@rpc("authority", "call_local", "reliable")
func knockback(n: String, v: Vector3) -> void:
	var p: Wizard = players.get(n)
	if p != null and p.is_multiplayer_authority():
		p.apply_knockback(v * (1.8 if rule == "lune" else 1.0))


@rpc("authority", "call_local", "reliable")
func set_status(n: String, status: String, duration: float, extra: String) -> void:
	var p: Wizard = players.get(n)
	if p == null:
		return
	p.set_status(status, duration, extra)
	if p.is_local():
		match status:
			"helium":
				hud.show_center("Votre voix est devenue suraiguë !", 3.0)
			"swap":
				hud.show_center("Vos voix sont échangées avec %s !" % _dname(extra), 3.0)
			"chicken":
				hud.show_center("Vous êtes une poule ! (pas de sorts)", 3.0)
			"cage":
				hud.show_center("Pris dans une cage !", 2.0)


@rpc("authority", "call_local", "reliable")
func player_died(victim: String, killer: String, cause: String) -> void:
	var v: Wizard = players.get(victim)
	if v == null:
		return
	var was_local := v.is_local()
	v.die()
	var text := ""
	if killer == victim or not players.has(killer):
		text = "%s s'est éliminé tout seul (%s)" % [v.display_name, cause]
	else:
		text = "%s a eu %s (%s)" % [_dname(killer), v.display_name, cause]
	hud.add_feed(text, Color(1, 0.85, 0.6))
	if was_local:
		# Replay du « dernier mot » : l'incantation du tueur, puis vos dernières paroles
		var clips := []
		if killer != victim and last_clip.has(killer):
			clips.append(last_clip[killer])
		clips.append(voice.last_words())
		voice.play_clips(clips)
		hud.show_center("%s\n\nReplay : son incantation… puis vos derniers mots." % text, RESPAWN_DELAY)
	elif players.has(killer) and players[killer].is_local():
		hud.show_center("Vous avez éliminé %s !" % v.display_name, 2.0)


@rpc("authority", "call_local", "reliable")
func respawn_player(n: String, pos: Vector3, yaw: float) -> void:
	var p: Wizard = players.get(n)
	if p != null:
		p.respawn(pos, yaw)


func _feed_rpc(text: String) -> void:
	feed.rpc(text)


@rpc("authority", "call_local", "reliable")
func feed(text: String) -> void:
	hud.add_feed(text)


func _dname(n: String) -> String:
	var p: Wizard = players.get(n)
	return p.display_name if p != null else "?"


# ================================================================== Pièges dessinés

func start_drawing(p: Wizard) -> void:
	if not p.alive or p.has_status("chicken") or draw_ui.is_open():
		return
	var from := p.camera.global_position
	var to := from - p.camera.global_transform.basis.z * 6.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, [p.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		hud.show_result("Visez une surface proche (sol, mur…) pour y dessiner.", Color(0.9, 0.9, 0.9))
		return
	_pending_trap = {"pos": hit.position, "normal": hit.normal}
	p.drawing = true
	if p.incanting:
		p._finish_incantation(true)
	draw_ui.open()


func _on_drawing_finished(points: PackedVector2Array, result: Dictionary) -> void:
	var p := local_player()
	_capture()
	if p == null or not p.alive:
		return
	p.drawing = false
	var shape: String = result.shape
	var power := 1.0
	if result.score < Gesture.MIN_SCORE:
		shape = ""
		hud.show_result("Dessin raté (%d %%) … il vous explose au nez !" % int(result.score * 100), Color(1, 0.5, 0.4))
	else:
		power = remap(clampf(result.score, Gesture.MIN_SCORE, 0.96), Gesture.MIN_SCORE, 0.96, 0.7, 1.4)
		hud.show_result("Sceau : %s (qualité %d %%)" % [Gesture.SHAPES[shape], int(result.score * 100)], Color(0.6, 1, 0.6))
	var args := [String(p.name), shape, power, _pending_trap.pos, _pending_trap.normal, points]
	if multiplayer.is_server():
		callv("_server_trap", args)
	else:
		rpc_request_trap.rpc_id(1, args[0], args[1], args[2], args[3], args[4], args[5])


func _on_drawing_cancelled() -> void:
	var p := local_player()
	if p != null:
		p.drawing = false
	_capture()


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_trap(owner_n: String, shape: String, power: float, pos: Vector3, normal: Vector3, points: PackedVector2Array) -> void:
	if not multiplayer.is_server() or owner_n != str(multiplayer.get_remote_sender_id()):
		return
	_server_trap(owner_n, shape, power, pos, normal, points)


func _server_trap(owner_n: String, shape: String, power: float, pos: Vector3, normal: Vector3, points: PackedVector2Array) -> void:
	var p: Wizard = players.get(owner_n)
	if p == null or not p.alive or p.global_position.distance_to(pos) > 9.0:
		return
	if shape == "" or not Gesture.SHAPES.has(shape):
		_server_explode(p.global_position, 0.5, owner_n, "un dessin raté")
		return
	# Au plus MAX_TRAPS pièges par magicien : le plus ancien disparaît
	var mine := []
	for tid in traps:
		if traps[tid].owner_name == owner_n:
			mine.append(tid)
	mine.sort()
	while mine.size() >= MAX_TRAPS:
		remove_trap.rpc(mine.pop_front(), false)
	var tid := _next_id
	_next_id += 1
	spawn_trap.rpc(tid, owner_n, shape, clampf(power, 0.5, 1.5), pos, normal, points)


@rpc("authority", "call_local", "reliable")
func spawn_trap(tid: int, owner_n: String, shape: String, power: float, pos: Vector3, normal: Vector3, points: PackedVector2Array) -> void:
	var t := Trap.new()
	t.id = tid
	t.owner_name = owner_n
	t.shape = shape
	t.power = power
	t.points = points
	var lp := local_player()
	t.mine = lp != null and String(lp.name) == owner_n
	fx_root.add_child(t)
	t.place(pos, normal)
	traps[tid] = t


@rpc("authority", "call_local", "reliable")
func remove_trap(tid: int, triggered: bool) -> void:
	var t: Trap = traps.get(tid)
	if t == null:
		return
	traps.erase(tid)
	if triggered:
		_burst(t.global_position, Trap.COLORS.get(t.shape, Color.WHITE), 1.5)
	t.queue_free()


func _server_trigger_trap(t: Trap, victim: Wizard) -> void:
	var n := String(victim.name)
	var owner_n := t.owner_name
	var pos := t.global_position
	var normal := t.normal
	remove_trap.rpc(t.id, true)
	_feed_rpc("%s est tombé dans le piège de %s (%s)" % [victim.display_name, _dname(owner_n), Gesture.SHAPES[t.shape]])
	if victim.has_status("shield"):
		return
	match t.shape:
		"pentacle":
			_server_explode(pos + normal * 0.3, 1.3 * t.power, owner_n, "un pentacle")
		"triangle":
			knockback.rpc(n, normal * (15.0 + 6.0 * t.power) + Vector3.UP * 6.0)
			_server_damage(n, 8, owner_n, "une catapulte")
		"carre":
			set_status.rpc(n, "cage", 3.5, "")
			_server_damage(n, 10, owner_n, "une cage")
		"cercle":
			set_status.rpc(n, "chicken", 8.0, "")


# ================================================================== Effets visuels

@rpc("authority", "call_local", "reliable")
func explosion_fx(pos: Vector3, radius: float) -> void:
	_burst(pos, Color(1.0, 0.5, 0.15), radius)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.3)
	l.light_energy = 6.0
	l.omni_range = radius * 3.0
	fx_root.add_child(l)
	l.global_position = pos
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.4)
	tw.tween_callback(l.queue_free)


func _burst(pos: Vector3, col: Color, radius: float) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(col.r, col.g, col.b, 0.8)
	mi.material_override = m
	fx_root.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.2
	var tw := create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius, 0.25)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.45)
	tw.chain().tween_callback(mi.queue_free)


# ================================================================== Manches et règles loufoques

func gravity_scale() -> float:
	return 0.4 if rule == "lune" else 1.0


func remap_spell(id: String) -> String:
	return rule_map.get(id, id)


func _server_round_start() -> void:
	if not multiplayer.is_server():
		return
	round_num += 1
	var choices := Spells.RULES.keys()
	if round_num > 1:
		choices.erase(rule)
	var new_rule: String = "normal" if round_num == 1 and players.size() <= 1 else choices.pick_random()
	var new_map := {}
	if new_rule == "maudit":
		var ids := []
		for sdef in Spells.LIST:
			ids.append(sdef.id)
		var shuffled := ids.duplicate()
		while shuffled == ids:
			shuffled.shuffle()
		for i in ids.size():
			new_map[ids[i]] = shuffled[i]
	for n in stats:
		stats[n].kills = 0
		stats[n].deaths = 0
		stats[n].points = 0.0
	for tid in traps.keys():
		remove_trap.rpc(tid, false)
	round_started.rpc(round_num, mode, new_rule, new_map, ROUND_TIME)
	for n in players:
		var sp := _pick_spawn()
		respawn_player.rpc(n, sp, _yaw_to_center(sp))
		if new_rule == "poulailler":
			set_status.rpc(n, "chicken", 20.0, "")
	_crown_cd.clear()
	crown_update.rpc("", CROWN_HOME)
	sync_stats.rpc(stats)


@rpc("authority", "call_local", "reliable")
func round_started(num: int, m: String, r: String, rmap: Dictionary, time_left: float) -> void:
	round_num = num
	mode = m
	rule = r
	rule_map = rmap
	round_left = time_left
	intermission = false
	var rd: Array = Spells.RULES[r]
	var md: Array = Spells.MODES[m]
	hud.set_round("MANCHE %d — %s · %s" % [num, md[0], rd[0]], "%s\n%s" % [rd[1], md[1]])
	hud.show_center("MANCHE %d\n%s\n%s" % [num, rd[0].to_upper(), rd[1]], 5.0)


func _server_round_tick(delta: float) -> void:
	if round_num == 0:
		return
	if not intermission and round_left <= 0.0:
		intermission = true
		var best := ""
		var best_score := -INF
		for n in stats:
			var sc: float = stats[n].points if mode == "roi" else stats[n].kills * 100.0 - stats[n].deaths
			if sc > best_score:
				best_score = sc
				best = n
		round_ended.rpc(best)
		get_tree().create_timer(INTERMISSION).timeout.connect(_server_round_start)
		return
	if intermission or mode != "roi":
		return
	# Roi du silence : ramassage et points
	for k in _crown_cd.keys():
		_crown_cd[k] -= delta
		if _crown_cd[k] <= 0.0:
			_crown_cd.erase(k)
	if crown_holder == "":
		for n in players:
			var p: Wizard = players[n]
			if p.alive and not _crown_cd.has(n) and p.global_position.distance_to(crown_pos) < 1.4:
				crown_update.rpc(n, crown_pos)
				feed.rpc("%s prend la couronne… chut !" % p.display_name)
				break
	elif stats.has(crown_holder):
		stats[crown_holder].points += delta
	_stats_sync_t -= delta
	if _stats_sync_t <= 0.0:
		_stats_sync_t = 1.0
		sync_stats.rpc(stats)


@rpc("authority", "call_local", "reliable")
func round_ended(winner: String) -> void:
	intermission = true
	round_left = 0.0
	var w: Wizard = players.get(winner)
	var wname := w.display_name if w != null else "Personne"
	hud.show_center("FIN DE LA MANCHE\n%s gagne !\n\nProchaine manche dans %d s…" % [wname, int(INTERMISSION)], INTERMISSION)
	hud.show_scores_for(INTERMISSION)
	if w != null:
		w.play_action("Cheer", INTERMISSION)


# ================================================================== Roi du silence

## Appelé quand un magicien parle (voix reçue par le serveur, ou voix de l'hôte).
func server_on_speaking(n: String) -> void:
	if multiplayer.is_server() and mode == "roi" and n == crown_holder and crown_holder != "":
		_server_drop_crown("%s a parlé… et perd la couronne !" % _dname(n))


## Appelé par VoiceSystem quand le joueur local parle.
func on_local_voice_activity() -> void:
	if in_game and multiplayer.is_server():
		server_on_speaking(str(multiplayer.get_unique_id()))


func _server_drop_crown(msg: String) -> void:
	if crown_holder == "":
		return
	var p: Wizard = players.get(crown_holder)
	var pos := CROWN_HOME
	if p != null:
		pos = p.global_position + Vector3.DOWN * 0.45
		if absf(pos.x) < Arena.PIT + 0.5 and absf(pos.z) < Arena.PIT + 0.5 and (absf(pos.z) > 1.1 or pos.y < -0.5):
			pos = CROWN_HOME   # tombée dans la lave : elle revient sur le pont
	_crown_cd[crown_holder] = 2.0
	crown_update.rpc("", pos)
	feed.rpc(msg)


@rpc("authority", "call_local", "reliable")
func crown_update(holder: String, pos: Vector3) -> void:
	crown_holder = holder
	crown_pos = pos
	var lp := local_player()
	if lp != null and holder == String(lp.name):
		hud.show_center("Vous avez la couronne !\nNE DITES PLUS UN MOT.", 3.0)


func _build_crown() -> void:
	_crown = Node3D.new()
	add_child(_crown)
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color("#ffcc33")
	gold.metallic = 0.9
	gold.roughness = 0.25
	gold.emission_enabled = true
	gold.emission = Color("#ffb000")
	gold.emission_energy_multiplier = 0.6
	var ring := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.3
	cm.bottom_radius = 0.3
	cm.height = 0.18
	ring.mesh = cm
	ring.material_override = gold
	_crown.add_child(ring)
	for i in 5:
		var spike := MeshInstance3D.new()
		var sm := CylinderMesh.new()
		sm.top_radius = 0.0
		sm.bottom_radius = 0.08
		sm.height = 0.22
		spike.mesh = sm
		spike.material_override = gold
		var a := i * TAU / 5.0
		spike.position = Vector3(cos(a) * 0.26, 0.19, sin(a) * 0.26)
		_crown.add_child(spike)
	var l := OmniLight3D.new()
	l.light_color = Color("#ffd060")
	l.light_energy = 1.5
	l.omni_range = 4.0
	_crown.add_child(l)
	_crown.visible = false


func _update_crown_visual(delta: float) -> void:
	_crown.visible = in_game and mode == "roi" and round_num > 0
	if not _crown.visible:
		return
	var holder: Wizard = players.get(crown_holder)
	if holder != null and holder.alive:
		_crown.global_position = holder.global_position + Vector3.UP * (1.25 if not holder.is_local() else 3.0)
		_crown.visible = not holder.is_local()
	else:
		_crown.global_position = crown_pos + Vector3.UP * (0.15 + sin(Time.get_ticks_msec() / 400.0) * 0.08)
	_crown.rotate_y(delta * 1.5)
