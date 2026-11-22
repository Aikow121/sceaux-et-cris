class_name Hud
extends CanvasLayer
## Interface : PV, micro, charge, sorts, états, résultat des incantations, éliminations.

const STATUS_NAMES := {
	"helium": "Voix d'hélium", "swap": "Voix échangée", "chicken": "Poule",
	"shield": "Bouclier", "cage": "En cage",
}

var player: Wizard
var _root: Control
var _hp: Label
var _status: Label
var _mic: ProgressBar
var _charge: ProgressBar
var _spells: Label
var _result: Label
var _result_t := 0.0
var _center: Label
var _center_t := 0.0
var _feed: VBoxContainer
var _pause: Label
var _score: PanelContainer
var _score_grid: GridContainer
var _flash: ColorRect


func _ready() -> void:
	visible = false
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_flash = ColorRect.new()
	_flash.color = Color(1, 0, 0, 0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash)

	var cross := _label(22)
	cross.text = "+"
	_root.add_child(cross)
	cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	cross.grow_horizontal = Control.GROW_DIRECTION_BOTH
	cross.grow_vertical = Control.GROW_DIRECTION_BOTH

	var bl := VBoxContainer.new()
	bl.custom_minimum_size = Vector2(260, 0)
	_root.add_child(bl)
	bl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 20)
	bl.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_status = _label(16)
	_status.modulate = Color(1, 0.8, 1)
	bl.add_child(_status)
	var ml := _label(14)
	ml.text = "Micro"
	bl.add_child(ml)
	_mic = _bar(Color(0.4, 0.9, 0.5))
	bl.add_child(_mic)
	var cl := _label(14)
	cl.text = "Charge du sort"
	bl.add_child(cl)
	_charge = _bar(Color(1.0, 0.7, 0.2))
	bl.add_child(_charge)
	_hp = _label(36)
	bl.add_child(_hp)

	_spells = _label(14)
	_spells.modulate = Color(1, 1, 1, 0.85)
	_root.add_child(_spells)
	_spells.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 20)
	_spells.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_spells.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_spells.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_result = _label(26)
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_result)
	_result.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 110)
	_result.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_result.grow_vertical = Control.GROW_DIRECTION_BEGIN

	_center = _label(30)
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_center)
	_center.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 120)
	_center.grow_horizontal = Control.GROW_DIRECTION_BOTH

	_pause = _label(20)
	_pause.text = "PAUSE — cliquez pour reprendre"
	_root.add_child(_pause)
	_pause.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_pause.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pause.position.y += 60

	var help := _label(13)
	help.modulate = Color(1, 1, 1, 0.65)
	help.text = "ZQSD bouger · Maj courir · Espace sauter · Clic droit (ou V) maintenu : incanter à voix haute · 1-5 : sorts au clavier · T : dessiner un piège · Tab : scores · Échap : souris"
	_root.add_child(help)
	help.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 6)
	help.grow_horizontal = Control.GROW_DIRECTION_BOTH
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN

	_feed = VBoxContainer.new()
	_feed.custom_minimum_size = Vector2(420, 0)
	_root.add_child(_feed)
	_feed.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 20)
	_feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	_score = PanelContainer.new()
	_score.visible = false
	_root.add_child(_score)
	_score.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_score.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_score.grow_vertical = Control.GROW_DIRECTION_BOTH
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 20)
	_score.add_child(m)
	_score_grid = GridContainer.new()
	_score_grid.columns = 3
	_score_grid.add_theme_constant_override("h_separation", 40)
	m.add_child(_score_grid)


func _label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _bar(c: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.max_value = 1.0
	b.show_percentage = false
	b.custom_minimum_size = Vector2(240, 12)
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	b.add_theme_stylebox_override("fill", sb)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _process(delta: float) -> void:
	_flash.color.a = move_toward(_flash.color.a, 0.0, delta * 1.5)
	_result_t -= delta
	_result.modulate.a = clampf(_result_t, 0.0, 1.0)
	_center_t -= delta
	if _center_t <= 0.0:
		_center.text = ""
	_pause.visible = Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not get_parent().draw_ui.is_open()
	_score.visible = Input.is_action_pressed("scoreboard")
	_mic.value = get_parent().voice.level
	if not is_instance_valid(player):
		return
	_hp.text = "PV %d" % maxi(player.hp, 0)
	_hp.modulate = Color(1, 0.4, 0.4) if player.hp <= 30 else Color.WHITE
	_charge.value = player.incant_charge if (player.incanting or player._key_spell != "") else 0.0
	var st := []
	for k in player.statuses:
		var label: String = STATUS_NAMES.get(k, k)
		if k == "swap":
			var other = get_parent().players.get(player.status_extra("swap"))
			if other != null:
				label = "Voix échangée avec %s" % other.display_name
		st.append("%s (%d s)" % [label, ceili(player.statuses[k].t)])
	_status.text = "\n".join(st)
	var lines := []
	for i in Spells.LIST.size():
		var s: Dictionary = Spells.LIST[i]
		var cd: float = player.cooldowns.get(s.id, 0.0)
		var ok: bool = get_parent().recognizer.has_spell(s.id)
		lines.append("%s%s [%d]%s" % [s.name, "" if ok else " (non enregistré)", i + 1, "  %.1fs" % cd if cd > 0.0 else ""])
	_spells.text = "\n".join(lines)


func show_result(text: String, col: Color) -> void:
	_result.text = text
	_result.add_theme_color_override("font_color", col)
	_result_t = 2.5


func show_center(text: String, dur: float) -> void:
	_center.text = text
	_center_t = dur


func flash() -> void:
	_flash.color.a = 0.35


func add_feed(text: String, col := Color.WHITE) -> void:
	var l := _label(17)
	l.text = text
	l.modulate = col
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_feed.add_child(l)
	while _feed.get_child_count() > 6:
		var c := _feed.get_child(0)
		_feed.remove_child(c)
		c.queue_free()
	get_tree().create_timer(7.0).timeout.connect(l.queue_free)


func update_scores(stats: Dictionary) -> void:
	for c in _score_grid.get_children():
		c.queue_free()
	for h in ["Magicien", "Éliminations", "Morts"]:
		var l := _label(20)
		l.text = h
		l.modulate = Color(1, 0.85, 0.4)
		_score_grid.add_child(l)
	var rows := stats.values()
	rows.sort_custom(func(a, b): return a.kills > b.kills)
	for s in rows:
		for v in [s.name, str(s.kills), str(s.deaths)]:
			var l := _label(18)
			l.text = v
			_score_grid.add_child(l)
