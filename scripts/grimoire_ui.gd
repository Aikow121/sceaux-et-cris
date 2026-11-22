class_name GrimoireUI
extends CanvasLayer
## « Grimoire vocal » : le joueur enregistre ses propres mots pour chaque sort
## (maintenir le bouton, parler, relâcher). 2 enregistrements par sort conseillés.

var main: Node
var _rows := {}         # id -> { "count": Label }
var _meter: ProgressBar
var _result: Label
var _recording_id := ""


func _ready() -> void:
	layer = 20
	visible = false
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.custom_minimum_size = Vector2(640, 0)
	margin.add_child(vb)

	var title := Label.new()
	title.text = "GRIMOIRE VOCAL"
	title.add_theme_font_size_override("font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var help := Label.new()
	help.text = "Maintenez « Enregistrer », dites le mot du sort, relâchez. Faites-le 2 fois par sort.\nVous pouvez choisir vos propres mots ! Évitez des mots qui se ressemblent."
	help.modulate = Color(1, 1, 1, 0.75)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(help)

	var mic_row := HBoxContainer.new()
	var ml := Label.new()
	ml.text = "Micro :"
	mic_row.add_child(ml)
	_meter = ProgressBar.new()
	_meter.max_value = 1.0
	_meter.show_percentage = false
	_meter.custom_minimum_size = Vector2(0, 16)
	_meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mic_row.add_child(_meter)
	vb.add_child(mic_row)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	vb.add_child(grid)
	for s in Spells.LIST:
		var name_l := Label.new()
		name_l.text = "%s  (« %s »)" % [s.name, s.word]
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(name_l)
		var count := Label.new()
		count.custom_minimum_size = Vector2(90, 0)
		grid.add_child(count)
		var rec := Button.new()
		rec.text = "Enregistrer (maintenir)"
		rec.button_down.connect(_start_rec.bind(s.id))
		rec.button_up.connect(_stop_rec.bind(s.id))
		grid.add_child(rec)
		var clr := Button.new()
		clr.text = "Effacer"
		clr.pressed.connect(_clear.bind(s.id))
		grid.add_child(clr)
		_rows[s.id] = {"count": count}

	var test := Button.new()
	test.text = "TESTER (maintenir et dire un sort)"
	test.button_down.connect(_start_rec.bind("__test"))
	test.button_up.connect(_stop_rec.bind("__test"))
	vb.add_child(test)
	_result = Label.new()
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.add_theme_font_size_override("font_size", 18)
	vb.add_child(_result)
	var close := Button.new()
	close.text = "Fermer"
	close.pressed.connect(func(): visible = false)
	vb.add_child(close)


func open() -> void:
	main.voice.start_mic()
	visible = true
	_refresh()
	if not main.voice.enabled:
		_result.text = "Micro indisponible."


func _process(_delta: float) -> void:
	if visible and main != null:
		_meter.value = main.voice.level


func _refresh() -> void:
	for id in _rows:
		var n: int = main.recognizer.templates.get(id, []).size()
		var l: Label = _rows[id].count
		l.text = "%d / 2" % mini(n, 3)
		l.modulate = Color(0.5, 1, 0.5) if n >= 2 else (Color(1, 0.9, 0.4) if n == 1 else Color(1, 0.5, 0.5))


func _start_rec(id: String) -> void:
	_recording_id = id
	main.voice.begin_utterance()
	_result.text = "J'écoute…"
	_result.modulate = Color.WHITE


func _stop_rec(id: String) -> void:
	if _recording_id != id:
		return
	_recording_id = ""
	var clip: PackedFloat32Array = main.voice.end_utterance()
	var info := SpellRecognizer.analyze(VoiceSystem.to_8k(clip))
	if info.feat.is_empty():
		_result.text = "Je n'ai rien entendu. Parlez plus fort ou maintenez plus longtemps."
		_result.modulate = Color(1, 0.6, 0.5)
		return
	if id == "__test":
		var r: Dictionary = main.recognizer.classify(info.feat)
		var def := Spells.get_def(r.id)
		if r.ok:
			_result.text = "Reconnu : %s  (puissance x%.1f, écart %.1f)" % [def.name, Spells.power_from_voice(info.duration, info.level), r.dist]
			_result.modulate = Color(0.5, 1, 0.5)
		else:
			_result.text = "Pas sûr… (le plus proche : %s, écart %.1f) → en jeu, ce serait un SORT RATÉ !" % [def.get("name", "?"), r.dist]
			_result.modulate = Color(1, 0.6, 0.5)
		return
	main.recognizer.add_template(id, info.feat)
	main.recognizer.save()
	_result.text = "Enregistré pour %s." % Spells.get_def(id).name
	_result.modulate = Color(0.5, 1, 0.5)
	_refresh()


func _clear(id: String) -> void:
	main.recognizer.clear_spell(id)
	main.recognizer.save()
	_refresh()
